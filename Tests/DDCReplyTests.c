#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "ddc_reply.h"
#include "ddc_packet.h"

static void finish_checksum(uint8_t *frame) {
    frame[10] = 0x50;
    for (int i = 0; i < 10; i++) frame[10] ^= frame[i];
}
int main(void) {
    uint8_t get_brightness[] = {0x82, 0x01, 0x10, 0xac};
    assert(ddcRequestChecksum(0x51, get_brightness, 3) == 0xac);
    assert(ddcRequestChecksum(0x50, get_brightness, 3) == 0xad);
    assert(ddcRequestLength(get_brightness, sizeof(get_brightness)) == 4);
    uint8_t set_zero[] = {0x84, 0x03, 0x10, 0, 0, 0xa8};
    assert(ddcRequestChecksum(0x51, set_zero, 5) == 0xa8);
    assert(ddcRequestLength(set_zero, sizeof(set_zero)) == 6);
    uint8_t zero_checksum[] = {0x84, 0x03, 0x10, 0, 0xa8, 0};
    assert(ddcRequestChecksum(0x51, zero_checksum, 5) == 0);
    assert(ddcRequestLength(zero_checksum, sizeof(zero_checksum)) == 6);
    assert(ddcRequestLength(zero_checksum, 5) == 0);
    assert(ddcRequestLength(NULL, 6) == 0);
    // Actual Mi HDMI reply after correcting the host source checksum.
    uint8_t mi[11] = {0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 26, 0xda};
    assert(decodeDDCReply(mi, 11, 0x10).curValue == 26);
    // Actual VU241Q reply captured at 51/100 brightness.
    uint8_t frame[12] = {0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 51, 0xf3, 0};
    DDCValue value = decodeDDCReply(frame, 12, 0x10);
    assert(value.curValue == 51 && value.maxValue == 100);
    uint8_t empty[12] = {0};
    assert(decodeDDCReply(empty, 12, 0x10).curValue == -1);
    assert(decodeDDCReply(frame, 10, 0x10).curValue == -1);
    assert(decodeDDCReply(NULL, 12, 0x10).curValue == -1);
    assert(decodeDDCReply(frame, 12, 0x12).curValue == -1);
    frame[10] ^= 1;
    assert(decodeDDCReply(frame, 12, 0x10).curValue == -1);
    frame[3] = 1; finish_checksum(frame);
    assert(decodeDDCReply(frame, 12, 0x10).curValue == -1);
    frame[3] = 0; frame[9] = 0; finish_checksum(frame);
    assert(decodeDDCReply(frame, 12, 0x10).curValue == 0); // Genuine zero is valid.
    frame[6] = 1; frame[7] = 44; frame[8] = 1; frame[9] = 4; finish_checksum(frame);
    value = decodeDDCReply(frame, 12, 0x10);
    assert(value.curValue == 260 && value.maxValue == 300);
    puts("PASS: HDMI request checksum, complete frames, Mi/VU replies, corrupt reply rejection, genuine zero and 16-bit values");
}
