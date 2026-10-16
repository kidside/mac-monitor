#include "../Sources/Native/ModeDescriptor.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static void write32(uint8_t *bytes, size_t offset, uint32_t value) { memcpy(bytes + offset, &value, 4); }
static void writeDensity(uint8_t *bytes, float value) { memcpy(bytes + 0xD0, &value, 4); }

int main(void) {
    // Known Mi mode 73: 1920x1080 logical, 2x backing, 100 Hz. The frequency
    // is at 0xBE (not the preceding reserved word at 0xBC).
    uint8_t bytes[MM_MODE_DESCRIPTOR_SIZE] = {0};
    write32(bytes, 0, 73); write32(bytes, 4, 0x200001);
    write32(bytes, 8, 1920); write32(bytes, 12, 1080);
    uint16_t refresh = 100; memcpy(bytes + 0xBE, &refresh, 2);
    writeDensity(bytes, 2);
    MMModeDetails mode;
    assert(MMParseHiDPIMode(bytes, sizeof(bytes), 73, &mode));
    assert(mode.modeID == 73 && mode.width == 1920 && mode.height == 1080 && mode.refreshRate == 100);
    assert(!MMParseHiDPIMode(bytes, sizeof(bytes) - 1, 73, &mode));
    assert(!MMParseHiDPIMode(NULL, sizeof(bytes), 73, &mode));
    assert(!MMParseHiDPIMode(bytes, sizeof(bytes), 74, &mode));
    writeDensity(bytes, 1); assert(!MMParseHiDPIMode(bytes, sizeof(bytes), 73, &mode));
    writeDensity(bytes, NAN); assert(!MMParseHiDPIMode(bytes, sizeof(bytes), 73, &mode));
    writeDensity(bytes, 2);
    write32(bytes, 4, 0x40000000); assert(!MMParseHiDPIMode(bytes, sizeof(bytes), 73, &mode));
    write32(bytes, 4, 0x200001);
    write32(bytes, 8, UINT32_MAX); assert(!MMParseHiDPIMode(bytes, sizeof(bytes), 73, &mode));
    write32(bytes, 8, 1920);
    refresh = 0; memcpy(bytes + 0xBE, &refresh, 2); assert(!MMParseHiDPIMode(bytes, sizeof(bytes), 73, &mode));
    puts("PASS: hidden Mi HiDPI descriptor, 100 Hz decoding, truncated/corrupt/unsupported mode rejection");
}
