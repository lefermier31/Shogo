/*
 * Server tick fix.
 *
 * LithTech 1.0 runs the local server once per rendered frame and clamps the
 * server delta to [floor, ceiling] (0.01 s / 0.2 s). Above ~100 fps every
 * frame still advances the world by the floor, so the game runs fast.
 *
 * We redirect the single direct call to the server update (CServerMgr::Update,
 * __thiscall(this, flags, float now)) to a wrapper that skips the call while
 * less than one floor of engine time has elapsed since the last real update.
 * The engine computes its delta from the last call it actually received, so
 * the next real update covers all the elapsed time and the clamp never kicks
 * in: the world runs at real speed, at most ~100 updates per second, which is
 * what multiplayer clients already get. Nothing is written to the constants.
 */
#include "shogofps.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* CServerMgr field offsets, cross-checked against the code before use. */
#define OFF_NOWORLD 0x190
#define OFF_PAUSE   0x194
#define OFF_DEMO    0x198
#define OFF_TIMEOFS 0x1F8
#define OFF_GAMETIME 0x20C
#define OFF_LAST    0x218

#define FLOOR_BITS 0x3C23D70Au /* 0.01f */
#define CEIL_BITS  0x3E4CCCCDu /* 0.2f  */

#define MAX_SET 8
#define MAX_REFS 512
#define MAX_CALLS 4096
#define CLAMP_PAIR_SPAN 0x60
#define CLUSTER_GAP 0x60
#define FUNC_WINDOW 0x1000
#define FOCUS_SPAN 0x100

typedef unsigned int (__attribute__((thiscall)) *update_fn)(void *self, unsigned int flags, float now);

typedef struct {
    uint32_t a[MAX_SET];
    int n;
} addrset;

typedef struct {
    uint32_t a[MAX_REFS];
    int n;      /* stored */
    int total;  /* found */
} reflist;

typedef struct {
    uint32_t target, site;
} callrec;

static update_fn g_orig;
static uint8_t *g_site;
static int32_t g_orig_rel;
static float g_floor = 0.01f;
static float g_threshold = 0.01f;
static int g_installed;
static int g_skip_enabled;
static int g_have_gametime;
static int g_have_state;

static uint8_t *g_last_self;
static double g_last_pass_qpc;
static int g_checks, g_mismatch;
static unsigned g_active_passes; /* first ones are warm-up, kept out of the speed figure */

static float g_prev_now;
static int g_have_prev_now;
static double g_prev_active_qpc;
static int g_prev_active_valid;

static struct {
    double start;
    unsigned frames, passes, skips, valve, inactive;
    double game_inc, real_active;
    float min_inc, max_inc;
    double orig_num, orig_den;
} W;

static uint32_t va(const uint8_t *p)
{
    return (uint32_t)(uintptr_t)p;
}

static void set_add(addrset *s, uint32_t v)
{
    if (s->n < MAX_SET)
        s->a[s->n++] = v;
}

static int set_has(const addrset *s, uint32_t v)
{
    int i;
    for (i = 0; i < s->n; i++)
        if (s->a[i] == v)
            return 1;
    return 0;
}

/* 4-byte aligned dwords with the given value outside code. */
static void find_dwords(const pe_t *pe, uint32_t value, addrset *out)
{
    int i;
    uint32_t j;
    memset(out, 0, sizeof *out);
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        if (r->exec)
            continue;
        for (j = 0; j + 4 <= r->size; j += 4)
            if (*(const uint32_t *)(r->ptr + j) == value)
                set_add(out, va(r->ptr + j));
    }
}

/* Start addresses of NUL-terminated strings containing `needle`, outside code. */
static void find_strings(const pe_t *pe, const char *needle, addrset *out)
{
    size_t nl = strlen(needle);
    int i;
    uint32_t j;
    memset(out, 0, sizeof *out);
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        if (r->exec || r->size < nl)
            continue;
        for (j = 0; j + nl <= r->size; j++) {
            if (r->ptr[j] == (uint8_t)needle[0] && memcmp(r->ptr + j, needle, nl) == 0) {
                uint32_t k = j, back = 0;
                while (k > 0 && r->ptr[k - 1] != 0 && back < 64) {
                    k--;
                    back++;
                }
                if (back < 64 && !set_has(out, va(r->ptr + k)))
                    set_add(out, va(r->ptr + k));
            }
        }
    }
}

