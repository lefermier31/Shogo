#include "shogofps.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static HANDLE g_log = INVALID_HANDLE_VALUE;

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
    slash = strrchr(path, '\\');
    if (!slash)
        return;
    strcpy(slash + 1, "ShogoFPS.log");
    g_log = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS,
                        FILE_ATTRIBUTE_NORMAL, NULL);
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
