#ifndef MAC_MONITOR_NUMERIC_INPUT_H
#define MAC_MONITOR_NUMERIC_INPUT_H
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static inline bool parseDDCWriteValue(bool change, const char *input, int current, int maximum, uint16_t *result) {
    if (!input || !*input || !result) return false;
    long long value;
    if (!strcmp(input, "on")) value = 1;
    else if (!strcmp(input, "off")) value = 2;
    else {
        // Do not silently accept prefixes, whitespace, empty signs or overflow.
        const char *digit = input;
        if (*digit == '+' || *digit == '-') digit++;
        if (!*digit) return false;
        for (const char *p = digit; *p; ++p) if (*p < '0' || *p > '9') return false;
        errno = 0;
        char *end;
        value = strtoll(input, &end, 10);
        if (errno == ERANGE || *end) return false;
    }
    if (change) {
        if (maximum < 0 || maximum > UINT16_MAX || current < 0 || current > maximum) return false;
        // Clamp before adding so even LLONG_MIN/LLONG_MAX cannot overflow.
        if (value < -(long long)current) value = 0;
        else if (value > (long long)maximum - current) value = maximum;
        else value += current;
    } else if (value < 0 || value > UINT16_MAX) return false;
    *result = (uint16_t)value;
    return true;
}
#endif