/* Every 4-byte window in code equal to one of the targets (operand references). */
static void find_refs(const pe_t *pe, const addrset *targets, reflist *out)
{
    int i;
    uint32_t j;
    memset(out, 0, sizeof *out);
    if (targets->n == 0)
        return;
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        if (!r->exec || r->size < 4)
            continue;
        for (j = 0; j + 4 <= r->size; j++) {
            if (set_has(targets, *(const uint32_t *)(r->ptr + j))) {
                out->total++;
                if (out->n < MAX_REFS)
                    out->a[out->n++] = va(r->ptr + j);
            }
        }
    }
}

static int any_ref_in(const reflist *l, uint32_t lo, uint32_t hi)
{
    int i;
    for (i = 0; i < l->n; i++)
        if (l->a[i] >= lo && l->a[i] < hi)
            return 1;
    return 0;
}

static int contains_dword(const uint8_t *lo, const uint8_t *hi, uint32_t v)
{
    const uint8_t *p;
    for (p = lo; p + 4 <= hi; p++)
        if (*(const uint32_t *)p == v)
            return 1;
    return 0;
}

static int looks_like_func_start(const pe_t *pe, uint32_t t)
{
    const uint8_t *p = (const uint8_t *)(uintptr_t)t;
    if ((t & 15) == 0)
        return 1;
    if (!pe_in_exec(pe, p - 3, 3))
        return 0;
    return p[-1] == 0xCC || p[-1] == 0x90 || p[-1] == 0xC3 || p[-3] == 0xC2;
}

static int cmp_u32(const void *a, const void *b)
{
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return x < y ? -1 : x > y;
}

static callrec g_calls[MAX_CALLS];

