/*
 * No critical hits on the player.
 *
 * The game's server code (object.lto) gives every hit a 5% chance of a critical hit that does
 * four times the damage, on any character, the player included. Inside that roll, once the 5%
 * draw has succeeded, the game asks "is the victim a character?" before multiplying the damage.
 * That call is redirected to a filter that answers "no" when the victim is a player, so the
 * player never takes a critical hit while enemies still do.
 *
 * object.lto is loaded when a game starts, so Client.exe's LoadLibraryA import is hooked and the
 * patch is applied to each module that exports ObjectDLLSetup. Everything is located by its
 * structure, never by address:
 *   - the roll: a reference to 0.05, then exactly one call, then a reference to 4.0 within 0x60
 *     bytes, then a reference to 0.25 (the attacker's health bonus) within 0x100 bytes;
 *   - the call's target (one jump thunk followed) pushes the string "CBaseCharacter";
 *   - its twin pushes "CPlayerObj" and is byte for byte the same function otherwise.
 * If any of this is not found exactly once, nothing is changed.
 */
#include "shogofps.h"
#include <string.h>

typedef int(__cdecl *hobject_test_fn)(void *hobject);
typedef HMODULE(WINAPI *loadlib_fn)(LPCSTR);

static hobject_test_fn g_is_character, g_is_player;
static DWORD *g_ll_slot;
static DWORD g_ll_orig;
static int g_installed;
static volatile LONG g_blocked;

static int __cdecl GAME_ENTRY crit_victim_filter(void *hobject)
{
    if (g_is_player(hobject)) {
        LONG n = InterlockedIncrement(&g_blocked);
        log_printf("crit: critical hit on the player cancelled (%ld so far)", n);
        return 0;
    }
    return g_is_character(hobject);
}

#define MAX_HITS 64

typedef struct {
    const uint8_t *at[MAX_HITS];
    int n;
} hits_t;

static void add_hit(hits_t *h, const uint8_t *p)
{
    if (h->n < MAX_HITS)
        h->at[h->n] = p;
    h->n++;
}

/* Addresses of a constant stored as float or double in the module's data sections. */
static void find_constant(const pe_t *pe, double value, hits_t *out)
{
    float f = (float)value;
    int i;
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        uint32_t k;
        if (r->exec)
            continue;
        for (k = 0; k + 8 <= r->size; k += 4) {
            if (memcmp(r->ptr + k, &f, 4) == 0 || (k % 8 == 0 && memcmp(r->ptr + k, &value, 8) == 0))
                add_hit(out, r->ptr + k);
        }
    }
}

static int in_hits(const hits_t *h, uint32_t v)
{
    int i;
    for (i = 0; i < h->n && i < MAX_HITS; i++)
        if ((uint32_t)(uintptr_t)h->at[i] == v)
            return 1;
    return 0;
}

/* Instructions with an absolute [disp32] operand (mod=00, rm=101) pointing at one of the constants. */
static void find_refs(const pe_t *pe, const hits_t *consts, hits_t *out)
{
    int i;
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        uint32_t k;
        if (!r->exec)
            continue;
        for (k = 1; k + 4 <= r->size; k++) {
            uint32_t v;
            if ((r->ptr[k - 1] & 0xC7) != 0x05)
                continue;
            memcpy(&v, r->ptr + k, 4);
            if (in_hits(consts, v))
                add_hit(out, r->ptr + k - 1);
        }
    }
}

static const uint8_t *call_target(const uint8_t *p)
{
    int32_t rel;
    memcpy(&rel, p + 1, 4);
    return p + 5 + rel;
}

static const uint8_t *skip_thunk(const pe_t *pe, const uint8_t *t)
{
    if (pe_in_exec(pe, t, 5) && t[0] == 0xE9) {
        const uint8_t *u = call_target(t);
        if (pe_in_exec(pe, u, 16))
            return u;
    }
    return t;
}

/* Address of a NUL-terminated string in the data sections (must be preceded by a NUL). */
static void find_string(const pe_t *pe, const char *s, hits_t *out)
{
    size_t len = strlen(s) + 1;
    int i;
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        uint32_t k;
        if (r->exec)
            continue;
        for (k = 1; k + len <= r->size; k++)
            if (r->ptr[k - 1] == 0 && memcmp(r->ptr + k, s, len) == 0)
                add_hit(out, r->ptr + k);
    }
}

