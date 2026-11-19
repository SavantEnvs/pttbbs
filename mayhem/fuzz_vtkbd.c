// Feeds terminal key-input bytes (VT100/xterm escape sequences, mouse reports) to the vtkbd parser.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "cmsys.h"
#include "vtkbd.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    VtkbdCtx ctx;
    memset(&ctx, 0, sizeof(ctx));
    for (size_t i = 0; i < size; i++) {
        int key = vtkbd_process(data[i], &ctx);
        if (key == 0)
            continue;
        const vtkbd_mouse_t *m = vtkbd_get_mouse(&ctx);
        if (m) {
            volatile int sink = m->x + m->y + m->button + m->flags;
            (void)sink;
        }
    }

    unsigned char *copy = malloc(size ? size : 1);
    memcpy(copy, data, size);
    // The filter only acts on 2- and 6-byte reads, so also try the prefixes of those lengths.
    static const size_t lens[] = {0, 2, 6};
    for (size_t k = 0; k < sizeof(lens) / sizeof(lens[0]); k++) {
        size_t n = lens[k] ? lens[k] : size;
        if (n > size)
            continue;
        ssize_t kept = vtkbd_ignore_dbcs_evil_repeats(copy, (ssize_t)n);
        if (kept > (ssize_t)n)
            abort();
    }
    free(copy);
    return 0;
}
