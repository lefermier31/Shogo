/*
 * Stand-in for Shogo's Client.exe, written from scratch for testing ShogoFPS
 * under Wine. It reproduces only the behaviour the fix depends on:
 *  - a server update called once per frame through a direct call, __thiscall
 *    (this, flags, float now), that clamps its delta to [0.01, 0.2] and adds
 *    it to the game time;
 *  - the anchor strings around that call;
 *  - an engine clock that stops while the window is inactive;
 *  - an input loop that reads GetTickCount through the import table;
 *  - a game thread whose x87 unit may be in 24-bit precision.
 * Build variants: -DDECOY_CLAMP, -DBAD_LAYOUT, -DNO_FOCUS_ANCHOR, -DTWO_CALLERS.
 */
#include <windows.h>
#include <float.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ServerMgr {
    char pad0[0x190];
    int no_world;          /* 0x190 */
    unsigned paused;       /* 0x194 */
    unsigned demo;         /* 0x198 */
    char pad1[0x1F0 - 0x19C];
    float frame_time;      /* 0x1F0 */
    char pad2[0x1F8 - 0x1F4];
    float time_offset;     /* 0x1F8 */
    char pad3[0x20C - 0x1FC];
    float game_time;       /* 0x20C */
    char pad4[0x214 - 0x210];
    float true_frame_time; /* 0x214 */
    float last_time;       /* 0x218 */
    float other_last;      /* 0x21C, used by BAD_LAYOUT */
} ServerMgr;

_Static_assert(offsetof(ServerMgr, no_world) == 0x190, "layout");
_Static_assert(offsetof(ServerMgr, paused) == 0x194, "layout");
_Static_assert(offsetof(ServerMgr, demo) == 0x198, "layout");
_Static_assert(offsetof(ServerMgr, time_offset) == 0x1F8, "layout");
_Static_assert(offsetof(ServerMgr, game_time) == 0x20C, "layout");
_Static_assert(offsetof(ServerMgr, last_time) == 0x218, "layout");

#ifdef NO_FOCUS_ANCHOR
#define FOCUS_VAR "keepfocus"
#else
#define FOCUS_VAR "alwaysfocused"
#endif

static volatile float s_floor = 0.01f;
static volatile float s_ceil = 0.2f;

typedef void (*logfn_t)(const char *, double);
static void quiet(const char *f, double v) { (void)f; (void)v; }
volatile logfn_t g_log = quiet;

static unsigned g_update_runs;
static int g_frame, g_load_at = -1;

/* Physics-like code that also reads the floor constant, as the real engine does. */
__attribute__((noipa)) float collide(float x)
{
    return x * s_floor + 1.0f;
}

#ifdef DECOY_CLAMP
__attribute__((noipa)) float decoy_clamp(float x)
{
    if (x < s_floor)
        x = s_floor;
    if (x > s_ceil)
        x = s_ceil;
    return x;
}
#endif

__attribute__((thiscall, noipa)) unsigned ServerMgr_Update(ServerMgr *self, unsigned flags, float t)
{
    float now, d;
    g_update_runs++;
    g_log("Guaranteed ratio: %.3f", 1.0);
    now = t + self->time_offset;
#ifdef BAD_LAYOUT
    /* last time kept elsewhere; 0x218 holds something unrelated */
    self->true_frame_time = now - self->other_last;
    self->other_last = now;
    self->last_time = self->last_time + 0.5f;
#else
    self->true_frame_time = now - self->last_time;
    self->last_time = now;
#endif
    if (g_frame == g_load_at) {
        /* level load handled inside the update: slow, restarts the world clock */
        g_load_at = -1;
        Sleep(400);
        self->game_time = 0.0f;
        return 1;
    }
    if (self->no_world)
        return 1;
    if ((flags & 1) || (self->paused & 1) || (self->demo & 0xC))
        return 1;
    d = self->true_frame_time;
    if (d < s_floor)
        d = s_floor;
    if (d > s_ceil)
        d = s_ceil;
    self->frame_time = d;
    self->game_time += d;
    g_log("Game time: %.2f", self->game_time);
    return 1;
}

