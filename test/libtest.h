#ifndef LISTTEST_H
#define LISTTEST_H 1

#ifdef _WIN32
#ifdef LIBTEST_DLL
#define LIBTESTAPI __declspec(dllexport)
#else
#define LIBTESTAPI __declspec(dllimport)
#endif
#else
#define LIBTESTAPI
#endif

LIBTESTAPI
double strtod_cdecl(const char *str);

#if defined _WIN32 || defined __CYGWIN__
LIBTESTAPI
double __stdcall strtod_stdcall(const char *str);

LIBTESTAPI
double __fastcall strtod_fastcall(const char *str);

double strtod_export_by_ordinal(const char *str);
#endif

#endif
