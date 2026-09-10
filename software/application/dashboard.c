/* SPDX-License-Identifier: Apache-2.0 */
/* Trusted-LAN protocol: non-secret configuration readback is explicit TCP only.
 * Unicast share events contain mining.submit (worker/job/nonce), never passwords. */
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
#include "versions.h"
#if XPAR_XSYSMON_0_IP_TYPE != 1
#error This temperature conversion requires UltraScale System Management IP
#endif
static QueueHandle_t events;
static uint32_t event_seq;
static miner_stats stats;
void telemetry_power(const ina700_sample samples[2]){
    taskENTER_CRITICAL();memcpy(stats.power,samples,sizeof(stats.power));taskEXIT_CRITICAL();
}
extern int ethernet_phy_known(void);
void telemetry_detail(const miner_event *event){
    taskENTER_CRITICAL();
    if(!strcmp(event->name,"solution_submitted"))stats.submitted++;
    if(!strcmp(event->name,"solution_accepted"))stats.accepted++;
    if(!strcmp(event->name,"solution_rejected"))stats.rejected++;
    if(!strcmp(event->name,"hardware_solution_invalid"))stats.invalid++;
    if(!strcmp(event->name,"pool_connected"))stats.connected=1;
    if(!strcmp(event->name,"pool_authorized"))stats.authorized=1;
    if(!strcmp(event->name,"pool_disconnected")){
        stats.connected=stats.authorized=stats.mining=0;stats.job_id[0]=0;
    }
    taskEXIT_CRITICAL();
    if(events&&xQueueSend(events,event,0)!=pdPASS){
        taskENTER_CRITICAL();stats.dropped++;taskEXIT_CRITICAL();
    }
}
void telemetry_event(const char *event){
    miner_event item={0};snprintf(item.name,sizeof(item.name),"%s",event);
    taskENTER_CRITICAL();
    item.job_number=stats.jobs;memcpy(item.job_id,stats.job_id,sizeof(item.job_id));
    taskEXIT_CRITICAL();
    telemetry_detail(&item);
}
uint32_t telemetry_job(const char *id){
    taskENTER_CRITICAL();
    stats.jobs++;snprintf(stats.job_id,sizeof(stats.job_id),"%s",id);
    uint32_t number=stats.jobs;taskEXIT_CRITICAL();
    telemetry_event("mining_job_received");return number;
}
void telemetry_mining(int active){
    taskENTER_CRITICAL();stats.mining=active;taskEXIT_CRITICAL();
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
    char request[80],message[MINER_TELEMETRY_MAX];miner_event event;uint32_t seq=0;TickType_t last_status=0;
    TickType_t sampled=xTaskGetTickCount();
    int counter_present=Xil_In32(0x44a300a8U)==0x48534831U;
    uint32_t previous=counter_present?Xil_In32(0x44a300acU):0;
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
        if(counter_present && now-sampled>=pdMS_TO_TICKS(1000)){
            uint32_t count=Xil_In32(0x44a300acU),delta=count-previous;
            taskENTER_CRITICAL();
            stats.hashrate_hps=miner_hashrate(previous,count,now-sampled,configTICK_RATE_HZ);
            stats.hashes_total+=delta;stats.sample_ms=(now-sampled)*portTICK_PERIOD_MS;
            stats.hashrate_valid=1;taskEXIT_CRITICAL();
            previous=count;sampled=now;
        }
        memset(&event,0,sizeof(event));
        int pending=xQueueReceive(events,&event,0)==pdPASS;
        if(!pending)strcpy(event.name,"status");else event_seq++;
        if(!discovery&&!pending&&now-last_status<pdMS_TO_TICKS(1000))continue;
        last_status=now;
        /* UltraScale SYSMON temperature is at AXI offset 0x400, not the
         * 7-series XADC offset selected by legacy SDT header defaults. */
        uint32_t raw=Xil_In32(XPAR_XSYSMON_0_BASEADDR+0x400)&0xffffU;
        int centi=(int)(((uint64_t)raw*5013743U)/6553600U)-27367;
        miner_stats snapshot;
        taskENTER_CRITICAL();snapshot=stats;taskEXIT_CRITICAL();
        int count=miner_telemetry_json(message,sizeof(message),&snapshot,&event,++seq,event_seq,
            now*portTICK_PERIOD_MS,centi,active_mac,network_up,ethernet_phy_known());
        if(count<=0||(size_t)count>=sizeof(message))continue;
        /* FreeRTOS UDP cannot send more than MTU - IPv4/UDP headers. Keep
         * full share submissions by splitting oversized packets into a
         * complete status and a partial event, never truncating a solution. */
        int split=count>1472;
        for(int part=0;part<=split;part++){
            if(split){
                static const miner_event status_event={.name="status"};
                if(!part)count=miner_telemetry_json(message,sizeof(message),&snapshot,&status_event,++seq,event_seq,
                    now*portTICK_PERIOD_MS,centi,active_mac,network_up,ethernet_phy_known());
                else count=miner_event_json(message,sizeof(message),&event,++seq,event_seq,
                    now*portTICK_PERIOD_MS,centi,active_mac);
            }
            if(count<=0||count>1472)continue;
            if(discovery)FreeRTOS_sendto(s,message,count,0,&peer,sizeof(peer));
            for(int i=0;i<4;i++)if(clients[i].used){
                if(now-clients[i].last>pdMS_TO_TICKS(5000)){clients[i].used=0;continue;}
                FreeRTOS_sendto(s,message,count,0,&clients[i].peer,sizeof(clients[i].peer));
            }
        }
    }
}
static const char *configure(const char *line,size_t n){
    miner_settings next;
    xSemaphoreTake(settings_lock,portMAX_DELAY);
    const char *error=miner_config_parse(line,n,&settings,&next);
    int rc=error?-1:settings_save(&next,eeprom_read,eeprom_write);
    if(!rc){settings=next;settings_generation++;}
    xSemaphoreGive(settings_lock);
    if(error)return error;
    if(rc)return "EEPROM write or verification failed";
    telemetry_event("settings_saved");return 0;
}
static int config_reply(const char *line,size_t used,int complete,char *out,size_t cap){
    const char *error="incomplete or oversized request";char command[24];
    if(complete){
        if(JSON_Validate(line,used)!=JSONSuccess||json_string(line,used,"command",command,sizeof(command)))
            error="invalid JSON request";
        else if(!strcmp(command,"get_settings")){
            miner_settings saved;
            xSemaphoreTake(settings_lock,portMAX_DELAY);
            int stored=settings_load(&saved,eeprom_read);
            xSemaphoreGive(settings_lock);
            if(stored<0)error="EEPROM read failed";
            else return miner_config_json(out,cap,&saved,stored,active_mac);
        }else error=configure(line,used);
    }
    return snprintf(out,cap,error?"{\"ok\":false,\"error\":\"%s\"}\n":
        "{\"ok\":true,\"message\":\"Saved; pool reconnects, MAC applies after reboot\"}\n",error?error:"");
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
        char reply[1024];int n=config_reply(line,used,complete,reply,sizeof(reply));
        if(n<=0||(size_t)n>=sizeof(reply)){FreeRTOS_closesocket(client);continue;}
        size_t sent=0;while(sent<(size_t)n){BaseType_t k=FreeRTOS_send(client,reply+sent,n-sent,0);if(k<=0)break;sent+=(size_t)k;}
        FreeRTOS_shutdown(client,FREERTOS_SHUT_RDWR);FreeRTOS_closesocket(client);
    }
}
void dashboard_start(void){
    stats.engines=Xil_In32(MINER_ENGINES_REG);
    stats.hw_version=Xil_In32(MINER_HW_VERSION_REG);
    stats.bootloader_version=Xil_In32(MINER_BOOT_VERSION_REG);
    events=xQueueCreate(32,sizeof(miner_event));configASSERT(events);
    configASSERT(xTaskCreate(broadcast_task,"telemetry",3072,0,2,0)==pdPASS);
    configASSERT(xTaskCreate(config_task,"config",3072,0,2,0)==pdPASS);
    power_start();
}
