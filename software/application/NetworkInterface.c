/* SPDX-License-Identifier: Apache-2.0 */
#include <string.h>
#include "FreeRTOS.h"
#include "task.h"
#include "FreeRTOS_IP.h"
#include "FreeRTOS_IP_Private.h"
#include "FreeRTOS_Routing.h"
#include "NetworkBufferManagement.h"
#include "xemaclite.h"
#include "xparameters.h"
#include "xil_printf.h"
static XEmacLite mac;
static TaskHandle_t rx_task;
static NetworkInterface_t *iface;
static int phy=-1;
extern uint8_t active_mac[6];
#define BUFFER_BYTES ((1536+ipBUFFER_PADDING+31)&~31)
size_t uxNetworkInterfaceAllocateRAMToBuffers(NetworkBufferDescriptor_t b[ipconfigNUM_NETWORK_BUFFER_DESCRIPTORS]) {
    static uint8_t storage[ipconfigNUM_NETWORK_BUFFER_DESCRIPTORS][BUFFER_BYTES] __attribute__((aligned(32)));
    for(unsigned i=0;i<ipconfigNUM_NETWORK_BUFFER_DESCRIPTORS;i++){
        *(NetworkBufferDescriptor_t**)storage[i]=&b[i];
        b[i].pucEthernetBuffer=storage[i]+ipBUFFER_PADDING;
    }
    return BUFFER_BYTES-ipBUFFER_PADDING;
}
static void receive_irq(void *unused) {
    (void)unused;BaseType_t wake=pdFALSE;
    vTaskNotifyGiveFromISR(rx_task,&wake);portYIELD_FROM_ISR(wake);
}
static void sent_irq(void *unused){(void)unused;}
static int bounded_receive(uint8_t *frame){
    UINTPTR base=XEmacLite_NextReceiveAddr(&mac);
    uint32_t status=XEmacLite_GetRxStatus(base);
    if(!(status&XEL_RSR_RECV_DONE_MASK)){
        base^=XEL_BUFFER_OFFSET;status=XEmacLite_GetRxStatus(base);
        if(!(status&XEL_RSR_RECV_DONE_MASK))return 0;
    }
    uint32_t type_word=XEmacLite_ReadReg(base,XEL_RXBUFF_OFFSET+12);
    uint16_t type=(uint16_t)(((type_word&255)<<8)|((type_word>>8)&255));
    int valid=type==XEL_ETHER_PROTO_TYPE_ARP;
    if(type==XEL_ETHER_PROTO_TYPE_IP){
        /* Vendor Recv derives copy length from the untrusted IPv4 header.
         * Validate before calling it, not after a potentially oversized copy. */
        uint32_t word=XEmacLite_ReadReg(base,XEL_RXBUFF_OFFSET+XEL_HEADER_IP_LENGTH_OFFSET);
        unsigned length=((word&255)<<8)|((word>>8)&255);
        valid=length>=20&&length<=ipconfigNETWORK_MTU;
    }
    if(!valid){XEmacLite_SetRxStatus(base,status&~XEL_RSR_RECV_DONE_MASK);return -1;}
    unsigned n=XEmacLite_Recv(&mac,frame);
    /* Driver includes its four-byte FCS allowance; the IP stack does not. */
    return n>=XEL_FCS_SIZE?(int)(n-XEL_FCS_SIZE):-1;
}
static void receive_task(void *unused) {
    (void)unused;static uint8_t discard[1536];
    for(;;){
        ulTaskNotifyTake(pdTRUE,pdMS_TO_TICKS(100));
        for(;;){
            NetworkBufferDescriptor_t *b=pxGetNetworkBufferWithDescriptor(1536,0);
            int n=bounded_receive(b?b->pucEthernetBuffer:discard);
            if(!n){if(b)vReleaseNetworkBufferAndDescriptor(b);break;}
            if(n<0){if(b)vReleaseNetworkBufferAndDescriptor(b);continue;}
            if(!b)continue;
            b->xDataLength=(size_t)n;b->pxInterface=iface;
            b->pxEndPoint=FreeRTOS_MatchingEndpoint(iface,b->pucEthernetBuffer);
            IPStackEvent_t event={eNetworkRxEvent,b};
            if(n<14 || n>ipconfigNETWORK_MTU+14 || !b->pxEndPoint ||
               xSendEventStructToIPTask(&event,0)!=pdPASS)vReleaseNetworkBufferAndDescriptor(b);
        }
    }
}
static BaseType_t link_status(NetworkInterface_t *unused) {
    (void)unused;uint16_t status;
    /* Some board revisions strap the PHY without a working MDC connection.
     * Allow network traffic in that case; telemetry reports link as unknown. */
    if(phy<0)return pdTRUE;
    if(XEmacLite_PhyRead(&mac,(uint32_t)phy,1,&status)!=XST_SUCCESS)return pdFALSE;
    if(XEmacLite_PhyRead(&mac,(uint32_t)phy,1,&status)!=XST_SUCCESS)return pdFALSE;
    return (status&4)?pdTRUE:pdFALSE;
}
int ethernet_phy_known(void){return phy>=0;}
void ethernet_retry_dhcp(void){if(iface)FreeRTOS_NetworkDown(iface);}
static BaseType_t output(NetworkInterface_t *unused,NetworkBufferDescriptor_t *b,BaseType_t release) {
    (void)unused;BaseType_t ok=pdFAIL;TickType_t start=xTaskGetTickCount();
    do {
        if(XEmacLite_TxBufferAvailable(&mac)){
            if(b->xDataLength<=1514 && XEmacLite_Send(&mac,b->pucEthernetBuffer,(unsigned)b->xDataLength)==XST_SUCCESS)ok=pdPASS;
            break;
        }
        vTaskDelay(1);
    }while(xTaskGetTickCount()-start<pdMS_TO_TICKS(20));
    if(release)vReleaseNetworkBufferAndDescriptor(b);
    return ok;
}
static BaseType_t initialise(NetworkInterface_t *interface) {
    if(rx_task)return link_status(interface);
    iface=interface;
    XEmacLite_Config *cfg=XEmacLite_LookupConfig(XPAR_XEMACLITE_0_BASEADDR);
    if(!cfg||XEmacLite_CfgInitialize(&mac,cfg,cfg->BaseAddress)!=XST_SUCCESS)return pdFAIL;
    XEmacLite_SetMacAddress(&mac,active_mac);XEmacLite_FlushReceive(&mac);
    for(unsigned p=0;p<32;p++){
        uint16_t id;
        if(XEmacLite_PhyRead(&mac,p,2,&id)==XST_SUCCESS&&id&&id!=0xffff){phy=(int)p;break;}
    }
    xil_printf("PHY MDIO address %d (-1 = strapped/unknown)\r\n",phy);
    if(phy>=0){
        uint16_t control,gigabit;
        /* EthernetLite is 10/100 full duplex; do not negotiate gigabit or half duplex. */
        if(XEmacLite_PhyRead(&mac,(unsigned)phy,9,&gigabit)==XST_SUCCESS)
            XEmacLite_PhyWrite(&mac,(unsigned)phy,9,gigabit&~0x300U);
        XEmacLite_PhyWrite(&mac,(unsigned)phy,4,0x0141);
        if(XEmacLite_PhyRead(&mac,(unsigned)phy,0,&control)==XST_SUCCESS)
            XEmacLite_PhyWrite(&mac,(unsigned)phy,0,(control&~0xcc00U)|0x1200U);
    }
    if(xTaskCreate(receive_task,"ether_rx",1024,0,5,&rx_task)!=pdPASS)return pdFAIL;
    XEmacLite_SetRecvHandler(&mac,0,receive_irq);XEmacLite_SetSendHandler(&mac,0,sent_irq);
    configASSERT(xPortInstallInterruptHandler(XPAR_XEMACLITE_0_INTERRUPTS,(XInterruptHandler)XEmacLite_InterruptHandler,&mac)==pdPASS);
    vPortEnableInterrupt(XPAR_XEMACLITE_0_INTERRUPTS);XEmacLite_EnableInterrupts(&mac);
    return link_status(interface);
}
NetworkInterface_t *pxFillInterfaceDescriptor(BaseType_t index,NetworkInterface_t *interface) {
    (void)index;memset(interface,0,sizeof(*interface));interface->pcName="eth0";
    interface->pfInitialise=initialise;interface->pfOutput=output;interface->pfGetPhyLinkStatus=link_status;
    return FreeRTOS_AddNetworkInterface(interface);
}
