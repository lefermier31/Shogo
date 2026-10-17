/*
 * ShogoFPS - frame-rate fixes for Shogo: Mobile Armor Division (LithTech 1.0).
 * Original code, MIT licence. Contains no Monolith or decompiled code.
 */
#ifndef SHOGOFPS_H
#define SHOGOFPS_H

#include <windows.h>
#include <stdint.h>

#define SHOGOFPS_VERSION "0.4.1"

/* Entry points called from game code: honour the MSVC caller's 4-byte stack. */
#define GAME_ENTRY __attribute__((force_align_arg_pointer))

typedef struct {
    int server_tick_fix;  /* hold the local server to >= one engine tick per update */
    int mouse_fix;        /* fine-grained GetTickCount for the DirectInput loop */
    int timer_resolution; /* timeBeginPeriod(1) */
    int min_tick_ms;      /* 0 or 10 = use the engine's own floor constant */
    int mouse_lag_ms;     /* how far the fine clock stays behind GetTickCount */
    int diagnose_only;    /* measure only, change nothing in the game's behaviour */
    int strict;           /* abort on any doubtful detection */
    int log_enabled;
    char log_dir[MAX_PATH]; /* empty = next to the DLL */
    int stats_interval;   /* seconds between stats lines */
    int valve_ms;         /* always let the server update after this much real time */
    int no_player_crits;  /* no critical hits on the player */
    int cutscene_fix;     /* a live camera ignores a repeated ON */
} config_t;

extern config_t g_cfg;

/* log.c */
void log_open(HMODULE self);
void log_printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
void log_hex(const char *label, const uint8_t *p, int n);
void log_close(void);

/* pe.c */
typedef struct {
    uint8_t *ptr;   /* start of the section in memory */
    uint32_t size;  /* bytes readable from ptr */
    int exec;
    char name[9];
} pe_range;

typedef struct {
    uint8_t *base;
    uint32_t image_size;
    uint32_t timestamp;
    uint32_t checksum;
    uint32_t image_base;
    IMAGE_NT_HEADERS32 *nt;
    int nranges;
    pe_range r[32];
} pe_t;

int pe_load(pe_t *pe, HMODULE mod);
int pe_in_exec(const pe_t *pe, const uint8_t *p, uint32_t len);
uint64_t pe_code_hash(const pe_t *pe);
/* Import slot of dll!func; without names, the slot holding expected (0 = no fallback). */
DWORD *pe_find_import(const pe_t *pe, const char *dll, const char *func, DWORD expected);

/* timing.c */
typedef DWORD (WINAPI *dword_fn)(void);
typedef UINT (WINAPI *period_fn)(UINT);

extern dword_fn real_GetTickCount;
extern dword_fn real_timeGetTime;    /* NULL until timing_init_late() */

void timing_init_early(void);        /* safe under the loader lock */
void timing_init_late(void);         /* first call from a game hook */
LONGLONG qpc_ticks(void);            /* QPC ticks since the DLL was loaded */
LONGLONG ms_to_ticks(int ms);
double ticks_to_seconds(LONGLONG t); /* short intervals only */
int timing_fine_clock(void);         /* 1 if timeGetTime now ticks in ~1 ms steps */
DWORD timing_step_ms(void);          /* timeGetTime step measured at start-up */
void timing_shutdown(void);

/* servertick.c */
int servertick_install(const pe_t *pe);
void servertick_uninstall(void);
void stats_maybe_report(int force);

/* mousefix.c */
int mousefix_install(const pe_t *pe);
void mousefix_uninstall(void);
void mousefix_stats(char *buf, int len, double window_s);

/* nocrit.c */
int nocrit_install(const pe_t *exe);
void nocrit_uninstall(void);

/* camguard.c */
int camguard_install(const pe_t *exe);
void camguard_uninstall(void);

#endif