/* Returns 1 and fills func/site when the server update call is identified. */
static int locate_update_call(const pe_t *pe, uint32_t *func_out, uint32_t *site_out)
{
    addrset floors, ceils, s_ratio, s_gtime, s_focus;
    reflist r_floor, r_ceil, r_ratio, r_gtime, r_focus;
    uint32_t pts[64], clamp = 0, lo, func = 0, site = 0;
    int npts = 0, i, j, nclusters, ncalls = 0, accepted = 0;
    uint8_t *fp, *fend;

    find_dwords(pe, FLOOR_BITS, &floors);
    find_dwords(pe, CEIL_BITS, &ceils);
    find_refs(pe, &floors, &r_floor);
    find_refs(pe, &ceils, &r_ceil);
    log_printf("scan: floor constant x%d, ceiling constant x%d, code refs %d / %d",
               floors.n, ceils.n, r_floor.total, r_ceil.total);
    if (!floors.n || !ceils.n) {
        log_printf("scan: clamp constants not found, server tick fix not applied");
        return 0;
    }

    for (i = 0; i < r_floor.n; i++)
        for (j = 0; j < r_ceil.n; j++) {
            uint32_t f = r_floor.a[i], c = r_ceil.a[j];
            uint32_t d = f > c ? f - c : c - f;
            if (d <= CLAMP_PAIR_SPAN && npts < 64)
                pts[npts++] = f < c ? f : c;
        }
    qsort(pts, npts, sizeof pts[0], cmp_u32);
    nclusters = npts ? 1 : 0;
    for (i = 1; i < npts; i++)
        if (pts[i] - pts[i - 1] > CLUSTER_GAP)
            nclusters++;
    if (nclusters != 1) {
        log_printf("scan: %d clamp candidates (need exactly 1), server tick fix not applied",
                   nclusters);
        return 0;
    }
    clamp = pts[0];
    log_printf("scan: clamp at %08X", clamp);

    find_strings(pe, "Guaranteed ratio", &s_ratio);
    find_strings(pe, "Game time", &s_gtime);
    find_strings(pe, "alwaysfocused", &s_focus);
    find_refs(pe, &s_ratio, &r_ratio);
    find_refs(pe, &s_gtime, &r_gtime);
    find_refs(pe, &s_focus, &r_focus);
    log_printf("scan: anchors 'Guaranteed ratio' %d/%d, 'Game time' %d/%d, 'alwaysfocused' %d/%d",
               s_ratio.n, r_ratio.total, s_gtime.n, r_gtime.total, s_focus.n, r_focus.total);
    if (!r_ratio.n && !r_focus.n) {
        log_printf("scan: no usable anchor string, server tick fix not applied");
        return 0;
    }
    if (g_cfg.strict && (!r_ratio.n || !r_focus.n)) {
        log_printf("scan: strict mode needs both anchors, server tick fix not applied");
        return 0;
    }

    /* Direct calls whose target lies shortly before the clamp. */
    lo = clamp > FUNC_WINDOW ? clamp - FUNC_WINDOW : 0;
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        uint32_t k;
        if (!r->exec || r->size < 5)
            continue;
        for (k = 0; k + 5 <= r->size; k++) {
            if (r->ptr[k] == 0xE8) {
                uint32_t s = va(r->ptr + k);
                uint32_t t = s + 5 + (uint32_t)(*(const int32_t *)(r->ptr + k + 1));
                if (t >= lo && t <= clamp && ncalls < MAX_CALLS) {
                    g_calls[ncalls].target = t;
                    g_calls[ncalls].site = s;
                    ncalls++;
                }
            }
        }
    }

    for (i = 0; i < ncalls; i++) {
        uint32_t t = g_calls[i].target, only_site = 0;
        int nsites = 0, dup = 0, focus_ok = 0, ratio_ok;
        for (j = 0; j < i; j++)
            if (g_calls[j].target == t)
                dup = 1;
        if (dup || !looks_like_func_start(pe, t))
            continue;
        for (j = 0; j < ncalls; j++) {
            if (g_calls[j].target != t)
                continue;
            nsites++;
            only_site = g_calls[j].site;
            if (r_focus.n && any_ref_in(&r_focus, g_calls[j].site - FOCUS_SPAN, g_calls[j].site))
                focus_ok = 1;
        }
        ratio_ok = any_ref_in(&r_ratio, t, clamp);
        if (nsites != 1)
            continue;
        if ((r_ratio.n && !ratio_ok) || (r_focus.n && !focus_ok))
            continue;
        accepted++;
        func = t;
        site = only_site;
    }
    if (accepted != 1) {
        log_printf("scan: %d candidate update functions (need exactly 1), server tick fix not applied",
                   accepted);
        return 0;
    }
    if (r_gtime.n && !any_ref_in(&r_gtime, clamp, clamp + FUNC_WINDOW))
        log_printf("scan: warning, 'Game time' not referenced after the clamp");

    /* The wrapper reads these fields: the function must use them. */
    fp = (uint8_t *)(uintptr_t)func;
    fend = (uint8_t *)(uintptr_t)clamp + 0x300;
    for (i = 0; i < pe->nranges; i++)
        if (pe->r[i].exec && fp >= pe->r[i].ptr && fp < pe->r[i].ptr + pe->r[i].size &&
            fend > pe->r[i].ptr + pe->r[i].size)
            fend = pe->r[i].ptr + pe->r[i].size;
    if (!contains_dword(fp, fend, OFF_TIMEOFS) || !contains_dword(fp, fend, OFF_LAST)) {
        log_printf("scan: update function does not use the expected fields, server tick fix not applied");
        return 0;
    }
    g_have_gametime = contains_dword(fp, fend, OFF_GAMETIME);
    g_have_state = contains_dword(fp, fend, OFF_NOWORLD) && contains_dword(fp, fend, OFF_PAUSE) &&
                   contains_dword(fp, fend, OFF_DEMO);

    g_floor = *(const float *)(uintptr_t)floors.a[0];
    *func_out = func;
    *site_out = site;
    log_printf("scan: update function %08X (RVA %06X), call site %08X (RVA %06X), game time field %s, state fields %s",
               func, func - va(pe->base), site, site - va(pe->base),
               g_have_gametime ? "yes" : "no", g_have_state ? "yes" : "no");
    log_hex("scan: call site bytes", (const uint8_t *)(uintptr_t)site - 8, 21);
    log_hex("scan: function start", fp, 16);
    return 1;
}

