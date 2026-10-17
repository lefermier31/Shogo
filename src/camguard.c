/*
 * Cutscenes that never end (e.g. "Public Nuisance").
 *
 * Some level triggers have a delay shorter than a frame, so they fire again on every frame while
 * something stands inside them. Each fire sends "ON" to the scene's camera, and a camera that
 * receives "ON" restarts its clock: the scene is pushed back by its full length every frame and
 * never ends. Here a camera that is already live ignores a further "ON", so the scene ends on time.
 *
 * The game code sends trigger messages through three engine calls (start a message to an object,
 * write the text, end the message). When the game code (object.lto) is set up, the engine hands it
 * its server interface; ShogoFPS catches that hand-over through Client.exe's GetProcAddress import
 * and wraps those three calls in the interface's table. An "ON" written to a camera that is already
 * live is replaced by a text the camera does not act on. Layout from the LithTech 1.0 interface:
 * table slots 10, 39 and 43; function members at byte offsets 8 to 432.
 */
#include "shogofps.h"
#include <string.h>

#define MID_TRIGGER 1000u
#define USRFLG_CAMERA_LIVE (1u << 5)

#define SLOT_WRITE_HSTRING 10
#define SLOT_START_TO_OBJECT 39
#define SLOT_END_MESSAGE 43

#define OFF_GET_CLASS 8
#define OFF_GET_OBJECT_CLASS 16
#define OFF_IS_KIND_OF 20
#define OFF_CREATE_STRING 116
#define OFF_FREE_STRING 120
#define OFF_GET_STRING_DATA 132
#define OFF_GET_USER_FLAGS 432

typedef void *(__attribute__((thiscall)) *start_fn)(void *self, void *sender, void *hobj, DWORD id);
typedef DWORD(__attribute__((thiscall)) *write_fn)(void *self, void *msg, void *hstr);
typedef DWORD(__attribute__((thiscall)) *end_fn)(void *self, void *msg);
typedef void *(__cdecl *get_class_fn)(const char *name);
typedef void *(__cdecl *obj_class_fn)(void *hobj);
typedef int(__cdecl *kind_fn)(void *cls, void *test);
typedef void *(__cdecl *create_str_fn)(const char *s);
typedef void(__cdecl *free_str_fn)(void *hstr);
typedef char *(__cdecl *str_data_fn)(void *hstr);
typedef DWORD(__cdecl *flags_fn)(void *hobj);
typedef void *(__cdecl *setup_fn)(int *n, void *server, int *version);
typedef FARPROC(WINAPI *getproc_fn)(HMODULE, LPCSTR);

static void **g_vtable;
static uint8_t *g_server;
static start_fn g_start;
static write_fn g_write;
static end_fn g_end;
static setup_fn g_setup;
static DWORD *g_gpa_slot;
static DWORD g_gpa_orig;
static int g_installed;
static volatile LONG g_ignored;

/* Messages started to a live camera, waiting for their text. */
#define MAX_PENDING 8
static void *g_pending[MAX_PENDING];
static void *g_replaced[MAX_PENDING]; /* our replacement string, freed at the end of the message */

#define MEMBER(type, off) (*(type *)(g_server + (off)))

static int live_camera(void *hobj)
{
    void *cam;
    if (!hobj)
        return 0;
    cam = MEMBER(get_class_fn, OFF_GET_CLASS)("Camera");
    if (!cam || !MEMBER(kind_fn, OFF_IS_KIND_OF)(MEMBER(obj_class_fn, OFF_GET_OBJECT_CLASS)(hobj), cam))
        return 0;
    return (MEMBER(flags_fn, OFF_GET_USER_FLAGS)(hobj) & USRFLG_CAMERA_LIVE) != 0;
}

static int find_pending(void *msg)
{
    int i;
    for (i = 0; i < MAX_PENDING; i++)
        if (g_pending[i] == msg)
            return i;
    return -1;
}

static void *__attribute__((thiscall)) GAME_ENTRY hook_start(void *self, void *sender, void *hobj, DWORD id)
{
    void *msg = g_start(self, sender, hobj, id);
    if (msg && id == MID_TRIGGER && live_camera(hobj)) {
        int i = find_pending(NULL);
        if (i >= 0) {
            g_pending[i] = msg;
            g_replaced[i] = NULL;
        }
    }
    return msg;
}

static DWORD __attribute__((thiscall)) GAME_ENTRY hook_write(void *self, void *msg, void *hstr)
{
    int i = msg ? find_pending(msg) : -1;
    if (i >= 0 && hstr && !g_replaced[i]) {
        const char *s = MEMBER(str_data_fn, OFF_GET_STRING_DATA)(hstr);
        if (s && lstrcmpiA(s, "ON") == 0) {
            void *other = MEMBER(create_str_fn, OFF_CREATE_STRING)("ON-IGNORED-ALREADY-LIVE");
            if (other) {
                LONG n = InterlockedIncrement(&g_ignored);
                if (n <= 3 || n % 100 == 0)
                    log_printf("cutscene: camera already playing, repeated ON ignored (%ld so far)", n);
                g_replaced[i] = other;
                hstr = other;
            }
        }
    }
    return g_write(self, msg, hstr);
}

