/* -*- indent-tabs-mode: nil -*-
 *
 * plthook_win32.c -- implementation of plthook for PE format
 *
 * URL: https://github.com/kubo/plthook
 *
 * ------------------------------------------------------
 *
 * Copyright 2013-2014 Kubo Takehiro <kubo@jiubao.org>
 *
 * Redistribution and use in source and binary forms, with or without modification, are
 * permitted provided that the following conditions are met:
 *
 *    1. Redistributions of source code must retain the above copyright notice, this list of
 *       conditions and the following disclaimer.
 *
 *    2. Redistributions in binary form must reproduce the above copyright notice, this list
 *       of conditions and the following disclaimer in the documentation and/or other materials
 *       provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 * FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 * ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * The views and conclusions contained in the software and documentation are those of the
 * authors and should not be interpreted as representing official policies, either expressed
 * or implied, of the authors.
 *
 */
#include <stdio.h>
#include <stddef.h>
#include <stdarg.h>
#include <windows.h>
#include <dbghelp.h>
#include "plthook.h"

#ifdef _MSC_VER
#pragma comment(lib, "dbghelp.lib")
#endif

#ifndef _Printf_format_string_
#define _Printf_format_string_
#endif
#ifndef __GNUC__
#define __attribute__(arg)
#endif

#ifdef __CYGWIN__
#define stricmp strcasecmp
#endif

typedef struct {
    const char *mod_name;
    const char *name;
    void **addr;
} import_address_entry_t;

struct plthook {
    HMODULE hMod;
    unsigned int num_entries;
    import_address_entry_t entries[1];
};

extern void clear_errmsg();
extern void append_errmsg_s(const char *str);
extern void append_errmsg_i(uintptr_t i);
extern void append_errmsg_win();

extern const char *winsock2_ordinal2name(int ordinal);

int plthook_open_real(plthook_t **plthook_out, HMODULE hMod)
{
    plthook_t *plthook;
    ULONG ulSize;
    IMAGE_IMPORT_DESCRIPTOR *desc_head, *desc;
    size_t num_entries = 0;
    size_t ordinal_name_buflen = 0;
    size_t idx;
    char *ordinal_name_buf;

    desc_head = (IMAGE_IMPORT_DESCRIPTOR*)ImageDirectoryEntryToData(hMod, TRUE, IMAGE_DIRECTORY_ENTRY_IMPORT, &ulSize);
    if (desc_head == NULL) {
        clear_errmsg();
        append_errmsg_s("ImageDirectoryEntryToData error: ");
        append_errmsg_win();
        return PLTHOOK_INTERNAL_ERROR;
    }

    /* Calculate size to allocate memory.  */
    for (desc = desc_head; desc->Name != 0; desc++) {
        IMAGE_THUNK_DATA *name_thunk = (IMAGE_THUNK_DATA*)((char*)hMod + desc->OriginalFirstThunk);
        IMAGE_THUNK_DATA *addr_thunk = (IMAGE_THUNK_DATA*)((char*)hMod + desc->FirstThunk);
        const char *module_name = (char *)hMod + desc->Name;
        int is_winsock2_dll = (stricmp(module_name, "WS2_32.DLL") == 0);

        while (addr_thunk->u1.Function != 0) {
            if (IMAGE_SNAP_BY_ORDINAL(name_thunk->u1.Ordinal)) {
                int ordinal = IMAGE_ORDINAL(name_thunk->u1.Ordinal);
                const char *name = NULL;
                if (is_winsock2_dll) {
                    name = winsock2_ordinal2name(ordinal);
                }
                if (name == NULL) {
#ifdef __CYGWIN__
                    ordinal_name_buflen += snprintf(NULL, 0, "%s:@%d", module_name, ordinal) + 1;
#else
                    ordinal_name_buflen += _scprintf("%s:@%d", module_name, ordinal) + 1;
#endif
                }
            }
            num_entries++;
            name_thunk++;
            addr_thunk++;
        }
    }

    plthook = calloc(1, offsetof(plthook_t, entries) + sizeof(import_address_entry_t) * num_entries + ordinal_name_buflen);
    if (plthook == NULL) {
        clear_errmsg();
        append_errmsg_s("failed to allocate memory: ");
        append_errmsg_i(sizeof(plthook_t));
        append_errmsg_s(" bytes");
        return PLTHOOK_OUT_OF_MEMORY;
    }
    plthook->hMod = hMod;
    plthook->num_entries = num_entries;

    ordinal_name_buf = (char*)plthook + offsetof(plthook_t, entries) + sizeof(import_address_entry_t) * num_entries;
    idx = 0;
    for (desc = desc_head; desc->Name != 0; desc++) {
        IMAGE_THUNK_DATA *name_thunk = (IMAGE_THUNK_DATA*)((char*)hMod + desc->OriginalFirstThunk);
        IMAGE_THUNK_DATA *addr_thunk = (IMAGE_THUNK_DATA*)((char*)hMod + desc->FirstThunk);
        const char *module_name = (char *)hMod + desc->Name;
        int is_winsock2_dll = (stricmp(module_name, "WS2_32.DLL") == 0);

        while (addr_thunk->u1.Function != 0) {
            const char *name = NULL;

            if (IMAGE_SNAP_BY_ORDINAL(name_thunk->u1.Ordinal)) {
                int ordinal = IMAGE_ORDINAL(name_thunk->u1.Ordinal);
                if (is_winsock2_dll) {
                    name = winsock2_ordinal2name(ordinal);
                }
                if (name == NULL) {
                    name = ordinal_name_buf;
                    ordinal_name_buf += sprintf(ordinal_name_buf, "%s:@%d", module_name, ordinal) + 1;
                }
            } else {
                name = (char*)((PIMAGE_IMPORT_BY_NAME)((char*)hMod + name_thunk->u1.AddressOfData))->Name;
            }
            plthook->entries[idx].mod_name = module_name;
            plthook->entries[idx].name = name;
            plthook->entries[idx].addr = (void**)&addr_thunk->u1.Function;
            idx++;
            name_thunk++;
            addr_thunk++;
        }
    }

    *plthook_out = plthook;
    return 0;
}
