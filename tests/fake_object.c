/*
 * Stand-in for the game's server code (object.lto), for the critical hit test. Original code:
 * it only reproduces the shape ShogoFPS looks for - a 5% roll that calls IsBaseCharacter before
 * multiplying the damage by 4, with an IsPlayer twin that differs only by the class name pushed.
 * Build with -DNO_TWIN for an IsPlayer that does not match (the patch must then stay out).
 */
#include <windows.h>
#include <string.h>

typedef struct { const char *cls; } fake_obj;

__attribute__((used)) const char s_base[] = "CBaseCharacter";
__attribute__((used)) const char s_player[] = "CPlayerObj";

static int __cdecl is_kind(void *h, const char *cls)
{
    const char *c = ((fake_obj *)h)->cls;
    if (strcmp(c, cls) == 0)
        return 1;
    return strcmp(cls, "CBaseCharacter") == 0 && (strcmp(c, "CPlayerObj") == 0 || strcmp(c, "CBaseAI") == 0);
}

/* Engine-style function table, called indirectly as the game does. */
__attribute__((used)) int(__cdecl *g_srv[2])(void *, const char *) = {0, is_kind};

int __cdecl IsBaseCharacter(void *h);
int __cdecl IsPlayer(void *h);
void __cdecl crit_roll(void *victim, float *damage, float roll);

__asm__(".text\n"
        ".globl _IsBaseCharacter\n_IsBaseCharacter:\n"
        "  pushl %ebp\n  movl %esp,%ebp\n  pushl $_s_base\n  pushl 8(%ebp)\n"
        "  call *_g_srv+4\n  addl $8,%esp\n  popl %ebp\n  ret\n"
        ".globl _IsPlayer\n_IsPlayer:\n"
        "  pushl %ebp\n  movl %esp,%ebp\n  pushl $_s_player\n  pushl 8(%ebp)\n"
#ifdef NO_TWIN
        "  nop\n"
#endif
        "  call *_g_srv+4\n  addl $8,%esp\n  popl %ebp\n  ret\n"
        ".globl _crit_roll\n_crit_roll:\n"
        "  flds 12(%esp)\n  fcomps _c005\n  fnstsw %ax\n  testb $0x41,%ah\n  je 1f\n"
        "  pushl 4(%esp)\n  call _IsBaseCharacter\n  addl $4,%esp\n  testl %eax,%eax\n  je 1f\n"
        "  movl 8(%esp),%eax\n  flds (%eax)\n  fmuls _c4\n  fstps (%eax)\n"
        "  flds _c025\n  fstp %st(0)\n"
        "1: ret\n"
        ".section .rdata,\"dr\"\n.align 4\n"
        "_c005: .float 0.05\n_c4: .float 4.0\n_c025: .float 0.25\n"
        ".text\n");

__declspec(dllexport) void *ObjectDLLSetup(int *n, void *server, int *version)
{
    (void)server;
    *n = 0;
    *version = 0;
    return 0;
}

/* Damage dealt to a player and to an AI by a hit of 10 with the given roll. */
__declspec(dllexport) void crit_test(float roll, float *player, float *ai)
{
    fake_obj p = {"CPlayerObj"}, a = {"CBaseAI"};
    *player = 10.0f;
    *ai = 10.0f;
    crit_roll(&p, player, roll);
    crit_roll(&a, ai, roll);
}
