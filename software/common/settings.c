/* SPDX-License-Identifier: Apache-2.0 */
#include "settings.h"
#include <string.h>
#define COMMIT 0xa5
static uint32_t u32(const uint8_t *p) {
    return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
static void put32(uint8_t *p,uint32_t n) {for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static uint32_t crc(const uint8_t *p,size_t n) {
    uint32_t c=~0U;
    while(n--){c^=*p++;for(unsigned i=0;i<8;i++)c=(c>>1)^((0U-(c&1U))&0xedb88320U);}
    return ~c;
}
void settings_defaults(miner_settings *s) {
    static const uint8_t mac[6]={2,0,0,0x11,0x22,0x33};
    memset(s,0,sizeof(*s));memcpy(s->mac,mac,6);s->port=3333;
}
static int string_ok(const char *s,size_t n) {
    for(size_t i=0;i<n;i++) {
        if(!s[i])return 1;
        /* Credentials can be encoded directly in JSON without escape ambiguity. */
        if((unsigned char)s[i]<32 || (unsigned char)s[i]>126 || s[i]=='"' || s[i]=='\\')return 0;
    }
    return 0;
}
int settings_valid(const miner_settings *s) {
    unsigned any=0;
    for(unsigned i=0;i<6;i++)any|=s->mac[i];
    if(!any || (s->mac[0]&1) || !s->port)return 0;
    if(!string_ok(s->host,sizeof(s->host)) || !string_ok(s->worker,sizeof(s->worker)) ||
       !string_ok(s->password,sizeof(s->password)))return 0;
    for(const char *p=s->host;*p;p++)if(!((*p>='a'&&*p<='z')||(*p>='A'&&*p<='Z')||
        (*p>='0'&&*p<='9')||*p=='.'||*p=='-'))return 0;
    return 1;
}
static void unpack(miner_settings *s,const uint8_t *b) {
    memcpy(s->mac,b+16,6);s->port=(uint16_t)(b[22]|(b[23]<<8));
    memcpy(s->host,b+24,96);memcpy(s->worker,b+120,128);memcpy(s->password,b+248,64);
}
static int record_valid(const uint8_t *b) {
    miner_settings s;
    if(memcmp(b,"S35C",4)||b[4]!=1||b[511]!=COMMIT||u32(b+504)!=crc(b,504))return 0;
    unpack(&s,b);return settings_valid(&s);
}
static int read_slots(uint8_t b[2][512],settings_read read) {
    if(read(SETTINGS_SLOT0,b[0],512)||read(SETTINGS_SLOT1,b[1],512))return -2;
    int a=record_valid(b[0]),c=record_valid(b[1]);
    if(!a&&!c)return -1;
    if(!a)return 1;
    if(!c)return 0;
    return (int32_t)(u32(b[1]+8)-u32(b[0]+8))>0?1:0;
}
int settings_load(miner_settings *s,settings_read read) {
    uint8_t b[2][512];int slot=read_slots(b,read);
    settings_defaults(s);
    if(slot==-2)return -1;
    if(slot<0)return 0;
    unpack(s,b[slot]);return 1;
}
int settings_save(const miner_settings *s,settings_read read,settings_write write) {
    uint8_t slots[2][512],b[512]={0},verify[512],commit=0;
    if(!settings_valid(s))return -1;
    int active=read_slots(slots,read);
    if(active==-2)return -1;
    uint32_t seq=active<0?0:u32(slots[active]+8)+1;
    uint16_t addr=active==0?SETTINGS_SLOT1:SETTINGS_SLOT0;
    memcpy(b,"S35C",4);b[4]=1;put32(b+8,seq);memcpy(b+16,s->mac,6);
    b[22]=(uint8_t)s->port;b[23]=(uint8_t)(s->port>>8);
    memcpy(b+24,s->host,96);memcpy(b+120,s->worker,128);memcpy(b+248,s->password,64);
    put32(b+504,crc(b,504));
    if(write(addr+511,&commit,1)||write(addr,b,511)||read(addr,verify,512)||memcmp(b,verify,512))return -1;
    commit=COMMIT;
    if(write(addr+511,&commit,1)||read(addr,verify,512)||!record_valid(verify))return -1;
    return 0;
}
