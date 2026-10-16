#ifndef MAC_MONITOR_DDC_REPLY_H
#define MAC_MONITOR_DDC_REPLY_H
#include <stdint.h>
#include <stddef.h>

typedef struct { int curValue; int maxValue; } DDCValue;

static inline DDCValue decodeDDCReply(const uint8_t *bytes, size_t length, uint8_t feature) {
    DDCValue invalid = {-1, -1};
    if (!bytes || length < 11 || bytes[0] != 0x6e || bytes[1] != 0x88 ||
        bytes[2] != 0x02 || bytes[3] != 0 || bytes[4] != feature || bytes[5] > 1) return invalid;
    uint8_t checksum = 0x50;
    for (size_t i = 0; i < 11; i++) checksum ^= bytes[i];
    if (checksum != 0) return invalid;
    DDCValue result = {
        .curValue = ((int)bytes[8] << 8) | bytes[9],
        .maxValue = ((int)bytes[6] << 8) | bytes[7]
    };
    return result;
}
#endif
