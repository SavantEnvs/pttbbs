// Feeds raw client bytes through the telnet IAC state machine used by mbbsd.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#include "cmsys.h"

static size_t g_written, g_cc, g_resized, g_ttype;

static void on_write(void *arg, int fd, const void *buf, size_t n) {
    (void)arg; (void)fd;
    if (n) (void)*(const volatile char *)buf, (void)*((const volatile char *)buf + n - 1);
    g_written += n;
}
static void on_resize(void *arg, int w, int h) { (void)arg; (void)w; (void)h; g_resized++; }
static void on_cc(void *arg, unsigned char c) { (void)arg; (void)c; g_cc++; }
static void on_ayt(void *arg, int fd) { (void)arg; (void)fd; }
static void on_ttype(void *arg, char *tt, int len) {
    (void)arg;
    g_ttype++;
    if (len > 0) (void)strnlen(tt, (size_t)len);
}

static const struct TelnetCallback cb = {
    .write_data = on_write,
    .term_resize = on_resize,
    .update_client_code = on_cc,
    .send_ayt = on_ayt,
    .ttype = on_ttype,
};

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2)
        return -1;
    // data[0] picks the read() chunk size, as a client's TCP segmentation would.
    size_t chunk = (size_t)(data[0] % 31) + 1;
    data++; size--;

    TelnetCtx ctx;
    telnet_ctx_init(&ctx, &cb, -1);
    telnet_ctx_set_cc_arg(&ctx, &ctx);
    telnet_ctx_set_write_arg(&ctx, &ctx);
    telnet_ctx_set_resize_arg(&ctx, &ctx);
    telnet_ctx_set_ayt_arg(&ctx, &ctx);
    telnet_ctx_set_ttype_arg(&ctx, &ctx);
    telnet_ctx_send_init_cmds(&ctx);

    // telnet_process() filters its buffer in place, so each chunk is a slice of a private copy.
    unsigned char *buf = malloc(size);
    memcpy(buf, data, size);
    for (size_t off = 0; off < size; off += chunk) {
        size_t n = size - off < chunk ? size - off : chunk;
        ssize_t r = telnet_process(&ctx, buf + off, (ssize_t)n);
        if (r > (ssize_t)n)
            abort();
    }
    free(buf);
    return 0;
}
