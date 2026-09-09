/* SPDX-License-Identifier: Apache-2.0 */
#include "settings.h"
#include "srec.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned char memory[8192],saved[8192];
static int budget=-1;
static int read_mem(uint16_t a,void *p,size_t n){assert(a+n<=sizeof(memory));memcpy(p,memory+a,n);return 0;}
static int write_mem(uint16_t a,const void *p,size_t n){
    assert(a>=4096&&a+n<=5120);
    for(size_t i=0;i<n;i++){
        if(budget==0)return -1;
        if(budget>0)budget--;
        memory[a+i]=((const unsigned char*)p)[i];
    }
    return 0;
}
int main(void){
    miner_settings a,b;memset(memory,255,sizeof(memory));
    assert(settings_load(&a,read_mem)==0);
    assert(!memcmp(a.mac,"\x02\x00\x00\x11\x22\x33",6));
    strcpy(a.host,"pool.example");strcpy(a.worker,"wallet.worker");
    assert(settings_save(&a,read_mem,write_mem)==0);
    assert(settings_load(&b,read_mem)==1&&!memcmp(&a,&b,sizeof(a)));
    memcpy(saved,memory,sizeof(memory));strcpy(a.worker,"new.worker");
    /* Interrupt at every byte of a save. Old settings survive until commit. */
    for(int n=0;n<=513;n++){
        memcpy(memory,saved,sizeof(memory));budget=n;
        int rc=settings_save(&a,read_mem,write_mem);
        assert(settings_load(&b,read_mem)==1);
        assert(!strcmp(b.worker,rc==0?"new.worker":"wallet.worker"));
        assert(!memcmp(memory,saved,4096));
    }
    a.mac[0]=1;assert(!settings_valid(&a));a.mac[0]=2;
    memset(a.host,'x',sizeof(a.host));assert(!settings_valid(&a));
    srec_record r;
    const char *ok="S30980000000010203046C";
    assert(srec_parse(ok,strlen(ok),&r)==0&&r.address==0x80000000&&r.size==4&&r.data[3]==4);
    char bad[80];strcpy(bad,ok);bad[21]='D';assert(srec_parse(bad,strlen(bad),&r)!=0);
    for(size_t n=0;n<strlen(ok);n++)assert(srec_parse(ok,n,&r)!=0);
    assert(srec_parse("S705800000007A",14,&r)==0&&r.type==7);
    assert(srec_parse("S405800000007A",14,&r)!=0);
    puts("PASS: EEPROM atomic saves, validation, SREC bounds/checksums");
}
