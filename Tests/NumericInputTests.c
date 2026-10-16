#include <assert.h>
#include <stdio.h>
#include "numeric_input.h"
int main(void) {
    uint16_t value;
    const char *bad[] = {"", " ", "+", "-", "12x", " 12", "12 ", "65536", "-1", "9223372036854775808"};
    for (size_t i=0; i<sizeof(bad)/sizeof(*bad); ++i) assert(!parseDDCWriteValue(false,bad[i],0,100,&value));
    assert(parseDDCWriteValue(false,"0",0,100,&value) && value == 0);
    assert(parseDDCWriteValue(false,"65535",0,100,&value) && value == 65535);
    assert(parseDDCWriteValue(false,"on",0,100,&value) && value == 1);
    assert(parseDDCWriteValue(true,"10",50,100,&value) && value == 60);
    assert(parseDDCWriteValue(true,"-10",50,100,&value) && value == 40);
    assert(parseDDCWriteValue(true,"9223372036854775807",50,100,&value) && value == 100);
    assert(parseDDCWriteValue(true,"-9223372036854775808",50,100,&value) && value == 0);
    assert(!parseDDCWriteValue(true,"1",101,100,&value));
    assert(!parseDDCWriteValue(false,NULL,0,100,&value));
    puts("PASS: complete numeric input, 16-bit bounds, overflow rejection and saturating signed changes");
}
