@import Foundation;
#include <assert.h>
#include <string.h>
#include "i2c.h"

static uint8_t sent[8];
static uint32_t sentLength, sentSource;
static int writes;

IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chip, uint32_t source, void *bytes, uint32_t length) {
    assert(chip == DDC_CHIP_ADDRESS_DEFAULT && length <= sizeof(sent));
    memcpy(sent, bytes, length);
    sentLength = length; sentSource = source; writes++;
    return kIOReturnSuccess;
}
IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chip, uint32_t offset, void *bytes, uint32_t length) {
    assert(chip == DDC_CHIP_ADDRESS_DEFAULT && offset == 0 && length == 11);
    const uint8_t reply[11] = {0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 26, 0xda};
    memcpy(bytes, reply, sizeof(reply));
    return kIOReturnSuccess;
}
int main(void) {
    DDCPacket request = createDDCPacket(LUMINANCE);
    request.data[3] = 0xff; // Reusing a packet must not poison its checksum.
    prepareDDCRead(&request);
    assert(request.data[3] == 0xac);
    prepareDDCRead(&request);
    assert(request.data[3] == 0xac);
    assert(performDDCWriteAtChipAddress(NULL, DDC_CHIP_ADDRESS_DEFAULT, &request) == kIOReturnSuccess);
    assert(writes == DDC_ITERATIONS && sentLength == 4 && sentSource == 0x51 && sent[3] == 0xac);
    prepareDDCWrite(&request, 168); // Includes a trailing zero checksum.
    assert(request.data[5] == 0);
    assert(performDDCWriteAtChipAddress(NULL, DDC_CHIP_ADDRESS_DEFAULT, &request) == kIOReturnSuccess);
    assert(sentLength == 6 && sent[4] == 168 && sent[5] == 0);
    prepareDDCWrite(&request, 0);
    assert(request.data[3] == 0 && request.data[4] == 0 && request.data[5] == 0xa8);
    assert(performDDCReadAtChipAddress(NULL, DDC_CHIP_ADDRESS_DEFAULT, &request) == kIOReturnSuccess);
    assert(decodeDDCReply(request.data, 11, LUMINANCE).curValue == 26);
    memset(request.data, 0, sizeof(request.data));
    assert(performDDCWriteAtChipAddress(NULL, DDC_CHIP_ADDRESS_DEFAULT, &request) == kIOReturnBadArgument);
    puts("PASS: actual Get/Set packet construction, complete I2C writes and HDMI read addressing");
}
