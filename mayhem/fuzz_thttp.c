// Parses the HTTP response that thttp reads from a server (status line, headers, body).
// read_response is static, so the harness includes thttp.c and feeds the response through the
// THTTP read hook instead of a socket (the hook is how thttp reads in the first place).
#include "../common/sys/thttp.c"

#include <stdint.h>
#include <stdlib.h>

static const uint8_t *g_data;
static size_t g_size, g_off, g_chunk;

static int mock_read(THTTP *t, void *buffer, int size) {
    (void)t;
    size_t n = g_size - g_off;
    if (n > g_chunk) n = g_chunk;
    if (n > (size_t)size) n = (size_t)size;
    memcpy(buffer, g_data + g_off, n);
    g_off += n;
    return (int)n;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1)
        return -1;
    g_chunk = (size_t)(data[0] % 61) + 1;
    g_data = data + 1; g_size = size - 1; g_off = 0;

    THTTP t;
    if (thttp_init(&t) < 0)
        return -1;
    t.read = mock_read;
    if (read_response(&t) >= 0 && thttp_code(&t) == 200) {
        const char *v;
        int len = thttp_content_length(&t);
        const char *body = thttp_get_content(&t);
        if (len < 0)
            abort();
        if (len > 0)
            (void)*(const volatile char *)(body + len - 1);
        static const char *const names[] = {"Content-Length", "content-type", "Location", "Server"};
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
            int n = thttp_get_header(&t, names[i], &v);
            if (n > 0)
                (void)*(const volatile char *)(v + n - 1);
        }
    }
    thttp_cleanup(&t);
    return 0;
}
