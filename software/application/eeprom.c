/* SPDX-License-Identifier: Apache-2.0 */
/* M24C64, 7-bit address 0x50, 16-bit address, 32-byte write pages. */
#include "settings.h"
#include "xil_io.h"
#include "FreeRTOS.h"
#include "task.h"
#define IIC 0x40800000U
static uint32_t rd(unsigned r){return Xil_In32(IIC+r);}
static void wr(unsigned r,uint32_t v){Xil_Out32(IIC+r,v);}
static int wait_status(unsigned mask,unsigned expected) {
    for(unsigned n=0;n<100000;n++)if((rd(0x104)&mask)==expected)return 0;
    return -1;
}
static int start(uint16_t address) {
    if(wait_status(4,0))return -1;
    wr(0x40,10);wr(0x120,15);wr(0x100,3);wr(0x100,1);
    wr(0x20,rd(0x20));
    wr(0x108,0x1a0);wr(0x108,address>>8);wr(0x108,address&255);
    return 0;
}
static int finish(void) {
    if(wait_status(0x80,0x80)||wait_status(4,0)||(rd(0x20)&3)) {
        wr(0x40,10);return -1;
    }
    return 0;
}
int eeprom_read(uint16_t address,void *buffer,size_t size) {
    uint8_t *p=buffer;
    if((size_t)address+size>8192)return -1;
    while(size){
        unsigned n=size>16?16:(unsigned)size;
        if(start(address))return -1;
        wr(0x108,0x1a1);wr(0x108,0x200|n);
        for(unsigned i=0;i<n;i++) {
            if(wait_status(0x40,0)){wr(0x40,10);return -1;}
            *p++=(uint8_t)rd(0x10c);
        }
        /* TX_ERROR can signal the intentional NACK on the final read byte. */
        if(wait_status(4,0)||(rd(0x20)&1)){wr(0x40,10);return -1;}
        address+=(uint16_t)n;size-=n;
    }
    return 0;
}
int eeprom_write(uint16_t address,const void *buffer,size_t size) {
    const uint8_t *p=buffer;
    if(address<SETTINGS_SLOT0 || (size_t)address+size>SETTINGS_SLOT1+SETTINGS_SLOT_SIZE)return -1;
    while(size){
        unsigned n=32-(address&31);
        if(n>size)n=(unsigned)size;
        if(start(address))return -1;
        for(unsigned i=0;i<n;i++) {
            if(wait_status(0x10,0)){wr(0x40,10);return -1;}
            wr(0x108,*p++|(i==n-1?0x200:0));
        }
        if(finish())return -1;
        vTaskDelay(pdMS_TO_TICKS(10)+1); /* exceeds EEPROM maximum write cycle */
        address+=(uint16_t)n;size-=n;
    }
    return 0;
}
