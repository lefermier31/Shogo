/*
 * Stand-in for Shogo's Client.exe, written from scratch for testing ShogoFPS
 * under Wine. It reproduces only the behaviour the fix depends on:
 *  - a server update called once per frame through a direct call, __thiscall
 *    (this, flags, float now), that clamps its delta to [0.01, 0.2] and adds
 *    it to the game time;
 *  - the anchor strings around that call;
 *  - an input loop that reads GetTickCount through the import table.
 * Reports the game speed (game time / real time) and input clock statistics.
 */
#include <windows.h>
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
} ServerMgr;

_Static_assert(offsetof(ServerMgr, no_world) == 0x190, "layout");
_Static_assert(offsetof(ServerMgr, paused) == 0x194, "layout");
_Static_assert(offsetof(ServerMgr, demo) == 0x198, "layout");
_Static_assert(offsetof(ServerMgr, time_offset) == 0x1F8, "layout");
_Static_assert(offsetof(ServerMgr, game_time) == 0x20C, "layout");
_Static_assert(offsetof(ServerMgr, last_time) == 0x218, "layout");

static volatile float s_floor = 0.01f;
static volatile float s_ceil = 0.2f;

typedef void (*logfn_t)(const char *, double);
static void quiet(const char *f, double v) { (void)f; (void)v; }
volatile logfn_t g_log = quiet;

static unsigned g_update_runs;

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
    self->true_frame_time = now - self->last_time;
    self->last_time = now;
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
    return strcmp(name, "alwaysfocused") == 0 ? g_alwaysfocused : 0.0f;
}

__attribute__((noipa)) int ClientShell_Update(ServerMgr *sm, float t, int inactive)
{
    unsigned flags = 0;
    if (inactive && get_var("alwaysfocused") != 1.0f)
        flags = 1;
    if (!ServerMgr_Update(sm, flags, t))
        return 0x2000031;
    return 0;
}

typedef DWORD(WINAPI *gtc_t)(void);
static gtc_t real_gtc;
static DWORD g_prev_tick;
static unsigned g_reads, g_still, g_ahead, g_backwards;

__attribute__((noipa)) void ReadInput(void)
{
    DWORD now = GetTickCount(); /* through the import table */
    DWORD real = real_gtc();
    if ((int)(now - real) > 0)
        g_ahead++;
    if (g_reads && (int)(now - g_prev_tick) < 0)
        g_backwards++;
    if (g_reads && now == g_prev_tick)
        g_still++;
    g_prev_tick = now;
    g_reads++;
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
    int frames = 2000, load = 1, i, errors = 0, jitter = 0;
    int inactive_from = -1, inactive_to = -1;
    unsigned inactive_frames = 0, inactive_runs = 0;
    double frame_ms = 4.0, start, target;
    float t, t_first = 0, t_last = 0, t_prev = 0;
    unsigned short_frames = 0;
    char shorts[256] = "";
    DWORD base;
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
        else if (!strcmp(argv[i], "--inactive") && i + 2 < argc) {
            inactive_from = atoi(argv[++i]);
            inactive_to = atoi(argv[++i]);
        }
    }

    real_gtc = (gtc_t)GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetTickCount");
    if (load && !LoadLibraryA("ShogoFPS.asi"))
        printf("LOADFAIL %lu\n", GetLastError());

    sm = calloc(1, sizeof *sm);
    base = timeGetTime();
    sm->last_time = (float)(timeGetTime() - base) * 0.001f;
    srand(1234);
    collide(1.0f);
#ifdef DECOY_CLAMP
    decoy_clamp(1.0f);
#endif

    start = qpc_now();
    target = start;
    for (i = 0; i < frames; i++) {
        int inactive = i >= inactive_from && i < inactive_to;
        unsigned before = g_update_runs;
        t = (float)(timeGetTime() - base) * 0.001f;
        if (i == 0)
            t_first = t;
        else if (t - t_prev < 0.010f) {
            short_frames++;
            if (strlen(shorts) < 200)
                sprintf(shorts + strlen(shorts), "%d:%.4f,", i, t - t_prev);
        }
        t_prev = t;
        t_last = t;
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
        double inactive_s = 0;
        double real = (double)(t_last - t_first) - inactive_s;
        double ratio = real > 0 ? sm->game_time / real : 0;
        printf("RESULT ratio=%.4f game=%.3f real=%.3f frames=%d updates=%u errors=%d "
               "reads=%u still=%u ahead=%u backwards=%u inactive_frames=%u inactive_updates=%u short_frames=%u\n",
               ratio, sm->game_time, real, frames, g_update_runs, errors,
               g_reads, g_still, g_ahead, g_backwards, inactive_frames, inactive_runs, short_frames);
        if (short_frames)
            printf("SHORT %s\n", shorts);
    }
    return 0;
}
