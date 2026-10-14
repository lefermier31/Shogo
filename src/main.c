#include "shogofps.h"
#include <stdio.h>
#include <string.h>

config_t g_cfg;

static int g_active;

static void load_config(HMODULE self)
{
    char path[MAX_PATH];
    DWORD n = GetModuleFileNameA(self, path, MAX_PATH);
    char *slash = n && n < MAX_PATH - 16 ? strrchr(path, '\\') : NULL;

    g_cfg.server_tick_fix = 1;
    g_cfg.mouse_fix = 1;
    g_cfg.timer_resolution = 1;
    g_cfg.min_tick_ms = 10;
    g_cfg.mouse_lag_ms = 20;
    g_cfg.diagnose_only = 0;
    g_cfg.strict = 0;
    g_cfg.log_enabled = 1;
    g_cfg.stats_interval = 30;
    g_cfg.valve_ms = 100;
    g_cfg.no_player_crits = 1;
    g_cfg.log_dir[0] = 0;
    if (!slash)
        return;
    strcpy(slash + 1, "ShogoFPS.ini");

#define GETI(key, field) g_cfg.field = (int)GetPrivateProfileIntA("ShogoFPS", key, g_cfg.field, path)
    GETI("ServerTickFix", server_tick_fix);
    GETI("MouseFix", mouse_fix);
    GETI("TimerResolution", timer_resolution);
    GETI("MinTickMs", min_tick_ms);
    GETI("MouseLagMs", mouse_lag_ms);
    GETI("DiagnoseOnly", diagnose_only);
    GETI("Strict", strict);
    GETI("Log", log_enabled);
    GETI("StatsInterval", stats_interval);
    GETI("ValveMs", valve_ms);
    GETI("NoPlayerCrits", no_player_crits);
#undef GETI
    GetPrivateProfileStringA("ShogoFPS", "LogDir", "", g_cfg.log_dir, sizeof g_cfg.log_dir, path);
    if (g_cfg.stats_interval < 5)
        g_cfg.stats_interval = 5;
    if (g_cfg.valve_ms < 50)
        g_cfg.valve_ms = 50;
}

static int host_is_client_exe(void)
{
    char path[MAX_PATH];
    const char *base;
    DWORD n = GetModuleFileNameA(NULL, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH)
        return 0;
    base = strrchr(path, '\\');
    base = base ? base + 1 : path;
    return lstrcmpiA(base, "client.exe") == 0;
}

static void start(HMODULE self)
{
    pe_t pe;
    char exe[MAX_PATH] = "";
    int tick = 0, mouse = 0, crit = 0;

    load_config(self);
    log_open(self);
    timing_init_early();
    GetModuleFileNameA(NULL, exe, MAX_PATH);
    log_printf("ShogoFPS " SHOGOFPS_VERSION " in %s", exe);
    log_printf("config: ServerTickFix=%d MouseFix=%d TimerResolution=%d MinTickMs=%d MouseLagMs=%d "
               "NoPlayerCrits=%d DiagnoseOnly=%d Strict=%d StatsInterval=%d",
               g_cfg.server_tick_fix, g_cfg.mouse_fix, g_cfg.timer_resolution, g_cfg.min_tick_ms,
               g_cfg.mouse_lag_ms, g_cfg.no_player_crits, g_cfg.diagnose_only, g_cfg.strict, g_cfg.stats_interval);

    if (!pe_load(&pe, GetModuleHandleA(NULL))) {
        log_printf("cannot read Client.exe headers, nothing applied");
        return;
    }
    log_printf("Client.exe: base %08X, size %u, timestamp %08X, checksum %08X, code hash %016llX",
               (uint32_t)(uintptr_t)pe.base, pe.image_size, pe.timestamp, pe.checksum,
               (unsigned long long)pe_code_hash(&pe));

    if (g_cfg.server_tick_fix)
        tick = servertick_install(&pe);
    if (g_cfg.mouse_fix)
        mouse = mousefix_install(&pe);
    if (g_cfg.no_player_crits)
        crit = nocrit_install(&pe);

    if (tick || mouse || crit) {
        HMODULE pinned;
        /* Hooks point into this module: it must never be unloaded. */
        GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                           (LPCSTR)(uintptr_t)start, &pinned);
        g_active = 1;
    }
    log_printf("ready: server tick fix %s, mouse fix %s, no player crits %s",
               tick ? "ON" : "off", mouse ? "ON" : "off", crit ? "ON" : "off");
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        /* The same loader may run in Shogo.exe, ShogoSrv.exe, tools...: stay inert there. */
        if (host_is_client_exe())
            start(inst);
    } else if (reason == DLL_PROCESS_DETACH) {
        if (g_active) {
            stats_maybe_report(1);
            if (reserved == NULL) {
                servertick_uninstall();
                mousefix_uninstall();
                nocrit_uninstall();
                timing_shutdown();
            }
            log_printf("shutdown");
        }
        log_close();
    }
    return TRUE;
}
