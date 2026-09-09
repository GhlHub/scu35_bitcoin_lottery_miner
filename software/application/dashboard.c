/* SPDX-License-Identifier: Apache-2.0 */
/* Trusted-LAN protocol; no credentials are broadcast or included in telemetry. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "app.h"
#include "task.h"
#include "queue.h"
#include "FreeRTOS_IP.h"
#include "FreeRTOS_Sockets.h"
#include "json_helpers.h"
#include "xparameters.h"
#include "xil_io.h"
#if XPAR_XSYSMON_0_IP_TYPE != 1
#error This temperature conversion requires UltraScale System Management IP
#endif
static QueueHandle_t events;
static uint32_t event_seq;
extern int ethernet_phy_known(void);
void telemetry_event(const char *event){
    char item[64];snprintf(item,sizeof(item),"%s",event);
    if(events)xQueueSend(events,item,0);
}
static Socket_t bound_socket(BaseType_t type,uint16_t port){
    Socket_t s=FreeRTOS_socket(FREERTOS_AF_INET,type,type==FREERTOS_SOCK_DGRAM?FREERTOS_IPPROTO_UDP:FREERTOS_IPPROTO_TCP);
    if(s==FREERTOS_INVALID_SOCKET)return s;
    struct freertos_sockaddr a={0};a.sin_family=FREERTOS_AF_INET;a.sin_port=FreeRTOS_htons(port);
    if(FreeRTOS_bind(s,&a,sizeof(a))){FreeRTOS_closesocket(s);return FREERTOS_INVALID_SOCKET;}
    TickType_t timeout=pdMS_TO_TICKS(100);FreeRTOS_setsockopt(s,0,FREERTOS_SO_RCVTIMEO,&timeout,sizeof(timeout));
    return s;
}
static void broadcast_task(void *unused){
    (void)unused;
    struct {struct freertos_sockaddr peer;TickType_t last;int used;} clients[4]={0};
    Socket_t s=bound_socket(FREERTOS_SOCK_DGRAM,4028);configASSERT(s!=FREERTOS_INVALID_SOCKET);
    char request[80],message[512],event[64]="status";uint32_t seq=0;TickType_t last_status=0;
    for(;;){
        struct freertos_sockaddr peer; socklen_t plen=sizeof(peer);
        BaseType_t n=FreeRTOS_recvfrom(s,request,sizeof(request)-1,0,&peer,&plen);
        TickType_t now=xTaskGetTickCount();int discovery=0;
        if(n>0){
            request[n]=0;
            discovery=!strcmp(request,"SCU35_DISCOVER/1");
            if(!strcmp(request,"SCU35_SUBSCRIBE/1")){
                int slot=-1;
                for(int i=0;i<4;i++){
                    if(clients[i].used&&clients[i].peer.sin_address.ulIP_IPv4==peer.sin_address.ulIP_IPv4&&clients[i].peer.sin_port==peer.sin_port){slot=i;break;}
                    if(!clients[i].used||now-clients[i].last>pdMS_TO_TICKS(5000))slot=i;
                }
                if(slot>=0){clients[slot].peer=peer;clients[slot].last=now;clients[slot].used=1;}
            }
        }
        int pending=xQueueReceive(events,event,0)==pdPASS;
        if(!pending)strcpy(event,"status");else event_seq++;
        if(!discovery&&!pending&&now-last_status<pdMS_TO_TICKS(1000))continue;
        last_status=now;
        /* UltraScale SYSMON temperature is at AXI offset 0x400, not the
         * 7-series XADC offset selected by legacy SDT header defaults. */
        uint32_t raw=Xil_In32(XPAR_XSYSMON_0_BASEADDR+0x400)&0xffffU;
        int centi=(int)(((uint64_t)raw*5013743U)/6553600U)-27367;
        int count=snprintf(message,sizeof(message),
            "{\"protocol\":\"SCU35/1\",\"seq\":%lu,\"event_seq\":%lu,\"event\":\"%s\","
            "\"mac\":\"%02x:%02x:%02x:%02x:%02x:%02x\",\"uptime_ms\":%lu,"
            "\"temp_centi\":%d,\"cpu_mhz\":50,\"engines\":2,\"network_up\":%s,"
            "\"phy_known\":%s,\"reboot_supported\":false,\"config_port\":4029}",
            (unsigned long)++seq,(unsigned long)event_seq,event,
            active_mac[0],active_mac[1],active_mac[2],active_mac[3],active_mac[4],active_mac[5],
            (unsigned long)(now*portTICK_PERIOD_MS),centi,network_up?"true":"false",ethernet_phy_known()?"true":"false");
        if(count<=0||(size_t)count>=sizeof(message))continue;
        if(discovery)FreeRTOS_sendto(s,message,count,0,&peer,sizeof(peer));
        for(int i=0;i<4;i++)if(clients[i].used){
            if(now-clients[i].last>pdMS_TO_TICKS(5000)){clients[i].used=0;continue;}
            FreeRTOS_sendto(s,message,count,0,&clients[i].peer,sizeof(clients[i].peer));
        }
    }
}
static int parse_mac(const char *s,uint8_t mac[6]){
    if(strlen(s)!=17)return -1;
    for(unsigned i=0;i<6;i++){
        unsigned value=0;
        for(unsigned j=0;j<2;j++){
            char c=s[3*i+j];int v=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:c>='A'&&c<='F'?c-'A'+10:-1;
            if(v<0)return -1;
            value=value*16+(unsigned)v;
        }
        mac[i]=(uint8_t)value;if(i<5&&s[3*i+2]!=':')return -1;
    }
    return 0;
}
static const char *configure(const char *line,size_t n){
    char command[16],macstr[18];uint32_t port;miner_settings next={0};
    if(JSON_Validate(line,n)!=JSONSuccess||json_string(line,n,"command",command,sizeof(command)))return "invalid JSON request";
    if(strcmp(command,"configure"))return "unsupported command";
    if(json_string(line,n,"mac",macstr,sizeof(macstr))||parse_mac(macstr,next.mac)||
       json_string(line,n,"host",next.host,sizeof(next.host))||json_string(line,n,"worker",next.worker,sizeof(next.worker))||
       json_string(line,n,"password",next.password,sizeof(next.password))||json_u32(line,n,"port",&port)||port>65535)return "invalid fields";
    next.port=(uint16_t)port;if(!settings_valid(&next))return "invalid settings";
    xSemaphoreTake(settings_lock,portMAX_DELAY);
    int rc=settings_save(&next,eeprom_read,eeprom_write);
    if(!rc){settings=next;settings_generation++;}
    xSemaphoreGive(settings_lock);
    if(rc)return "EEPROM write or verification failed";
    telemetry_event("settings_saved");return 0;
}
static void config_task(void *unused){
    (void)unused;Socket_t server=bound_socket(FREERTOS_SOCK_STREAM,4029);configASSERT(server!=FREERTOS_INVALID_SOCKET);
    configASSERT(FreeRTOS_listen(server,2)==0);
    for(;;){
        Socket_t client=FreeRTOS_accept(server,0,0);
        /* accept returns NULL on timeout, INVALID_SOCKET on invalid listener. */
        if(client==NULL||client==FREERTOS_INVALID_SOCKET){vTaskDelay(1);continue;}
        TickType_t timeout=pdMS_TO_TICKS(100);FreeRTOS_setsockopt(client,0,FREERTOS_SO_RCVTIMEO,&timeout,sizeof(timeout));
        timeout=pdMS_TO_TICKS(500);FreeRTOS_setsockopt(client,0,FREERTOS_SO_SNDTIMEO,&timeout,sizeof(timeout));
        char line[1024];size_t used=0;int complete=0;TickType_t start=xTaskGetTickCount();
        while(used<sizeof(line)&&xTaskGetTickCount()-start<pdMS_TO_TICKS(3000)){
            char c;BaseType_t n=FreeRTOS_recv(client,&c,1,0);
            if(n<0&&n!=-pdFREERTOS_ERRNO_EWOULDBLOCK)break;
            if(n!=1)continue;
            if(c=='\n'){complete=1;break;}
            line[used++]=c;
        }
        const char *error=complete?configure(line,used):"incomplete or oversized request";
        char reply[200];int n=snprintf(reply,sizeof(reply),error?"{\"ok\":false,\"error\":\"%s\"}\n":
            "{\"ok\":true,\"message\":\"Saved; pool reconnects, MAC applies after reboot\"}\n",error?error:"");
        size_t sent=0;while(sent<(size_t)n){BaseType_t k=FreeRTOS_send(client,reply+sent,n-sent,0);if(k<=0)break;sent+=(size_t)k;}
        FreeRTOS_shutdown(client,FREERTOS_SHUT_RDWR);FreeRTOS_closesocket(client);
    }
}
void dashboard_start(void){
    events=xQueueCreate(32,64);configASSERT(events);
    configASSERT(xTaskCreate(broadcast_task,"telemetry",2048,0,2,0)==pdPASS);
    configASSERT(xTaskCreate(config_task,"config",3072,0,2,0)==pdPASS);
}