static volatile float g_alwaysfocused = 0.0f;

__attribute__((noipa)) float get_var(const char *name)
{
    return strcmp(name, FOCUS_VAR) == 0 ? g_alwaysfocused : 0.0f;
}

__attribute__((noipa)) int ClientShell_Update(ServerMgr *sm, float t, int inactive)
{
    unsigned flags = 0;
    if (inactive && get_var(FOCUS_VAR) != 1.0f)
        flags = 1;
    if (!ServerMgr_Update(sm, flags, t))
        return 0x2000031;
    return 0;
}

#ifdef TWO_CALLERS
__attribute__((noipa)) void ServerMgr_Prime(ServerMgr *sm)
{
    ServerMgr_Update(sm, 1, sm->last_time);
}
#endif

typedef DWORD(WINAPI *gtc_t)(void);
static gtc_t real_gtc;
static DWORD g_prev_tick;
static unsigned g_reads, g_still, g_ahead, g_backwards;
static DWORD g_max_lag;

__attribute__((noipa)) void ReadInput(void)
{
    DWORD now = GetTickCount(); /* through the import table */
    DWORD real = real_gtc();
    if ((int)(now - real) > 0)
        g_ahead++;
    else if (g_frame > 200 && real - now > g_max_lag)
        g_max_lag = real - now;
    if (g_reads && (int)(now - g_prev_tick) < 0)
        g_backwards++;
    if (g_reads && now == g_prev_tick)
        g_still++;
    g_prev_tick = now;
    g_reads++;
}

/* --qpc-days: QueryPerformanceCounter as seen from outside this exe is shifted. */
static LONGLONG g_qpc_shift;
static BYTE *g_exe_lo, *g_exe_hi;
typedef LONG(WINAPI *ntqpc_t)(LARGE_INTEGER *, LARGE_INTEGER *);
static ntqpc_t g_ntqpc;

static BOOL WINAPI shifted_qpc(LARGE_INTEGER *c)
{
    BYTE *from = (BYTE *)__builtin_return_address(0);
    g_ntqpc(c, NULL);
    if (from < g_exe_lo || from >= g_exe_hi)
        c->QuadPart += g_qpc_shift;
    return TRUE;
}

static void shift_qpc(double days)
{
    BYTE *exe = (BYTE *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS32 *nt = (IMAGE_NT_HEADERS32 *)(exe + ((IMAGE_DOS_HEADER *)exe)->e_lfanew);
    BYTE *fn = (BYTE *)GetProcAddress(GetModuleHandleA("kernel32.dll"), "QueryPerformanceCounter");
    LARGE_INTEGER f;
    DWORD old;
    QueryPerformanceFrequency(&f);
    g_qpc_shift = (LONGLONG)(days * 86400.0 * (double)f.QuadPart);
    g_exe_lo = exe;
    g_exe_hi = exe + nt->OptionalHeader.SizeOfImage;
    g_ntqpc = (ntqpc_t)GetProcAddress(GetModuleHandleA("ntdll.dll"), "NtQueryPerformanceCounter");
    VirtualProtect(fn, 5, PAGE_EXECUTE_READWRITE, &old);
    fn[0] = 0xE9;
    *(DWORD *)(fn + 1) = (DWORD)((BYTE *)shifted_qpc - (fn + 5));
    VirtualProtect(fn, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), fn, 5);
}

static double qpc_now(void)
{
    static LARGE_INTEGER f;
    LARGE_INTEGER c;
    if (!f.QuadPart)
        QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart / (double)f.QuadPart;
}

