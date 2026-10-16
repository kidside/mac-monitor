#ifndef MM_DDC_PACKET_H
#define MM_DDC_PACKET_H
#include <stddef.h>
#include <stdint.h>

static inline uint8_t ddcRequestChecksum(uint8_t source, const uint8_t *bytes, size_t length) {
    uint8_t checksum = 0x6e ^ source;
    for (size_t i = 0; i < length; i++) checksum ^= bytes[i];
    return checksum;
}

// The length byte counts the payload, excluding itself and the checksum.
// A trailing zero is still part of the frame and must be transmitted.
static inline size_t ddcRequestLength(const uint8_t *bytes, size_t capacity) {
    if (!bytes || capacity < 2 || !(bytes[0] & 0x80)) return 0;
    size_t length = (bytes[0] & 0x7f) + 2;
    return length <= capacity ? length : 0;
}
#endif
