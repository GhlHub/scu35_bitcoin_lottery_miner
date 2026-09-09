/* SPDX-License-Identifier: Apache-2.0 */
#include "srec.h"
static int hex(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
static int byte(const char *p) {
    int a=hex(p[0]), b=hex(p[1]);
    return a < 0 || b < 0 ? -1 : a*16+b;
}
int srec_parse(const char *line, size_t size, srec_record *r)
{
    unsigned naddr, sum; int count;
    if (size < 4 || line[0]!='S' || line[1]<'0' || line[1]>'9') return -1;
    r->type=(unsigned)(line[1]-'0');
    switch (r->type) {
    case 0: case 1: case 5: case 9: naddr=2; break;
    case 2: case 6: case 8: naddr=3; break;
    case 3: case 7: naddr=4; break;
    default: return -1;
    }
    count=byte(line+2);
    if (count < (int)naddr+1 || size != 4U+2U*(unsigned)count) return -1;
    r->address=0; r->size=(unsigned)count-naddr-1; sum=(unsigned)count;
    if (r->type>=5 && r->size) return -1;
    for (unsigned i=0; i<(unsigned)count; i++) {
        int value=byte(line+4+2*i);
        if (value<0) return -1;
        sum+=(unsigned)value;
        if (i<naddr) r->address=(r->address<<8)|(unsigned)value;
        else if (i<(unsigned)count-1) r->data[i-naddr]=(uint8_t)value;
    }
    return (sum&255U)==255U ? 0 : -1;
}
