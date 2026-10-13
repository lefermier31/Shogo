/*
 * Mouse fix.
 *
 * The engine's DirectInput loop measures the time between input reads with
 * GetTickCount, which only moves in ~15.6 ms steps. Above ~64 fps most frames
 * see zero elapsed time and get no mouse movement, then one frame gets a
 * whole tick's worth: the view stutters. We point Client.exe's import of
 * GetTickCount at a 1 ms clock built on timeGetTime.
 *
 * That clock must never run ahead of the real GetTickCount: the engine
 * subtracts it from DirectInput event timestamps (GetTickCount domain) as
 * unsigned values, and a negative gap would freeze the mouse. It is kept a
 * few milliseconds behind, rises monotonically, and is clamped every call.
 */
#include "shogofps.h"
#include <stdio.h>
#include <string.h>

static DWORD *g_slot;
static DWORD g_slot_orig;
static int g_installed;
static int g_ready; /* 0 = calibrate on first call, 1 = fine clock, -1 = pass-through */
static DWORD g_offset;
static DWORD g_lag;
static DWORD g_last_out;
static int g_have_last;

static unsigned g_calls, g_still, g_guard, g_catchup;

static DWORD *find_import(const pe_t *pe, const char *dll, const char *func, DWORD expected)
{
    IMAGE_DATA_DIRECTORY *dd = &pe->nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    IMAGE_IMPORT_DESCRIPTOR *d;
    uint32_t size = pe->image_size;

    if (!dd->VirtualAddress || dd->VirtualAddress >= size)
        return NULL;
    for (d = (IMAGE_IMPORT_DESCRIPTOR *)(pe->base + dd->VirtualAddress);
         (uint8_t *)(d + 1) <= pe->base + size && d->Name; d++) {
        IMAGE_THUNK_DATA32 *ft, *ot;
        int i;
        if (d->Name >= size || d->FirstThunk >= size)
            break;
        if (lstrcmpiA((const char *)(pe->base + d->Name), dll) != 0)
            continue;
        ft = (IMAGE_THUNK_DATA32 *)(pe->base + d->FirstThunk);
        ot = (d->OriginalFirstThunk && d->OriginalFirstThunk < size)
                 ? (IMAGE_THUNK_DATA32 *)(pe->base + d->OriginalFirstThunk)
                 : NULL;
        for (i = 0; (uint8_t *)(ft + i + 1) <= pe->base + size && ft[i].u1.Function; i++) {
            if (ot) {
                IMAGE_IMPORT_BY_NAME *ibn;
                if (ot[i].u1.Ordinal & IMAGE_ORDINAL_FLAG32)
                    continue;
                if (ot[i].u1.AddressOfData >= size)
                    continue;
                ibn = (IMAGE_IMPORT_BY_NAME *)(pe->base + ot[i].u1.AddressOfData);
                if (strcmp((const char *)ibn->Name, func) == 0)
                    return (DWORD *)&ft[i].u1.Function;
            } else if (ft[i].u1.Function == expected) {
                return (DWORD *)&ft[i].u1.Function;
            }
        }
    }
    return NULL;
}

static int count_refs(const pe_t *pe, uint32_t value)
{
    int i, n = 0;
    uint32_t j;
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        if (!r->exec)
            continue;
        for (j = 0; j + 4 <= r->size; j++)
            if (*(const uint32_t *)(r->ptr + j) == value)
                n++;
    }
    return n;
}

static void calibrate(void)
{
    DWORD a, b;
    double end;

    timing_init_late();
    if (g_cfg.diagnose_only) {
        g_ready = -1;
        return;
    }
    if (!real_timeGetTime || !timing_fine_clock()) {
        g_ready = -1;
        log_printf("mouse: timeGetTime is not fine-grained, mouse fix stays in pass-through");
        return;
    }
    /* Align on a GetTickCount edge so the lag is exact. */
    a = real_GetTickCount();
    end = qpc_seconds() + 0.05;
    do {
        b = real_GetTickCount();
    } while (b == a && qpc_seconds() < end);
    if (b == a) {
        g_ready = -1;
        log_printf("mouse: GetTickCount did not move, mouse fix stays in pass-through");
        return;
    }
    g_offset = b - real_timeGetTime() - g_lag;
    g_ready = 1;
    log_printf("mouse: fine clock active, %lu ms behind GetTickCount", g_lag);
}

