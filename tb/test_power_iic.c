/* SPDX-License-Identifier: Apache-2.0 */
/* Host model exercises the actual bounded AXI IIC transaction functions. */
#include <assert.h>
#include <stdio.h>
#include "xil_types.h"
#define XIL_IO_H
#include "FreeRTOS.h"
#include "task.h"
static unsigned scenario,tx_count,rx_count,resets,tx[8];
static TickType_t ticks;
static inline u32 Xil_In32(UINTPTR address){
    assert(address>=0x40810000U&&address<0x40810200U);
    unsigned r=address-0x40810000U;
    if(r==0x20){
        if(scenario==2&&tx_count>=2)return 2; /* address NACK */
        if(scenario==3&&tx_count>=4)return 1; /* arbitration lost */
        if(tx_count>=4&&((tx[2]&0x100)||scenario==6))return 2; /* final receive NACK, or write error */
        return 0;
    }
    if(r==0x104){
        int reading=tx_count>=4&&(tx[2]&0x100);
        unsigned count=reading?(tx[3]&255):0;
        int empty=!reading||rx_count>=count||scenario==4;
        int busy=scenario==1||scenario==5||(reading&&rx_count<count);
        return 0x80U|(empty?0x40U:0)|(busy?4U:0);
    }
    if(r==0x10c){rx_count++;return 0x40U+rx_count;}
    assert(0);return 0;
}
static inline void Xil_Out32(UINTPTR address,u32 value){
    assert(address>=0x40810000U&&address<0x40810200U);
    unsigned r=address-0x40810000U;
    if(r==0x40){assert(value==10);resets++;tx_count=rx_count=0;}
    if(r==0x108){assert(tx_count<8);tx[tx_count++]=value;}
}
#include "../software/application/power.c"
TickType_t xTaskGetTickCount(void){return ticks;}
void vTaskDelay(TickType_t n){ticks+=n;}
int main(void){
    uint8_t b[3];
    assert(!read_reg(0x44,8,b,3));
    assert(tx_count==4&&tx[0]==0x188&&tx[1]==8&&tx[2]==0x189&&tx[3]==0x203);
    assert(b[0]==0x41&&b[1]==0x42&&b[2]==0x43);
    /* Write path cannot ignore TX_ERROR; receive final-byte NACK can. */
    assert(!write_reg(0x45,1,INA700_ADC_CONFIG));
    assert(tx[0]==0x18a&&tx[1]==1&&tx[2]==0xfb&&tx[3]==0x26a);
    scenario=6;assert(write_reg(0x45,1,INA700_ADC_CONFIG));
    for(scenario=1;scenario<=5;scenario++){
        ticks=0;unsigned before=resets;
        assert(read_reg(0x45,5,b,2)==-1);
        assert(resets>=before+2&&ticks<=pdMS_TO_TICKS(100));
    }
    scenario=0;ticks=0;
    assert(!read_reg(0x45,5,b,2));
    assert(tx[0]==0x18a&&tx[2]==0x18b&&tx[3]==0x202);
    assert(read_reg(0x44,5,b,0)==-1);
    puts("PASS: dedicated IIC address/START/repeated-START/STOP, NACK, arbitration, stuck bus and recovery");
}
