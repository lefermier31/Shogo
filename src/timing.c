/*
 * Clocks used by the hooks.
 *
 * The engine switches the game thread's x87 unit to 24-bit precision, and our
 * hooks run on that thread. Absolute QPC seconds would lose all sub-second
 * resolution after a few days of Windows uptime, so every deadline here is an
 * integer tick count relative to the moment the DLL was loaded; doubles are
 * only used for short intervals in the statistics.
 */
#include "shogofps.h"

dword_fn real_GetTickCount;
dword_fn real_timeGetTime;

static period_fn real_timeBeginPeriod;
static period_fn real_timeEndPeriod;
static LARGE_INTEGER g_qpf;
static LONGLONG g_qpc0;
static volatile LONG g_late_done;
static int g_period_set;
static int g_fine_clock;
static DWORD g_step_ms = 1000;

void timing_init_early(void)
{
    LARGE_INTEGER c;
    HMODULE k32 = GetModuleHandleA("kernel32.dll");
    real_GetTickCount = (dword_fn)GetProcAddress(k32, "GetTickCount");
    QueryPerformanceFrequency(&g_qpf);
    QueryPerformanceCounter(&c);
    g_qpc0 = c.QuadPart;
}

LONGLONG qpc_ticks(void)
{
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    return c.QuadPart - g_qpc0;
}

LONGLONG ms_to_ticks(int ms)
{
    return g_qpf.QuadPart * ms / 1000;
}

double ticks_to_seconds(LONGLONG t)
{
    return (double)t / (double)g_qpf.QuadPart;
}

/*
 * Smallest step of timeGetTime seen within max_ms. Returns early once a step
 * of 2 ms or less has been seen `early` times, so a fine clock costs ~3 ms.
 */
static DWORD measure_step(int max_ms, int early)
{
    DWORD best = 1000, prev = real_timeGetTime(), now;
    LONGLONG end = qpc_ticks() + ms_to_ticks(max_ms);
    int fine = 0;
    while (qpc_ticks() < end) {
        now = real_timeGetTime();
        if (now != prev) {
            if (now - prev < best)
                best = now - prev;
            if (now - prev <= 2 && ++fine >= early)
                break;
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

    before = measure_step(34, 3);
    if (g_cfg.timer_resolution && !g_cfg.diagnose_only) {
        g_period_set = real_timeBeginPeriod(1) == TIMERR_NOERROR;
        after = measure_step(34, 3);
        log_printf("timer: timeBeginPeriod(1) %s, timeGetTime step %lu ms -> %lu ms",
                   g_period_set ? "ok" : "FAILED", before, after);
    } else {
        after = before;
        log_printf("timer: resolution left alone, timeGetTime step %lu ms", before);
    }
    g_step_ms = after;
    g_fine_clock = after <= 2;
    {
        unsigned short cw;
        __asm__ volatile("fnstcw %0" : "=m"(cw));
        log_printf("timer: game thread x87 control word %04X (%s precision)", cw,
                   (cw & 0x300) == 0 ? "24-bit" : (cw & 0x300) == 0x200 ? "53-bit" : "64-bit");
    }
}

int timing_fine_clock(void)
{
    return g_fine_clock;
}

DWORD timing_step_ms(void)
{
    return g_step_ms;
}

void timing_shutdown(void)
{
    if (g_period_set && real_timeEndPeriod) {
        real_timeEndPeriod(1);
        g_period_set = 0;
    }
}