/* Offset of "push imm32" pushing one of the strings, within the first 0x40 bytes of fn; -1 if none. */
static int push_offset(const pe_t *pe, const uint8_t *fn, const hits_t *strs)
{
    int k;
    if (!pe_in_exec(pe, fn, 0x48))
        return -1;
    for (k = 0; k < 0x40; k++) {
        uint32_t v;
        if (fn[k] != 0x68)
            continue;
        memcpy(&v, fn + k + 1, 4);
        if (in_hits(strs, v))
            return k;
    }
    return -1;
}

/* Same code as ref over len bytes, except the pushed string at push_at, and relative
   calls/jumps compared by destination. */
static int same_function(const uint8_t *a, const uint8_t *ref, int len, int push_at)
{
    int k = 0;
    while (k < len) {
        if (k == push_at) {
            if (a[k] != 0x68)
                return 0;
            k += 5;
            continue;
        }
        if ((ref[k] == 0xE8 || ref[k] == 0xE9) && a[k] == ref[k] && k + 5 <= len &&
            call_target(a + k) == call_target(ref + k)) {
            k += 5;
            continue;
        }
        if (a[k] != ref[k])
            return 0;
        k++;
    }
    return 1;
}

static void patch_module(HMODULE mod, const char *name)
{
    pe_t pe;
    hits_t c005 = {0}, c4 = {0}, c025 = {0}, r005 = {0}, r4 = {0}, r025 = {0};
    hits_t s_char = {0}, s_player = {0};
    const uint8_t *site = NULL, *is_char = NULL, *is_player = NULL;
    int sites = 0, i, j, push_at, len, twins = 0;
    DWORD old;
    int32_t rel;

    if (!pe_load(&pe, mod)) {
        log_printf("crit: cannot read %s, not applied", name);
        return;
    }
    find_constant(&pe, 0.05, &c005);
    find_constant(&pe, 4.0, &c4);
    find_constant(&pe, 0.25, &c025);
    find_refs(&pe, &c005, &r005);
    find_refs(&pe, &c4, &r4);
    find_refs(&pe, &c025, &r025);
    find_string(&pe, "CBaseCharacter", &s_char);
    find_string(&pe, "CPlayerObj", &s_player);
    if (r005.n > MAX_HITS || r4.n > MAX_HITS || r025.n > MAX_HITS || !s_char.n || !s_player.n) {
        log_printf("crit: %s does not look like Shogo's game code (refs %d/%d/%d, strings %d/%d), not applied",
                   name, r005.n, r4.n, r025.n, s_char.n, s_player.n);
        return;
    }

    /* The roll: 0.05 ... one call to IsBaseCharacter ... 4.0 ... 0.25 */
    for (i = 0; i < r005.n; i++) {
        for (j = 0; j < r4.n; j++) {
            const uint8_t *a = r005.at[i], *b = r4.at[j], *p, *call = NULL;
            int calls = 0, k, bonus = 0;
            if (b <= a || b - a > 0x60)
                continue;
            for (k = 0; k < r025.n; k++)
                if (r025.at[k] > b && r025.at[k] - b <= 0x100)
                    bonus = 1;
            if (!bonus)
                continue;
            for (p = a + 6; p + 5 <= b; p++) {
                const uint8_t *t;
                if (*p != 0xE8)
                    continue;
                t = skip_thunk(&pe, call_target(p));
                if (push_offset(&pe, t, &s_char) >= 0) {
                    calls++;
                    call = p;
                    is_char = t;
                }
            }
            if (calls == 1) {
                sites++;
                site = call;
            }
        }
    }
    if (sites != 1) {
        log_printf("crit: critical hit roll found %d times in %s (expected 1), not applied", sites, name);
        return;
    }

    /* IsPlayer: the twin of IsBaseCharacter pushing "CPlayerObj". */
    push_at = push_offset(&pe, is_char, &s_char);
    for (len = push_at + 5; len < 0x100 && is_char[len] != 0xC3 && is_char[len] != 0xC2; len++)
        ;
    len++;
    if (len > 0x100 || !pe_in_exec(&pe, is_char, (uint32_t)len)) {
        log_printf("crit: end of IsBaseCharacter not found, not applied");
        return;
    }
    for (i = 0; i < pe.nranges; i++) {
        const pe_range *r = &pe.r[i];
        uint32_t k;
        if (!r->exec)
            continue;
        for (k = (uint32_t)push_at; k + 5 <= r->size; k++) {
            const uint8_t *start = r->ptr + k - push_at;
            uint32_t v;
            if (r->ptr[k] != 0x68)
                continue;
            memcpy(&v, r->ptr + k + 1, 4);
            if (!in_hits(&s_player, v) || !pe_in_exec(&pe, start, (uint32_t)len))
                continue;
            if (same_function(start, is_char, len, push_at)) {
                twins++;
                is_player = start;
            }
        }
    }
    if (twins != 1) {
        log_printf("crit: IsPlayer found %d times next to IsBaseCharacter %08X (expected 1), not applied",
                   twins, (uint32_t)(uintptr_t)is_char);
        return;
    }

    log_printf("crit: roll call at %08X, IsBaseCharacter %08X, IsPlayer %08X in %s",
               (uint32_t)(uintptr_t)site, (uint32_t)(uintptr_t)is_char, (uint32_t)(uintptr_t)is_player, name);
    log_hex("crit: call site", site - 16, 32);
    if (g_cfg.diagnose_only) {
        log_printf("crit: DIAGNOSE ONLY, critical hits on the player left as they are");
        return;
    }
    g_is_character = (hobject_test_fn)(uintptr_t)is_char;
    g_is_player = (hobject_test_fn)(uintptr_t)is_player;
    rel = (int32_t)((uintptr_t)crit_victim_filter - (uintptr_t)(site + 5));
    if (!VirtualProtect((void *)(site + 1), 4, PAGE_EXECUTE_READWRITE, &old)) {
        log_printf("crit: VirtualProtect failed (%lu), not applied", GetLastError());
        return;
    }
    memcpy((void *)(site + 1), &rel, 4);
    VirtualProtect((void *)(site + 1), 4, old, &old);
    FlushInstructionCache(GetCurrentProcess(), site, 5);
    log_printf("crit: critical hits on the player are off");
}

