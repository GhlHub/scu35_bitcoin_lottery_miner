/* SPDX-License-Identifier: Apache-2.0 */
/* Bare-metal first stage: calibrate, validate/load SREC, install vectors, jump. */
#include <stdint.h>
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "mb_interface.h"
#include "hyperbus_odly.h"
#include "srec.h"
#include "versions.h"

#define HB 0x00010000U
#define SPI 0x44A00000U
#define FLASH_START 0x00800000U
#define FLASH_END 0x01000000U
#define RAM_START 0x80000000U
#define RAM_END 0x80800000U
static uint8_t cache[64], vectors[0x50], seen[0x50];
static uint32_t flash=FLASH_START;
static unsigned pos=64;
static char line[514];
static srec_record record;
extern void console_init(void);
static void delay(unsigned n) { while (n--) __asm__ volatile("nop"); }

/* AXI Quad SPI polled standard-mode READ; hardware is configured in quad mode
 * but decodes opcode 03 as a one-lane transaction. Bound every status wait. */
static int transfer(const uint8_t *tx, uint8_t *rx, unsigned n)
{
    unsigned guard=1000000;
    Xil_Out32(SPI+0x60,0x1E6); /* master, enabled, manual SS, FIFO reset, inhibit */
    Xil_Out32(SPI+0x60,0x186);
    for (unsigned i=0;i<n;i++) Xil_Out32(SPI+0x68,tx[i]);
    Xil_Out32(SPI+0x70,0xFFFFFFFE);
    Xil_Out32(SPI+0x60,0x086);
    for (unsigned i=0;i<n;i++) {
        while ((Xil_In32(SPI+0x64)&1U) && --guard) {}
        if (!guard) {
            Xil_Out32(SPI+0x60,0x186);
            Xil_Out32(SPI+0x70,0xFFFFFFFF);
            return -1;
        }
        rx[i]=(uint8_t)Xil_In32(SPI+0x6c);
    }
    Xil_Out32(SPI+0x60,0x186);
    Xil_Out32(SPI+0x70,0xFFFFFFFF);
    return 0;
}
static int get_byte(void)
{
    if(pos==sizeof(cache)) {
        uint8_t tx[68]={3,(uint8_t)(flash>>16),(uint8_t)(flash>>8),(uint8_t)flash};
        uint8_t rx[68];
        if(flash>FLASH_END-sizeof(cache) || transfer(tx,rx,sizeof(tx))) return -1;
        for(unsigned i=0;i<sizeof(cache);i++) cache[i]=rx[i+4];
        flash+=sizeof(cache);pos=0;
    }
    return cache[pos++];
}
static int load(uint32_t *entry)
{
    uint32_t data_records=0, low=RAM_END, high=RAM_START;
    for (;;) {
        int c; size_t n=0;
        do {c=get_byte();} while(c=='\r'||c=='\n');
        if(c!='S') {xil_printf("SREC start %x byte %x\r\n",flash-64+pos-1,c);return -1;}
        line[n++]=(char)c;
        for (;;) {
            c=get_byte();
            if(c<0 || n==sizeof(line)) return -1;
            if(c=='\r'||c=='\n') break;
            line[n++]=(char)c;
        }
        if(srec_parse(line,n,&record)) {xil_printf("SREC parse near %x size %d\r\n",flash-64+pos,n);return -1;}
        if(record.type==0) continue;
        if(record.type==5||record.type==6) {
            if(record.address!=data_records) return -1;
            continue;
        }
        if(record.type>=7) {
            *entry=record.address;
            return data_records && *entry>=low && *entry<high && !(*entry&3U) ? 0 : -1;
        }
        uint32_t a=record.address;
        if(a<sizeof(vectors) && record.size<=sizeof(vectors)-a) {
            for(unsigned i=0;i<record.size;i++){vectors[a+i]=record.data[i];seen[a+i]=1;}
        } else if(a>=RAM_START && a<RAM_END && record.size<=RAM_END-a) {
            for(unsigned i=0;i<record.size;i++) {
                Xil_Out8(a+i,record.data[i]);
                uint8_t actual=Xil_In8(a+i);
                if(actual!=record.data[i]) {
                    xil_printf("RAM verify %x wrote %x read %x\r\n",a+i,record.data[i],actual);
                    return -1;
                }
            }
            if(a<low)low=a;
            if(a+record.size>high)high=a+record.size;
        } else return -1;
        data_records++;
    }
}
int main(void)
{
    uint16_t lo,hi,mid; uint32_t entry;
    static const uint8_t offsets[]={0,8,16,32};
    microblaze_disable_interrupts();
    Xil_ICacheDisable();Xil_DCacheDisable();console_init();
    xil_printf("SCU35 50MHz SREC boot v" BOOTLOADER_VERSION "\r\n");
    Xil_Out32(MINER_BOOT_VERSION_REG,BOOTLOADER_VERSION_CODE);
    delay(50000); /* power-on guard before the first HyperRAM command */
    if(hb_idelayctrl_reset_wait_ready(HB,0x8000)) goto fail;
    uint32_t reset=Xil_In32(HB+HB_DELAY_RST_CTRL_OFFSET);
    Xil_Out32(HB+HB_DELAY_RST_CTRL_OFFSET,reset|HB_DELAY_RST_HB_RESET);
    delay(50000);
    Xil_Out32(HB+HB_DELAY_RST_CTRL_OFFSET,reset&~HB_DELAY_RST_HB_RESET);
    delay(50000);
    if(hb_rwds_idly_dec_below_16(HB) ||
       hb_odly_sweep_to_midpoint(HB,&lo,&hi,&mid)) goto fail;
    /* The sweep's initial CR0 read occurs before the timing is calibrated.
     * Set latency explicitly after calibration: seven clocks at 200 MHz,
     * matching HB_LATENCY_DEFAULT=7. Explicitly restore all fields rather
     * than preserving a possibly invalid pre-calibration register value:
     * normal operation, 46-ohm drive, reserved ones, fixed 2x, 32-byte wrap. */
    uint32_t cr0=0xBF2FU;
    Xil_Out32(HB+HB_CR0_OFFSET,cr0);
    if ((Xil_In32(HB+HB_CR0_OFFSET)&0xffffU)!=(cr0&0xffffU)) goto fail;
    xil_printf("HyperRAM window %x..%x midpoint %x\r\n",lo,hi,mid);
    xil_printf("HyperRAM CR0 %x\r\n",cr0);
    Xil_Out32(SPI+0x40,0xA); Xil_Out32(SPI+0x1c,0); /* soft reset, IRQs off */
    {uint8_t tx[4]={0x9f,0,0,0},rx[4];
     /* STARTUP consumes initial clocks while handing CCLK to user logic.
      * Match the dummy Read-ID initialization in AMD XSpi_CfgInitialize
      * (CR #721229); discard this bounded transfer before the real command. */
     (void)transfer(tx,rx,4);
     if(transfer(tx,rx,4)||rx[1]==0||rx[1]==255){
         xil_printf("Flash ID read failed\r\n");goto fail;
     }
     xil_printf("Flash %02x%02x%02x SREC @ %08x\r\n",rx[1],rx[2],rx[3],FLASH_START);}
    if(load(&entry)) goto fail;
    for(unsigned i=0;i<sizeof(offsets);i++)
        for(unsigned j=0;j<8;j++)if(!seen[offsets[i]+j])goto fail;
    /* All record, memory and vector checks completed before touching live vectors. */
    for(unsigned i=0;i<sizeof(offsets);i++)
        for(unsigned j=0;j<8;j++)Xil_Out8(offsets[i]+j,vectors[offsets[i]+j]);
    Xil_ICacheInvalidate();
    xil_printf("Jump %08x\r\n",entry);
    ((void(*)(void))(uintptr_t)entry)();
fail:
    xil_printf("Boot failed; application not started\r\n");
    for(;;)__asm__ volatile("nop");
}