static DWORD WINAPI GAME_ENTRY shogo_tick(void)
{
    DWORD real = real_GetTickCount();
    DWORD g = real - 1, f;

    if (g_ready == 0)
        calibrate();
    if (g_cfg.diagnose_only) {
        f = real;
    } else if (g_ready != 1) {
        f = g;
    } else {
        f = real_timeGetTime() + g_offset;
        if ((int32_t)(f - g) > 0) {
            g_offset -= f - g;
            f = g;
            g_guard++;
        } else if ((int32_t)(g - f) > (int32_t)(g_lag + 48)) {
            g_offset += (g - g_lag) - f;
            f = g - g_lag;
            g_catchup++;
        }
    }
    if (g_have_last && (int32_t)(f - g_last_out) < 0)
        f = g_last_out;
    g_calls++;
    if (g_have_last && f == g_last_out)
        g_still++;
    g_last_out = f;
    g_have_last = 1;
    stats_maybe_report(0);
    return f;
}

int mousefix_install(const pe_t *pe)
{
    DWORD old;
    int refs;

    g_lag = (DWORD)(g_cfg.mouse_lag_ms < 16 ? 16 : g_cfg.mouse_lag_ms > 64 ? 64 : g_cfg.mouse_lag_ms);
    if (!real_GetTickCount) {
        log_printf("mouse: GetTickCount not resolved, not applied");
        return 0;
    }
    g_slot = find_import(pe, "kernel32.dll", "GetTickCount", (DWORD)(uintptr_t)real_GetTickCount);
    if (!g_slot) {
        log_printf("mouse: Client.exe does not import GetTickCount, not applied");
        return 0;
    }
    if (*g_slot != (DWORD)(uintptr_t)real_GetTickCount) {
        HMODULE owner = NULL;
        char name[MAX_PATH] = "?";
        if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                   GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               (LPCSTR)(uintptr_t)*g_slot, &owner))
            GetModuleFileNameA(owner, name, sizeof name);
        log_printf("mouse: GetTickCount import already redirected to %s, not applied", name);
        return 0;
    }
    refs = count_refs(pe, (uint32_t)(uintptr_t)g_slot);
    log_printf("mouse: GetTickCount import slot %08X, %d code reference(s)",
               (uint32_t)(uintptr_t)g_slot, refs);
    if (refs == 0 || (g_cfg.strict && refs != 1)) {
        log_printf("mouse: unexpected reference count, not applied");
        return 0;
    }
    if (!VirtualProtect(g_slot, 4, PAGE_READWRITE, &old)) {
        log_printf("mouse: VirtualProtect failed (%lu)", GetLastError());
        return 0;
    }
    g_slot_orig = *g_slot;
    *g_slot = (DWORD)(uintptr_t)shogo_tick;
    VirtualProtect(g_slot, 4, old, &old);
    g_installed = 1;
    log_printf("mouse: GetTickCount import redirected%s",
               g_cfg.diagnose_only ? " (DIAGNOSE ONLY: real value returned, only measured)" : "");
    return 1;
}

void mousefix_uninstall(void)
{
    DWORD old;
    if (!g_installed)
        return;
    if (*g_slot == (DWORD)(uintptr_t)shogo_tick && VirtualProtect(g_slot, 4, PAGE_READWRITE, &old)) {
        *g_slot = g_slot_orig;
        VirtualProtect(g_slot, 4, old, &old);
    }
    g_installed = 0;
}

void mousefix_stats(char *buf, int len, double window_s)
{
    buf[0] = 0;
    if (!g_installed || g_calls == 0)
        return;
    snprintf(buf, len, "mouse: %.1f reads/s, %.0f%% of reads with no time progress, guard %u, catch-up %u",
             g_calls / window_s, 100.0 * g_still / g_calls, g_guard, g_catchup);
    g_calls = g_still = g_guard = g_catchup = 0;
}