static DWORD __attribute__((thiscall)) GAME_ENTRY hook_end(void *self, void *msg)
{
    DWORD r = g_end(self, msg);
    int i = msg ? find_pending(msg) : -1;
    if (i >= 0) {
        if (g_replaced[i])
            MEMBER(free_str_fn, OFF_FREE_STRING)(g_replaced[i]);
        g_pending[i] = NULL;
        g_replaced[i] = NULL;
    }
    return r;
}

static int code_of(HMODULE exe, const void *p)
{
    HMODULE owner = NULL;
    return GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                              (LPCSTR)p, &owner) && owner == exe;
}

static void wrap_server(void *server)
{
    static const int offs[] = {OFF_GET_CLASS, OFF_GET_OBJECT_CLASS, OFF_IS_KIND_OF, OFF_CREATE_STRING,
                               OFF_FREE_STRING, OFF_GET_STRING_DATA, OFF_GET_USER_FLAGS};
    HMODULE exe = GetModuleHandleA(NULL);
    void **vt;
    DWORD old;
    unsigned k;

    if (!server || IsBadReadPtr(server, OFF_GET_USER_FLAGS + 4)) {
        log_printf("cutscene: no server interface, not applied");
        return;
    }
    vt = *(void ***)server;
    if (vt == g_vtable && vt[SLOT_START_TO_OBJECT] == (void *)hook_start)
        return; /* already in place (game code reloaded) */
    if (IsBadReadPtr(vt, (SLOT_END_MESSAGE + 1) * 4)) {
        log_printf("cutscene: server interface table unreadable, not applied");
        return;
    }
    /* Everything must point into Client.exe's code, or the layout is not the expected one. */
    if (!code_of(exe, vt[SLOT_WRITE_HSTRING]) || !code_of(exe, vt[SLOT_START_TO_OBJECT]) ||
        !code_of(exe, vt[SLOT_END_MESSAGE])) {
        log_printf("cutscene: server interface table does not match, not applied");
        return;
    }
    for (k = 0; k < sizeof offs / sizeof offs[0]; k++) {
        if (!code_of(exe, *(void **)((uint8_t *)server + offs[k]))) {
            log_printf("cutscene: server interface member +%d does not match, not applied", offs[k]);
            return;
        }
    }
    g_server = server;
    g_start = (start_fn)vt[SLOT_START_TO_OBJECT];
    g_write = (write_fn)vt[SLOT_WRITE_HSTRING];
    g_end = (end_fn)vt[SLOT_END_MESSAGE];
    if (g_cfg.diagnose_only) {
        log_printf("cutscene: DIAGNOSE ONLY, cameras left as they are");
        return;
    }
    if (!VirtualProtect(vt, (SLOT_END_MESSAGE + 1) * 4, PAGE_READWRITE, &old)) {
        log_printf("cutscene: VirtualProtect failed (%lu), not applied", GetLastError());
        return;
    }
    vt[SLOT_START_TO_OBJECT] = (void *)hook_start;
    vt[SLOT_WRITE_HSTRING] = (void *)hook_write;
    vt[SLOT_END_MESSAGE] = (void *)hook_end;
    VirtualProtect(vt, (SLOT_END_MESSAGE + 1) * 4, old, &old);
    g_vtable = vt;
    log_printf("cutscene: a camera already playing now ignores a repeated ON");
}

static void *__cdecl GAME_ENTRY hook_setup(int *n, void *server, int *version)
{
    void *r = g_setup(n, server, version);
    wrap_server(server);
    return r;
}

static FARPROC WINAPI GAME_ENTRY hook_GetProcAddress(HMODULE mod, LPCSTR name)
{
    FARPROC p = ((getproc_fn)(uintptr_t)g_gpa_orig)(mod, name);
    if (p && (uintptr_t)name > 0xFFFF && strcmp(name, "ObjectDLLSetup") == 0) {
        g_setup = (setup_fn)(uintptr_t)p;
        return (FARPROC)(uintptr_t)hook_setup;
    }
    return p;
}

int camguard_install(const pe_t *exe)
{
    DWORD old;
    g_gpa_slot = pe_find_import(exe, "kernel32.dll", "GetProcAddress", 0);
    if (!g_gpa_slot) {
        log_printf("cutscene: Client.exe does not import GetProcAddress, not applied");
        return 0;
    }
    if (!VirtualProtect(g_gpa_slot, 4, PAGE_READWRITE, &old)) {
        log_printf("cutscene: VirtualProtect failed (%lu)", GetLastError());
        return 0;
    }
    g_gpa_orig = *g_gpa_slot;
    *g_gpa_slot = (DWORD)(uintptr_t)hook_GetProcAddress;
    VirtualProtect(g_gpa_slot, 4, old, &old);
    g_installed = 1;
    return 1;
}

void camguard_uninstall(void)
{
    DWORD old;
    if (!g_installed)
        return;
    if (*g_gpa_slot == (DWORD)(uintptr_t)hook_GetProcAddress && VirtualProtect(g_gpa_slot, 4, PAGE_READWRITE, &old)) {
        *g_gpa_slot = g_gpa_orig;
        VirtualProtect(g_gpa_slot, 4, old, &old);
    }
    g_installed = 0;
}
