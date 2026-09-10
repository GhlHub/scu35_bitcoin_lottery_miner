/* SPDX-License-Identifier: Apache-2.0 */
#include "ina700.h"
#include <assert.h>
#include <stdio.h>
static unsigned call,fail_at;
static uint16_t config,diag=3,voltage=1600,current=2500,temp=0x1900,id=0x5449;
static uint32_t power=62500;
static int mock_read(uint8_t address,uint8_t reg,uint8_t *b,size_t n){
    assert(address==0x44||address==0x45);
    if(++call==fail_at)return -1;
    uint32_t v=0;
    switch(reg){
    case 0x3e:v=id;break;case 1:v=config;break;case 0xb:v=diag;break;
    case 5:v=voltage;break;case 6:v=temp;break;case 7:v=current;break;
    case 8:v=power;break;default:assert(0);
    }
    assert(n==(reg==8?3U:2U));
    for(size_t i=0;i<n;i++)b[i]=(uint8_t)(v>>(8*(n-1-i)));
    return 0;
}
static int mock_write(uint8_t address,uint8_t reg,uint16_t value){
    assert(address==0x44||address==0x45);assert(reg==1&&value==0xfb6a);
    if(++call==fail_at)return -1;
    config=value;return 0;
}
int main(void){
    ina700_sample s={0};
    assert(!ina700_init(0x44,mock_read,mock_write));
    assert(!ina700_sample_read(0x44,mock_read,&s)&&s.valid);
    assert(s.voltage_uv==5000000&&s.current_ua==1200000&&s.power_uw==6000000&&s.temp_milli_c==50000);
    current=0xffff;temp=0xfff0;voltage=272;power=1;
    assert(!ina700_sample_read(0x45,mock_read,&s));
    assert(s.current_ua==-480&&s.temp_milli_c==-125&&s.voltage_uv==850000&&s.power_uw==96);
    current=0x8000;temp=0x8000;power=0xffffff;
    assert(!ina700_sample_read(0x45,mock_read,&s));
    assert(s.current_ua==-15728640&&s.temp_milli_c==-256000&&s.power_uw==1610612640U);
    for(unsigned i=1;i<=6;i++){
        call=0;fail_at=i;s.valid=1;
        assert(ina700_sample_read(0x44,mock_read,&s)&&!s.valid);
    }
    for(unsigned i=1;i<=3;i++){
        call=0;fail_at=i;assert(ina700_init(0x45,mock_read,mock_write));
    }
    fail_at=0;id=0;assert(ina700_init(0x44,mock_read,mock_write));id=0x5449;
    diag=1;assert(ina700_sample_read(0x44,mock_read,&s)&&!s.valid);
    diag=2;assert(ina700_sample_read(0x44,mock_read,&s)&&!s.valid);
    diag=0x203;assert(ina700_sample_read(0x44,mock_read,&s)&&!s.valid);
    diag=3;config=0xfb68;assert(ina700_sample_read(0x44,mock_read,&s)&&!s.valid);
    assert(!ina700_init(0x44,mock_read,mock_write));
    assert(!ina700_sample_read(0x44,mock_read,&s)&&s.valid);
    puts("PASS: INA700 identity/config, units, signed limits, 24-bit power, read failures and recovery");
}
