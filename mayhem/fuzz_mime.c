// Decodes RFC 2047 encoded-words ("=?charset?Q|B?...?=") in a mail header, in place, to Big5.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "cmsys.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1)
        return -1;
    // data[0] sets how much room the caller's buffer has beyond the string.
    size_t pad = data[0] & 0x7f;
    data++; size--;
    size_t cap = size + 1 + pad;

    char *str = malloc(cap);
    memcpy(str, data, size);
    str[size] = '\0';
    str_decode_M3(str, cap);
    // The contract is a NUL-terminated string within the buffer.
    if (memchr(str, '\0', cap) == NULL)
        abort();
    free(str);
    return 0;
}