static int special_state(const uint8_t *o)
{
    if (!g_have_state)
        return 0;
    return *(const int32_t *)(o + OFF_NOWORLD) != 0 ||
           (*(const uint32_t *)(o + OFF_PAUSE) & 1) ||
           (*(const uint32_t *)(o + OFF_DEMO) & 0xC);
}

static void self_check(const uint8_t *o, float now_arg)
{
    float last = *(const volatile float *)(o + OFF_LAST);
    float expect = now_arg + *(const volatile float *)(o + OFF_TIMEOFS);
    if (g_checks >= 32)
        return;
    g_checks++;
    if (fabsf(last - expect) > 1e-5f * (1.0f + fabsf(expect)))
        g_mismatch++;
    if (g_checks >= 8 && g_mismatch * 4 > g_checks && g_skip_enabled) {
        g_skip_enabled = 0;
        log_printf("self-check FAILED (%d/%d): the engine does not store its last time where expected, "
                   "skipping disabled, game behaves as without ShogoFPS", g_mismatch, g_checks);
    } else if (g_checks == 32) {
        log_printf("self-check ok (%d/32 mismatches)", g_mismatch);
    }
}

static unsigned int do_pass(uint8_t *o, unsigned int flags, float now)
{
    double q = qpc_seconds();
    int active = !(flags & 1) && !special_state(o);
    float gt_before = g_have_gametime ? *(volatile float *)(o + OFF_GAMETIME) : 0.0f;
    unsigned int ret = g_orig(o, flags, now);

    if (o != g_last_self) {
        g_last_self = o;
        g_prev_active_valid = 0;
    }
    g_last_pass_qpc = q;
    W.passes++;
    if (active) {
        self_check(o, now);
        if (g_have_gametime) {
            float inc = *(volatile float *)(o + OFF_GAMETIME) - gt_before;
            if (g_prev_active_valid && g_active_passes > 20 && inc >= 0.0f && inc <= 0.25f) {
                W.game_inc += inc;
                W.real_active += q - g_prev_active_qpc;
                if (inc < W.min_inc)
                    W.min_inc = inc;
                if (inc > W.max_inc)
                    W.max_inc = inc;
            }
        }
        g_prev_active_qpc = q;
        g_prev_active_valid = 1;
        g_active_passes++;
    } else {
        W.inactive++;
        g_prev_active_valid = 0;
    }
    return ret;
}

static unsigned int __attribute__((thiscall)) GAME_ENTRY
update_wrapper(void *self, unsigned int flags, float now)
{
    uint8_t *o = (uint8_t *)self;
    unsigned int ret;

    timing_init_late();
    W.frames++;

    /* What the unpatched engine would do at this frame rate. */
    if (g_have_prev_now) {
        float df = now - g_prev_now;
        if (df >= 0.0f && df < 1.0f) {
            W.orig_den += df;
            W.orig_num += df < g_floor ? g_floor : df;
        }
    }
    g_prev_now = now;
    g_have_prev_now = 1;

    if (g_skip_enabled && o == g_last_self && !(flags & 1) && !special_state(o)) {
        volatile float t = now + *(volatile float *)(o + OFF_TIMEOFS);
        volatile float d = t - *(volatile float *)(o + OFF_LAST);
        if (d >= 0.0f && d < g_threshold) {
            if ((qpc_seconds() - g_last_pass_qpc) * 1000.0 < (double)g_cfg.valve_ms) {
                W.skips++;
                stats_maybe_report(0);
                return 1; /* 0 would be treated as a fatal server error */
            }
            W.valve++;
        }
    }
    ret = do_pass(o, flags, now);
    stats_maybe_report(0);
    return ret;
}