int main(int argc, char **argv)
{
    int frames = 2000, load = 1, i, errors = 0, jitter = 0, freeze = 0, pc24 = 0;
    int inactive_from = -1, inactive_to = -1;
    unsigned inactive_frames = 0, inactive_runs = 0, short_frames = 0;
    double frame_ms = 4.0, target, qdays = 0, span_q0 = 0, span_q1 = 0;
    float t, t_first = 0, t_last = 0, t_prev = 0, engine_t = 0, span_g0 = 0, span_g1 = 0;
    float paused = 0;
    DWORD prev_tgt;
    ServerMgr *sm;

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--frames") && i + 1 < argc)
            frames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--frame-ms") && i + 1 < argc)
            frame_ms = atof(argv[++i]);
        else if (!strcmp(argv[i], "--no-load"))
            load = 0;
        else if (!strcmp(argv[i], "--jitter"))
            jitter = 1;
        else if (!strcmp(argv[i], "--freeze"))
            freeze = 1;
        else if (!strcmp(argv[i], "--focus-lock"))
            g_alwaysfocused = 1.0f;
        else if (!strcmp(argv[i], "--pc24"))
            pc24 = 1;
        else if (!strcmp(argv[i], "--qpc-days") && i + 1 < argc)
            qdays = atof(argv[++i]);
        else if (!strcmp(argv[i], "--load-at") && i + 1 < argc)
            g_load_at = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--inactive") && i + 2 < argc) {
            inactive_from = atoi(argv[++i]);
            inactive_to = atoi(argv[++i]);
        }
    }

    real_gtc = (gtc_t)GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetTickCount");
    if (qdays > 0)
        shift_qpc(qdays);
    if (pc24)
        _controlfp(_PC_24, _MCW_PC); /* as the engine and Direct3D do */
    if (load && !LoadLibraryA("ShogoFPS.asi"))
        printf("LOADFAIL %lu\n", GetLastError());

    sm = calloc(1, sizeof *sm);
    prev_tgt = timeGetTime();
    srand(1234);
    collide(1.0f);
#ifdef DECOY_CLAMP
    decoy_clamp(1.0f);
#endif
#ifdef TWO_CALLERS
    ServerMgr_Prime(sm);
#endif

    target = qpc_now();
    for (i = 0; i < frames; i++) {
        int inactive = i >= inactive_from && i < inactive_to;
        unsigned before = g_update_runs;
        DWORD tgt = timeGetTime();
        g_frame = i;
        /* the engine clock only advances while the window is active */
        if (inactive && freeze)
            paused += (float)(tgt - prev_tgt) * 0.001f;
        else
            engine_t += (float)(tgt - prev_tgt) * 0.001f;
        prev_tgt = tgt;
        t = engine_t;
        if (i == 0)
            t_first = t;
        else if (t - t_prev < 0.010f && !inactive)
            short_frames++;
        t_prev = t;
        t_last = t;
        if (i == inactive_from) {
            span_g0 = sm->game_time;
            span_q0 = qpc_now();
        }
        if (i == inactive_to) {
            span_g1 = sm->game_time;
            span_q1 = qpc_now();
        }
        ReadInput();
        if (ClientShell_Update(sm, t, inactive) != 0)
            errors++;
        if (inactive) {
            inactive_frames++;
            inactive_runs += g_update_runs - before;
        }
        target += jitter ? (2.0 + (rand() % 1000) / 100.0) / 1000.0 : frame_ms / 1000.0;
        while (qpc_now() < target)
            ;
        if (qpc_now() - target > 0.005) /* no catch-up burst after a stall */
            target = qpc_now();
    }

    {
        /* game time vs engine time; a level load restarts game time at 0 */
        double real = (double)(t_last - t_first);
        double ratio = real > 0 ? sm->game_time / real : 0;
        double span = span_q1 > span_q0 ? (span_g1 - span_g0) / (span_q1 - span_q0) : 0;
        printf("RESULT ratio=%.4f game=%.3f real=%.3f frames=%d updates=%u errors=%d "
               "reads=%u still=%u ahead=%u backwards=%u maxlag=%lu inactive_frames=%u "
               "inactive_updates=%u short_frames=%u span_speed=%.3f paused=%.3f\n",
               ratio, sm->game_time, real, frames, g_update_runs, errors, g_reads, g_still,
               g_ahead, g_backwards, g_max_lag, inactive_frames, inactive_runs, short_frames, span,
               paused);
    }
    return 0;
}
