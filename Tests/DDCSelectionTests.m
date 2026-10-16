@import Foundation;
@import IOKit;
#include <assert.h>
#include "ioregistry.h"
int main(void) {
    DisplayInfos displays[2] = {};
    const char *bad[] = {"0", "-1", "-9223372036854775808", "3", "9223372036854775808", "99999999999999999999999", "", "-", "id=", "=1", "unknown=1"};
    for (size_t i = 0; i < sizeof(bad)/sizeof(*bad); ++i) {
        char *input = strdup(bad[i]);
        assert(selectDisplay(displays, 2, input) == NULL);
        free(input);
    }
    char first[] = "1", last[] = "2";
    assert(selectDisplay(displays, 2, first) == displays);
    assert(selectDisplay(displays, 2, last) == displays + 1);
    assert(selectDisplay(NULL, 2, first) == NULL);
    assert(selectDisplay(displays, 0, first) == NULL);
    assert(selectDisplay(displays, 2, NULL) == NULL);
    displays[0].id = 19; displays[1].id = 27;
    char id[] = "id=27";
    assert(selectDisplay(displays, 2, id) == displays + 1);
    puts("PASS: DDC selection rejects zero, negative, overflow, empty and missing identifiers; valid index and ID routing retained");
}
