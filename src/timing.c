#include "shogofps.h"

dword_fn real_GetTickCount;
dword_fn real_timeGetTime;

static period_fn real_timeBeginPeriod;
static period_fn real_timeEndPeriod;
static LARGE_INTEGER g_qpf;
static volatile LONG g_late_done;
static int g_period_set;
static int g_fine_clock;

void timing_init_early(void)
{
    HMODULE k32 = GetModuleHandleA("kernel32.dll");
    real_GetTickCount = (dword_fn)GetProcAddress(k32, "GetTickCount");
    QueryPerformanceFrequency(&g_qpf);
}

double qpc_seconds(void)
{
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart / (double)g_qpf.QuadPart;
}

/* Smallest step of timeGetTime observed over ~30 ms. */
static DWORD measure_step(void)
{
    DWORD best = 1000, prev = real_timeGetTime(), now;
    double end = qpc_seconds() + 0.03;
    while (qpc_seconds() < end) {
        now = real_timeGetTime();
        if (now != prev) {
            if (now - prev < best)
                best = now - prev;
            prev = now;
        }
    }
    return best;
}

/*
 * Runs on the game thread, outside the loader lock, the first time one of
 * our hooks is reached. Loads the system winmm by full path so that a proxy
 * winmm.dll in the game folder (Ultimate ASI Loader) is never mistaken for it.
 */
void timing_init_late(void)
{
    char path[MAX_PATH];
    HMODULE wm;
    UINT n;
    DWORD before, after;

    if (InterlockedExchange(&g_late_done, 1))
        return;
    n = GetSystemDirectoryA(path, MAX_PATH - 16);
    if (n == 0 || n >= MAX_PATH - 16) {
        log_printf("timer: GetSystemDirectory failed");
        return;
    }
    lstrcatA(path, "\\winmm.dll");
    wm = LoadLibraryA(path);
    if (!wm) {
        log_printf("timer: cannot load %s", path);
        return;
    }
    real_timeGetTime = (dword_fn)GetProcAddress(wm, "timeGetTime");
    real_timeBeginPeriod = (period_fn)GetProcAddress(wm, "timeBeginPeriod");
    real_timeEndPeriod = (period_fn)GetProcAddress(wm, "timeEndPeriod");
    if (!real_timeGetTime || !real_timeBeginPeriod || !real_timeEndPeriod) {
        log_printf("timer: winmm exports missing");
        real_timeGetTime = NULL;
        return;
    }

    before = measure_step();
    if (g_cfg.timer_resolution && !g_cfg.diagnose_only) {
        g_period_set = real_timeBeginPeriod(1) == TIMERR_NOERROR;
        after = measure_step();
        log_printf("timer: timeBeginPeriod(1) %s, timeGetTime step %lu ms -> %lu ms",
                   g_period_set ? "ok" : "FAILED", before, after);
    } else {
        after = before;
        log_printf("timer: resolution left alone, timeGetTime step %lu ms", before);
    }
    g_fine_clock = after <= 2;
}

int timing_fine_clock(void)
{
    return g_fine_clock;
}

void timing_shutdown(void)
{
    if (g_period_set && real_timeEndPeriod) {
        real_timeEndPeriod(1);
        g_period_set = 0;
    }
}
