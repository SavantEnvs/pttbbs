// Runs the BBS text helpers over one string: ANSI escape stripping/scanning, DBCS-aware string
// functions, display width, and URL detection with multi-line URL tracking.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "cmsys.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2)
        return -1;
    size_t split = data[0];
    data++; size--;
    if (split > size)
        split = size;

    // The helpers take NUL-terminated strings; the input holds two of them.
    char *a = malloc(size + 1);
    memcpy(a, data, size);
    a[size] = '\0';
    size_t alen = strlen(a);
    char *b = malloc(size + 1);
    memcpy(b, data + split, size - split);
    b[size - split] = '\0';
    char *dst = malloc(size + 1);

    for (int mode = STRIP_ALL; mode <= NO_RELOAD; mode++) {
        int n = strip_control_sequence_ex(dst, a, (enum STRIP_FLAG)mode);
        if (n < 0 || (size_t)n > alen)
            abort();
        (void)strip_control_sequence_ex(NULL, a, (enum STRIP_FLAG)mode);
    }
    strip_blank(dst, a);
    reduce_blank(dst, a);
    (void)skip_control_sequence(a);

    (void)stream_width(a);
    (void)stream_width_n(a, (int)alen);
    (void)mb_width(a);
    int real_cols;
    (void)stream_col_offset((int)split, a, &real_cols);

    if (alen) {
        for (size_t i = 0; i < alen; i++)
            (void)mbs_status(a, (int)i);
        (void)mbs_nth(a, (int)split);
    }
    (void)mbs_strstr(a, b);
    (void)mbs_strcasestr(a, b);
    size_t blen = strlen(b);
    (void)mbs_strncasecmp(a, b, split < alen && split < blen ? split : (alen < blen ? alen : blen));
    (void)mbs_strcasehash(a);

    memcpy(dst, a, alen + 1);
    mbs_safe_trim(dst);
    memcpy(dst, a, alen + 1);
    mbs_sanitize(dst, (int)alen + 1);

    int ulen;
    if (match_url(a, (int)alen, &ulen) && (ulen <= 0 || (size_t)ulen > alen))
        abort();
    (void)match_url_continuation(a, (int)alen);

    // url_tracker_init starts at a URL that match_url found: p and first_len are its result.
    url_tracker_t st;
    const char *end = a + alen;
    for (const char *p = a; p < end; p++) {
        if ((*p == 'h' || *p == 'H') && match_url(p, (int)(end - p), &ulen)) {
            if (url_tracker_init(&st, p, ulen, end, (int)(p - a) % 100) && split < alen)
                (void)url_tracker_next_line(&st, a + split, end);
            break;
        }
    }
    if (split > 0 && split < alen)
        (void)url_tracker_init_from_prev_line(&st, a + split, a, end);

    free(a);
    free(b);
    free(dst);
    return 0;
}
