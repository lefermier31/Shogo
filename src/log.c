#include "shogofps.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static HANDLE g_log = INVALID_HANDLE_VALUE;

static int starts_with_env_dir(const char *path, const char *var)
{
    char dir[MAX_PATH];
    DWORD n = GetEnvironmentVariableA(var, dir, MAX_PATH);
    if (n == 0 || n >= MAX_PATH)
        return 0;
    return CompareStringA(LOCALE_INVARIANT, NORM_IGNORECASE, path, (int)n, dir, (int)n) == CSTR_EQUAL &&
           (path[n] == '\\' || path[n] == 0);
}

/*
 * A 1998 executable without a manifest runs with UAC file virtualization: a
 * log created under Program Files would silently land in VirtualStore. Use
 * %LOCALAPPDATA%\ShogoFPS instead in that case.
 */
static int needs_relocation(const char *path)
{
    HANDLE tok;
    DWORD virt = 0, len = 0;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok))
        return 0;
    if (!GetTokenInformation(tok, TokenVirtualizationEnabled, &virt, sizeof virt, &len))
        virt = 0;
    CloseHandle(tok);
    return virt && (starts_with_env_dir(path, "ProgramFiles") ||
                    starts_with_env_dir(path, "ProgramFiles(x86)") ||
                    starts_with_env_dir(path, "ProgramW6432") ||
                    starts_with_env_dir(path, "SystemRoot"));
}

void log_open(HMODULE self)
{
    char path[MAX_PATH];
    DWORD n;
    char *slash;

    if (!g_cfg.log_enabled)
        return;
    n = GetModuleFileNameA(self, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH - 16)
        return;
    if (g_cfg.log_dir[0]) {
        /* Chosen folder (e.g. on another drive): create it, parents included. */
        char *p;
        n = (DWORD)lstrlenA(g_cfg.log_dir);
        if (n == 0 || n >= MAX_PATH - 16)
            return;
        lstrcpyA(path, g_cfg.log_dir);
        while (n > 3 && (path[n - 1] == '\\' || path[n - 1] == '/'))
            path[--n] = 0;
        for (p = path + (n > 3 ? 3 : n); *p; p++) {
            if (*p == '\\' || *p == '/') {
                char c = *p;
                *p = 0;
                CreateDirectoryA(path, NULL);
                *p = c;
            }
        }
        CreateDirectoryA(path, NULL);
        lstrcatA(path, "\\ShogoFPS.log");
    } else if (needs_relocation(path)) {
        n = GetEnvironmentVariableA("LOCALAPPDATA", path, MAX_PATH - 32);
        if (n == 0 || n >= MAX_PATH - 32)
            return;
        lstrcatA(path, "\\ShogoFPS");
        CreateDirectoryA(path, NULL);
        lstrcatA(path, "\\ShogoFPS.log");
    } else {
        slash = strrchr(path, '\\');
        if (!slash)
            return;
        strcpy(slash + 1, "ShogoFPS.log");
    }
    g_log = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS,
                        FILE_ATTRIBUTE_NORMAL, NULL);
    log_printf("log file: %s", path);
}

void log_printf(const char *fmt, ...)
{
    char buf[1024];
    SYSTEMTIME st;
    int len, n;
    DWORD written;
    va_list ap;

    if (g_log == INVALID_HANDLE_VALUE)
        return;
    GetLocalTime(&st);
    len = snprintf(buf, sizeof buf, "[%02u:%02u:%02u.%03u] ",
                   st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    va_start(ap, fmt);
    n = vsnprintf(buf + len, sizeof buf - len - 3, fmt, ap);
    va_end(ap);
    if (n < 0)
        n = 0;
    len += n;
    if (len > (int)sizeof buf - 3)
        len = (int)sizeof buf - 3;
    buf[len++] = '\r';
    buf[len++] = '\n';
    WriteFile(g_log, buf, (DWORD)len, &written, NULL);
}

void log_hex(const char *label, const uint8_t *p, int n)
{
    char line[256];
    int i, pos = 0;

    for (i = 0; i < n && pos < (int)sizeof line - 4; i++)
        pos += snprintf(line + pos, sizeof line - pos, "%02X ", p[i]);
    line[pos] = 0;
    log_printf("%s: %s", label, line);
}

void log_close(void)
{
    if (g_log != INVALID_HANDLE_VALUE) {
        CloseHandle(g_log);
        g_log = INVALID_HANDLE_VALUE;
    }
}
