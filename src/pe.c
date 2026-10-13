#include "shogofps.h"
#include <string.h>

int pe_load(pe_t *pe, HMODULE mod)
{
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)mod;
    IMAGE_SECTION_HEADER *s;
    int i;

    memset(pe, 0, sizeof *pe);
    if (!mod || dos->e_magic != IMAGE_DOS_SIGNATURE)
        return 0;
    pe->base = (uint8_t *)mod;
    pe->nt = (IMAGE_NT_HEADERS32 *)(pe->base + dos->e_lfanew);
    if (pe->nt->Signature != IMAGE_NT_SIGNATURE ||
        pe->nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC)
        return 0;
    pe->image_size = pe->nt->OptionalHeader.SizeOfImage;
    pe->image_base = pe->nt->OptionalHeader.ImageBase;
    pe->timestamp = pe->nt->FileHeader.TimeDateStamp;
    pe->checksum = pe->nt->OptionalHeader.CheckSum;

    s = IMAGE_FIRST_SECTION(pe->nt);
    for (i = 0; i < pe->nt->FileHeader.NumberOfSections && pe->nranges < 32; i++, s++) {
        uint32_t size = s->Misc.VirtualSize ? s->Misc.VirtualSize : s->SizeOfRawData;
        pe_range *r;
        if (s->VirtualAddress >= pe->image_size || size == 0)
            continue;
        if (size > pe->image_size - s->VirtualAddress)
            size = pe->image_size - s->VirtualAddress;
        if (!(s->Characteristics & IMAGE_SCN_MEM_READ) &&
            !(s->Characteristics & IMAGE_SCN_MEM_EXECUTE))
            continue;
        r = &pe->r[pe->nranges++];
        r->ptr = pe->base + s->VirtualAddress;
        r->size = size;
        r->exec = (s->Characteristics & (IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_CNT_CODE)) != 0;
        memcpy(r->name, s->Name, 8);
        r->name[8] = 0;
    }
    return pe->nranges > 0;
}

int pe_in_exec(const pe_t *pe, const uint8_t *p, uint32_t len)
{
    int i;
    for (i = 0; i < pe->nranges; i++) {
        const pe_range *r = &pe->r[i];
        if (r->exec && p >= r->ptr && p + len <= r->ptr + r->size)
            return 1;
    }
    return 0;
}

/* FNV-1a over the code sections: a cheap build fingerprint for the log. */
uint64_t pe_code_hash(const pe_t *pe)
{
    uint64_t h = 1469598103934665603ULL;
    int i;
    uint32_t j;
    for (i = 0; i < pe->nranges; i++) {
        if (!pe->r[i].exec)
            continue;
        for (j = 0; j < pe->r[i].size; j++) {
            h ^= pe->r[i].ptr[j];
            h *= 1099511628211ULL;
        }
    }
    return h;
}