int servertick_install(const pe_t *pe)
{
    uint32_t func, site;
    uint8_t *p;
    DWORD old;
    int32_t rel;

    W.min_inc = 1e9f;
    if (!locate_update_call(pe, &func, &site))
        return 0;
    p = (uint8_t *)(uintptr_t)site;
    rel = *(int32_t *)(p + 1);
    if (p[0] != 0xE8 || site + 5 + (uint32_t)rel != func) {
        log_printf("patch: call site changed under us, not applied");
        return 0;
    }

    if (g_floor < 0.001f || g_floor > 0.05f) {
        log_printf("patch: unexpected floor value %.6f, not applied", g_floor);
        return 0;
    }
    g_threshold = g_floor;
    if (g_cfg.min_tick_ms > 0 && g_cfg.min_tick_ms != 10) {
        float t = (float)g_cfg.min_tick_ms / 1000.0f;
        g_threshold = t < g_floor ? g_floor : t;
    }

    g_orig = (update_fn)(uintptr_t)func;
    g_site = p;
    g_orig_rel = rel;
    if (!VirtualProtect(p + 1, 4, PAGE_EXECUTE_READWRITE, &old)) {
        log_printf("patch: VirtualProtect failed (%lu)", GetLastError());
        return 0;
    }
    *(int32_t *)(p + 1) = (int32_t)((uint32_t)(uintptr_t)update_wrapper - (site + 5));
    VirtualProtect(p + 1, 4, old, &old);
    FlushInstructionCache(GetCurrentProcess(), p, 5);

    g_installed = 1;
    g_skip_enabled = !g_cfg.diagnose_only;
    log_printf("patch: server update redirected, min tick %.2f ms (engine floor %.2f ms)%s",
               g_threshold * 1000.0f, g_floor * 1000.0f,
               g_cfg.diagnose_only ? ", DIAGNOSE ONLY: measuring, nothing skipped" : "");
    return 1;
}

void servertick_uninstall(void)
{
    DWORD old;
    int32_t ours;
    if (!g_installed)
        return;
    ours = (int32_t)((uint32_t)(uintptr_t)update_wrapper - (va(g_site) + 5));
    if (*(int32_t *)(g_site + 1) == ours &&
        VirtualProtect(g_site + 1, 4, PAGE_EXECUTE_READWRITE, &old)) {
        *(int32_t *)(g_site + 1) = g_orig_rel;
        VirtualProtect(g_site + 1, 4, old, &old);
        FlushInstructionCache(GetCurrentProcess(), g_site, 5);
    }
    g_installed = 0;
}

void stats_maybe_report(int force)
{
    double now = qpc_seconds(), win;
    char mouse[256];

    if (W.start == 0.0) {
        W.start = now;
        return;
    }
    win = now - W.start;
    if (win <= 0.0 || (!force && win < (double)g_cfg.stats_interval))
        return;

    if (g_installed) {
        char speed[64], orig[64], tick[64];
        if (W.real_active > 0.5)
            snprintf(speed, sizeof speed, "x%.3f", W.game_inc / W.real_active);
        else
            snprintf(speed, sizeof speed, "n/a");
        if (W.orig_den > 0.5)
            snprintf(orig, sizeof orig, "x%.3f", W.orig_num / W.orig_den);
        else
            snprintf(orig, sizeof orig, "n/a");
        if (W.max_inc > 0.0f)
            snprintf(tick, sizeof tick, "%.1f-%.1f ms", W.min_inc * 1000.0f, W.max_inc * 1000.0f);
        else
            snprintf(tick, sizeof tick, "n/a");
        log_printf("stats %.0fs: %.1f fps | server %.1f updates/s (skipped %u, valve %u, inactive %u) | "
                   "game speed %s | server step %s | unpatched engine would run %s",
                   win, W.frames / win, W.passes / win, W.skips, W.valve, W.inactive,
                   speed, tick, orig);
    }
    mousefix_stats(mouse, sizeof mouse, win);
    if (mouse[0])
        log_printf("stats %.0fs: %s", win, mouse);

    memset(&W, 0, sizeof W);
    W.start = now;
    W.min_inc = 1e9f;
}
