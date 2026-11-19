// Converts between Big5 and UTF-8 with the bounded and streaming converters in libcmsys.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "cmsys.h"
#include "multibyte.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2)
        return -1;
    int mode = data[0] & 3;
    size_t max_len = (size_t)data[1] + 1;
    data += 2; size -= 2;

    switch (mode) {
    case 0:
    case 1: {
        char *src = malloc(size ? size : 1);
        char *dst = malloc(max_len);
        memcpy(src, data, size);
        char *r = mode == 0 ? utf8_to_big5_n(src, size, dst, max_len)
                            : big5_to_utf8_n(src, size, dst, max_len);
        if (r != dst || strlen(dst) >= max_len)
            abort();
        free(src);
        free(dst);
        break;
    }
    case 2: {
        // In-place conversion: source and destination are the same buffer.
        char *buf = malloc(max_len);
        size_t n = size < max_len - 1 ? size : max_len - 1;
        memcpy(buf, data, n);
        buf[n] = '\0';
        big5_to_utf8(buf, buf, max_len);
        if (strlen(buf) >= max_len)
            abort();
        free(buf);
        break;
    }
    default: {
        utf8_ctx u;
        big5_ctx b;
        char out[8];
        utf8_init(&u);
        big5_init(&b);
        for (size_t i = 0; i < size; i++) {
            if (utf8_add_byte(&u, data[i])) {
                int ucs = utf8_get_ucs(&u);
                big5_ctx e;
                big5_init(&e);
                if (ucs >= 0 && big5_from_char(&e, ucs) > 0)
                    (void)big5_to_mb(&e, out);
            }
            if (big5_add_byte(&b, data[i])) {
                int ch = big5_get_char(&b);
                utf8_ctx e;
                utf8_init(&e);
                if (ch >= 0 && utf8_from_ucs(&e, ch) > 0)
                    (void)utf8_to_mb(&e, out);
            }
        }
        break;
    }
    }
    return 0;
}
