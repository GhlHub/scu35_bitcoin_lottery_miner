/* SPDX-License-Identifier: Apache-2.0 */
/* Compile the actual interface with host MMIO storage; dead-strip RTOS paths. */
#include <assert.h>
#include <stdio.h>
#include "xil_types.h"
#define XIL_IO_H
static inline u32 Xil_In32(UINTPTR a){return *(volatile u32*)a;}
static inline void Xil_Out32(UINTPTR a,u32 v){*(volatile u32*)a=v;}
#include "../software/application/NetworkInterface.c"
static uint32_t memory[2048] __attribute__((aligned(4096)));
static unsigned copies;
u16 XEmacLite_GetReceiveDataLength(UINTPTR base){
    uint32_t word=XEmacLite_ReadReg(base,XEL_RXBUFF_OFFSET+12);
    return (u16)(((word&255)<<8)|((word>>8)&255));
}
u16 XEmacLite_Recv(XEmacLite *instance,u8 *frame){
    (void)frame;copies++;
    UINTPTR base=XEmacLite_NextReceiveAddr(instance);
    if(!(XEmacLite_GetRxStatus(base)&XEL_RSR_RECV_DONE_MASK))base^=XEL_BUFFER_OFFSET;
    unsigned n=28;
    if(XEmacLite_GetReceiveDataLength(base)==XEL_ETHER_PROTO_TYPE_IP){
        uint32_t word=XEmacLite_ReadReg(base,XEL_RXBUFF_OFFSET+16);
        n=((word&255)<<8)|((word>>8)&255);
    }
    XEmacLite_SetRxStatus(base,0);
    return (u16)(n+18);
}
static void frame(unsigned type,unsigned length){
    memset(memory,0,sizeof(memory));
    UINTPTR base=(UINTPTR)memory;
    mac.EmacLiteConfig.BaseAddress=base;mac.EmacLiteConfig.RxPingPong=1;mac.NextRxBufferToUse=0;
    XEmacLite_WriteReg(base,XEL_RXBUFF_OFFSET+12,((type&255)<<8)|(type>>8));
    XEmacLite_WriteReg(base,XEL_RXBUFF_OFFSET+16,((length&255)<<8)|(length>>8));
    XEmacLite_SetRxStatus(base,XEL_RSR_RECV_DONE_MASK);
}
int main(void){
    uint8_t bytes[1536];
    frame(0x0800,1500);assert(bounded_receive(bytes)==1514&&copies==1);
    frame(0x0800,1501);assert(bounded_receive(bytes)==-1&&copies==1);
    frame(0x0800,65535);assert(bounded_receive(bytes)==-1&&copies==1);
    frame(0x0800,19);assert(bounded_receive(bytes)==-1&&copies==1);
    frame(0x0806,0);assert(bounded_receive(bytes)==42&&copies==2);
    frame(0x8100,100);assert(bounded_receive(bytes)==-1&&copies==2);
    assert(bounded_receive(bytes)==0);
    puts("PASS: Ethernet RX bounds checked before copy; FCS removed");
}
