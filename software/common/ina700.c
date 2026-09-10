/* SPDX-License-Identifier: Apache-2.0 */
/* TI INA700 SBOSAB4B, sections 6.6.1.2--6.6.1.9. All bus data MSB first. */
#include "ina700.h"
static uint16_t be16(const uint8_t *p){return ((uint16_t)p[0]<<8)|p[1];}
static int32_t signed16(uint16_t v){return v&0x8000U?(int32_t)v-65536:(int32_t)v;}
int ina700_init(uint8_t address,ina700_read_fn read,ina700_write_fn write){
    uint8_t b[2];
    if(read(address,0x3e,b,2)||be16(b)!=0x5449)return -1;
    if(write(address,1,INA700_ADC_CONFIG)||read(address,1,b,2))return -1;
    return be16(b)==INA700_ADC_CONFIG?0:-1;
}
int ina700_sample_read(uint8_t address,ina700_read_fn read,ina700_sample *out){
    uint8_t config[2],diag[2],v[2],i[2],t[2],p[3];
    out->valid=0;
    if(read(address,1,config,2)||be16(config)!=INA700_ADC_CONFIG||
       read(address,0x0b,diag,2)||(be16(diag)&0x203)!=3||
       read(address,5,v,2)||read(address,6,t,2)||
       read(address,7,i,2)||read(address,8,p,3))return -1;
    out->voltage_uv=(uint32_t)be16(v)*3125U;
    out->current_ua=signed16(be16(i))*480;
    out->temp_milli_c=(signed16(be16(t)&0xfff0U)/16)*125;
    out->power_uw=(((uint32_t)p[0]<<16)|((uint32_t)p[1]<<8)|p[2])*96U;
    out->valid=1;
    return 0;
}