static HMODULE WINAPI GAME_ENTRY hook_LoadLibraryA(LPCSTR name)
{
    HMODULE h = ((loadlib_fn)(uintptr_t)g_ll_orig)(name);
    DWORD err = GetLastError();
    if (h && GetProcAddress(h, "ObjectDLLSetup"))
        patch_module(h, name ? name : "?");
    SetLastError(err);
    return h;
}

int nocrit_install(const pe_t *exe)
{
    DWORD old;
    g_ll_slot = pe_find_import(exe, "kernel32.dll", "LoadLibraryA", 0);
    if (!g_ll_slot) {
        log_printf("crit: Client.exe does not import LoadLibraryA, not applied");
        return 0;
    }
    if (!VirtualProtect(g_ll_slot, 4, PAGE_READWRITE, &old)) {
        log_printf("crit: VirtualProtect failed (%lu)", GetLastError());
        return 0;
    }
    /* Chained: another loader may already sit in this slot. */
    g_ll_orig = *g_ll_slot;
    *g_ll_slot = (DWORD)(uintptr_t)hook_LoadLibraryA;
    VirtualProtect(g_ll_slot, 4, old, &old);
    g_installed = 1;
    log_printf("crit: waiting for the game code (object.lto) to load");
    return 1;
}

void nocrit_uninstall(void)
{
    DWORD old;
    if (!g_installed)
        return;
    if (*g_ll_slot == (DWORD)(uintptr_t)hook_LoadLibraryA && VirtualProtect(g_ll_slot, 4, PAGE_READWRITE, &old)) {
        *g_ll_slot = g_ll_orig;
        VirtualProtect(g_ll_slot, 4, old, &old);
    }
    g_installed = 0;
}
