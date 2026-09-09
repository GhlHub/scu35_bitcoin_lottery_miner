/* SPDX-License-Identifier: Apache-2.0 */
#include <string.h>
#include "app.h"
#include "task.h"
#include "FreeRTOS_IP.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xil_io.h"
miner_settings settings;
uint8_t active_mac[6];
SemaphoreHandle_t settings_lock;
volatile unsigned settings_generation;
volatile BaseType_t network_up;
static uint32_t random_state=0x712ae951;
BaseType_t xApplicationGetRandomNumber(uint32_t *value) {
    /* DHCP/sequence randomization, not cryptographic randomness. */
    taskENTER_CRITICAL();
    random_state^=random_state<<13;random_state^=random_state>>17;random_state^=random_state<<5;
    *value=random_state;taskEXIT_CRITICAL();return pdTRUE;
}
uint32_t ulApplicationGetNextSequenceNumber(uint32_t src,uint16_t sp,uint32_t dst,uint16_t dp){
    uint32_t n;xApplicationGetRandomNumber(&n);return n^src^dst^((uint32_t)sp<<16)^dp;
}
void vApplicationIPNetworkEventHook(eIPCallbackEvent_t event) {
    network_up=event==eNetworkUp&&FreeRTOS_GetIPAddress()!=0;
    xil_printf("Network %s\r\n",network_up?"up":"down");
}
static void network_watch(void *unused){
    (void)unused;
    extern void ethernet_retry_dhcp(void);
    for(;;){
        vTaskDelay(pdMS_TO_TICKS(10000));
        /* Never settle permanently on the all-zero fallback after DHCP
         * discovery exhaustion. Retry when the stack has completed that cycle. */
        if(FreeRTOS_IsNetworkUp()&&!FreeRTOS_GetIPAddress())ethernet_retry_dhcp();
    }
}
int main(void){
    console_init();Xil_ICacheEnable();Xil_DCacheEnable();
    xil_printf("SCU35 Bitcoin miner / FreeRTOS 202604-LTS / CPU 50MHz\r\n");
    int stored=settings_load(&settings,eeprom_read);
    memcpy(active_mac,settings.mac,6);
    random_state^=Xil_In32(0x41c00008U);
    for(unsigned i=0;i<6;i++)random_state=random_state*33+active_mac[i];
    xil_printf("EEPROM settings %d; MAC %02x:%02x:%02x:%02x:%02x:%02x\r\n",stored,
        active_mac[0],active_mac[1],active_mac[2],active_mac[3],active_mac[4],active_mac[5]);
    settings_lock=xSemaphoreCreateMutex();configASSERT(settings_lock);
    static const uint8_t ip[4]={0},mask[4]={255,255,255,0},gateway[4]={0},dns[4]={0};
    configASSERT(FreeRTOS_IPInit(ip,mask,gateway,dns,active_mac)==pdPASS);
    dashboard_start();stratum_start();
    configASSERT(xTaskCreate(network_watch,"network_watch",512,0,1,0)==pdPASS);
    vTaskStartScheduler();
    for(;;){}
}
