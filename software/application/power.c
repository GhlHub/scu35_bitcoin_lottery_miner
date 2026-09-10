/* SPDX-License-Identifier: Apache-2.0 */
/* Dedicated polled AXI IIC dynamic-mode bus. Never accesses EEPROM/PMICs.
 * Each transaction has a bounded deadline and yields; errors reset only this
 * IIC core. A physically stuck bus remains unavailable until released. */
#include "app.h"
#include "task.h"
#include "xil_io.h"
#include "versions.h"
#include "ina700.h"
#define IIC 0x40810000U
static uint32_t rd(unsigned r){return Xil_In32(IIC+r);}
static void wr(unsigned r,uint32_t v){Xil_Out32(IIC+r,v);}
static TickType_t deadline_start;
static int wait_status(unsigned mask,unsigned expected,unsigned errors){
    for(;;){
        if(rd(0x20)&errors)return -1;
        if((rd(0x104)&mask)==expected)return 0;
        if(xTaskGetTickCount()-deadline_start>=pdMS_TO_TICKS(100))return -1;
        vTaskDelay(1);
    }
}
static int begin(uint8_t address,uint8_t reg){
    deadline_start=xTaskGetTickCount();
    wr(0x40,10); /* reset controller, including stale NACK/FIFO state */
    wr(0x120,15);wr(0x100,3);wr(0x100,1);
    wr(0x20,rd(0x20)); /* toggle-on-write IRQ status; IRQs remain disabled */
    if(wait_status(4,0,1))return -1;
    wr(0x108,0x100U|((uint32_t)address<<1));wr(0x108,reg);
    return 0;
}
static int read_reg(uint8_t address,uint8_t reg,uint8_t *data,size_t size){
    if(!size||size>3||begin(address,reg))goto fail;
    /* Drain register pointer before repeated START so an address/data NACK
     * cannot be mistaken for the deliberate final-byte receive NACK. */
    if(wait_status(0x80,0x80,3))goto fail;
    wr(0x108,0x101U|((uint32_t)address<<1));wr(0x108,0x200U|(unsigned)size);
    for(size_t n=0;n<size;n++){
        if(wait_status(0x40,0,1))goto fail;
        data[n]=(uint8_t)rd(0x10c);
    }
    if(wait_status(4,0,1))goto fail;
    return 0;
fail: wr(0x40,10);return -1;
}
static int write_reg(uint8_t address,uint8_t reg,uint16_t value){
    if(begin(address,reg))goto fail;
    wr(0x108,value>>8);wr(0x108,0x200U|(value&255));
    if(wait_status(0x80,0x80,3)||wait_status(4,0,3))goto fail;
    return 0;
fail: wr(0x40,10);return -1;
}
static void power_task(void *unused){
    (void)unused;
    ina700_sample samples[2]={{0}};int ready[2]={0};
    TickType_t last=xTaskGetTickCount();
    for(;;){
        for(unsigned n=0;n<2;n++){
            uint8_t address=(uint8_t)(0x44+n);
            samples[n].valid=0;
            if(!ready[n]){
                ready[n]=ina700_init(address,read_reg,write_reg)==0;
                if(!ready[n])samples[n].errors++;
                /* Allow a complete averaged conversion before first read. */
            }else if(ina700_sample_read(address,read_reg,&samples[n])){
                samples[n].errors++;ready[n]=0;
            }else samples[n].sampled_ms=xTaskGetTickCount()*portTICK_PERIOD_MS;
        }
        telemetry_power(samples);
        vTaskDelayUntil(&last,pdMS_TO_TICKS(1000));
    }
}
void power_start(void){
    /* Avoid touching an unmapped peripheral if new firmware boots on old HW. */
    if(Xil_In32(MINER_HW_VERSION_REG)!=0x01020000U)return;
    configASSERT(xTaskCreate(power_task,"power",1024,0,1,0)==pdPASS);
}
