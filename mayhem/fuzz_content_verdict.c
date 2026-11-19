// Parses the one-line verdict ("allow|deny alert ban report reporter reason\ndetails") that the
// content-filter service sends back to mbbsd. content_parse_verdict is static, so the harness
// includes its translation unit, the way upstream's test_brc.c does for brc.c.
#include "../common/bbs/content.c"

#include <stdint.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // content_filter() NUL-terminates the response it hands to the parser.
    char *resp = malloc(size + 1);
    memcpy(resp, data, size);
    resp[size] = '\0';

    content_verdict_t v;
    int rc = content_parse_verdict(resp, size, &v);
    if (rc == 0) {
        if (strlen(v.reason) >= sizeof(v.reason) || strlen(v.reporter) >= sizeof(v.reporter) ||
            strlen(v.details) >= sizeof(v.details))
            abort();
    }
    free(resp);
    return rc < 0 ? -1 : 0;
}
