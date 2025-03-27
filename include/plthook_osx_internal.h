#include <stdint.h>
#include <mach-o/dyld.h>

#include "../plthook.h"

int plthook_open_real(plthook_t **plthook_out, uint32_t image_idx, const struct mach_header *mh, const char *image_name);