#ifndef MM_MODE_DESCRIPTOR_H
#define MM_MODE_DESCRIPTOR_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#define MM_MODE_DESCRIPTOR_SIZE 0xD4
typedef struct {
    int32_t modeID;
    uint32_t width, height;
    uint16_t refreshRate;
} MMModeDetails;

// SkyLight's mode descriptor is opaque. Validate the fields we use before
// exposing additional 2x modes; unknown layouts fail closed.
static inline bool MMParseHiDPIMode(const void *data, size_t size, int32_t index, MMModeDetails *result) {
    if (!data || !result || size < MM_MODE_DESCRIPTOR_SIZE || index < 0) return false;
    const uint8_t *bytes = data;
    uint32_t mode, flags, width, height;
    uint16_t refresh;
    float density;
    memcpy(&mode, bytes, 4);
    memcpy(&flags, bytes + 4, 4);
    memcpy(&width, bytes + 8, 4);
    memcpy(&height, bytes + 12, 4);
    memcpy(&refresh, bytes + 0xBE, 2);
    memcpy(&density, bytes + 0xD0, 4);
    if (mode != (uint32_t)index || !(flags & 1) || density != 2.0f ||
        width < 320 || width > 7680 || height < 200 || height > 4320 ||
        refresh == 0 || refresh > 1000) return false;
    *result = (MMModeDetails){index, width, height, refresh};
    return true;
}
#endif
