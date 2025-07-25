#include <plthook.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "libtest.h"
#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#if defined __UCLIBC__ && !defined RTLD_NOLOAD
#define RTLD_NOLOAD 0
#endif

#define CHK_PH(func) do { \
    if (func != 0) { \
        fprintf(stderr, "%s error: %s\n", #func, plthook_error()); \
        exit(1); \
    } \
} while (0)

typedef struct {
    const char *name;
    int enumerated;
} enum_test_data_t;

enum open_mode {
    OPEN_MODE_DEFAULT,
    OPEN_MODE_BY_HANDLE,
    OPEN_MODE_BY_ADDRESS,
};

static enum_test_data_t funcs_called_by_libtest[] = {
#if defined __APPLE__ && defined __LP64__
    {"_strtod", 0},
#elif defined __APPLE__ && !defined __LP64__
    {"_strtod$UNIX2003", 0},
#else
    {"strtod", 0},
#endif
    {NULL, },
};

static enum_test_data_t funcs_called_by_main[] = {
#if defined _WIN64 || (defined __CYGWIN__ && defined __x86_64__)
    {"strtod_cdecl", 0},
    {"strtod_stdcall", 0},
    {"strtod_fastcall", 0},
#ifndef __CYGWIN__
    {"libtest.dll:@10", 0},
#endif
#elif defined _WIN32 && defined __GNUC__
    {"strtod_cdecl", 0},
    {"strtod_stdcall@8", 0},
    {"@strtod_fastcall@8", 0},
#elif defined _WIN32 && !defined __GNUC__
    {"strtod_cdecl", 0},
    {"_strtod_stdcall@8", 0},
    {"@strtod_fastcall@8", 0},
    {"libtest.dll:@10", 0},
#elif defined __APPLE__
    {"_strtod_cdecl", 0},
#else
    {"strtod_cdecl", 0},
#endif
    {NULL, },
};

typedef struct hooked_val_t hooked_val_t;

extern hooked_val_t val_exe2lib;
extern hooked_val_t val_lib2libc;

extern double (*strtod_cdecl_old_func)(const char *);
#if defined _WIN32 || defined __CYGWIN__
extern double (__stdcall *strtod_stdcall_old_func)(const char *);
extern double (__fastcall *strtod_fastcall_old_func)(const char *);
#endif
#if defined _WIN32
extern double (*strtod_export_by_ordinal_old_func)(const char *);
#endif

/* hook func from libtest to libc. */
double strtod_hook_func(const char *str);

/* hook func from testprog to libtest. */
double strtod_cdecl_hook_func(const char *str);

#if defined _WIN32 || defined __CYGWIN__
/* hook func from testprog to libtest. */
double __stdcall strtod_stdcall_hook_func(const char *str);

/* hook func from testprog to libtest. */
double __fastcall strtod_fastcall_hook_func(const char *str);
#endif

#if defined _WIN32
/* hook func from testprog to libtest. */
double strtod_export_by_ordinal_hook_func(const char *str);
#endif

static void test_plthook_enum(plthook_t *plthook, enum_test_data_t *test_data)
{
    unsigned int pos = 0;
    const char *name;
    void **addr;
    int i;

    while (plthook_enum(plthook, &pos, &name, &addr) == 0) {
        for (i = 0; test_data[i].name != NULL; i++) {
            if (strcmp(test_data[i].name, name) == 0) {
                test_data[i].enumerated = 1;
            }
        }
    }
    for (i = 0; test_data[i].name != NULL; i++) {
        if (!test_data[i].enumerated) {
            fprintf(stderr, "%s is not enumerated by plthook_enum.\n", test_data[i].name);
            pos = 0;
            while (plthook_enum(plthook, &pos, &name, &addr) == 0) {
                fprintf(stderr, "   %s\n", name);
            }
            exit(1);
        }
    }
}

void hook_function_calls_in_executable(enum open_mode open_mode)
{
    plthook_t *plthook;
    void *handle;

    fprintf(stderr, "opening executable via %d\n", open_mode);
    switch (open_mode) {
    case OPEN_MODE_DEFAULT:
        CHK_PH(plthook_open(&plthook, NULL));
        break;
    case OPEN_MODE_BY_HANDLE:
#ifdef WIN32
        handle = GetModuleHandle(NULL);
#else
        handle = dlopen(NULL, RTLD_LAZY);
#endif
        assert(handle != NULL);
        CHK_PH(plthook_open_by_handle(&plthook, handle));
        break;
    case OPEN_MODE_BY_ADDRESS:
        CHK_PH(plthook_open_by_address(&plthook, &hook_function_calls_in_executable));
        break;
    }
    test_plthook_enum(plthook, funcs_called_by_main);
    CHK_PH(plthook_replace(plthook, "strtod_cdecl", (void*)strtod_cdecl_hook_func, (void**)&strtod_cdecl_old_func));
#if defined _WIN32 || defined __CYGWIN__
    CHK_PH(plthook_replace(plthook, "strtod_stdcall", (void*)strtod_stdcall_hook_func, (void**)&strtod_stdcall_old_func));
    CHK_PH(plthook_replace(plthook, "strtod_fastcall", (void*)strtod_fastcall_hook_func, (void**)&strtod_fastcall_old_func));
#endif
#if defined _WIN32
    CHK_PH(plthook_replace(plthook, "libtest.dll:@10", (void*)strtod_export_by_ordinal_hook_func, (void**)&strtod_export_by_ordinal_old_func));
#endif
    plthook_close(plthook);
}

void hook_function_calls_in_library(enum open_mode open_mode, const char *filename)
{
    plthook_t *plthook;
    void *handle;
#ifndef WIN32
    void *address;
#endif

    fprintf(stderr, "opening %s via %d\n", filename, open_mode);
    switch (open_mode) {
    case OPEN_MODE_DEFAULT:
        CHK_PH(plthook_open(&plthook, filename));
        break;
    case OPEN_MODE_BY_HANDLE:
#ifdef WIN32
        handle = GetModuleHandle(filename);
#else
        handle = dlopen(filename, RTLD_LAZY | RTLD_NOLOAD);
#endif
        assert(handle != NULL);
        CHK_PH(plthook_open_by_handle(&plthook, handle));
        break;
    case OPEN_MODE_BY_ADDRESS:
#ifdef WIN32
        handle = GetModuleHandle(filename);
        assert(handle != NULL);
        CHK_PH(plthook_open_by_address(&plthook, handle));
#else
        handle = dlopen(filename, RTLD_LAZY | RTLD_NOLOAD);
        address = dlsym(handle, "strtod_cdecl");
        assert(address != NULL);
        CHK_PH(plthook_open_by_address(&plthook, (char*)address));
#endif
        break;
    }
    test_plthook_enum(plthook, funcs_called_by_libtest);
    CHK_PH(plthook_replace(plthook, "strtod", (void*)strtod_hook_func, NULL));
    plthook_close(plthook);
}

