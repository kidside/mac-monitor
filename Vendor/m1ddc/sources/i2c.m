@import Foundation;

#include "i2c.h"
#include "utils.h"

// Function to get ready for DDC operations for a specific display attribute
DDCPacket createDDCPacket(UInt8 attrCode) {
    DDCPacket packet = {};
    packet.data[2] = attrCode;
    packet.inputAddr = packet.data[2] == INPUT_ALT ? ALTERNATE_INPUT_ADDRESS : DEFAULT_INPUT_ADDRESS;
    return packet;
}

// Prepare DDC packet for read
void prepareDDCRead(DDCPacket *packet) {
    UInt8 *data = packet->data;
    data[0] = 0x82;
    data[1] = 0x01;
    data[3] = ddcRequestChecksum(packet->inputAddr, data, 3);
}

// Prepare DDC packet for write
void prepareDDCWrite(DDCPacket *packet, UInt16 newValue) {
    UInt8* data = packet->data;
    data[0] = 0x84;
    data[1] = 0x03;
    data[3] = (newValue) >> 8;
    data[4] = newValue & 255;
    data[5] = ddcRequestChecksum(packet->inputAddr, data, 5);
}


IOReturn performDDCReadAtChipAddress(IOAVServiceRef avService, UInt32 chipAddress, DDCPacket *packet) {
    memset(packet->data, 0, sizeof(UInt8) * DDC_BUFFER_SIZE);
    usleep(DDC_READ_WAIT);
    // The host source address belongs to writes, not to the reply's subaddress.
    return IOAVServiceReadI2C(avService, chipAddress, 0, packet->data, 11);
}

IOReturn performDDCWriteAtChipAddress(IOAVServiceRef avService, UInt32 chipAddress, DDCPacket *packet) {
    IOReturn ret;
    size_t length = ddcRequestLength(packet->data, sizeof(packet->data));
    if (!length) return kIOReturnBadArgument;

    for (int i = 0; i < DDC_ITERATIONS; ++i) {
        usleep(DDC_WAIT);
        if ((ret = IOAVServiceWriteI2C(avService, chipAddress, packet->inputAddr, packet->data, (UInt32)length))) {
            return ret;
        }
    }
    return ret;
}

IOReturn performDDCRead(IOAVServiceRef avService, DDCPacket *packet) {
    return performDDCReadAtChipAddress(avService, DDC_CHIP_ADDRESS_DEFAULT, packet);
}

IOReturn performDDCWrite(IOAVServiceRef avService, DDCPacket *packet) {
    return performDDCWriteAtChipAddress(avService, DDC_CHIP_ADDRESS_DEFAULT, packet);
}
