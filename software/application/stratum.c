/* SPDX-License-Identifier: Apache-2.0 */
/* One task owns both the Stratum session and mining registers. New work cannot
 * race result metadata; stop, drain, clear precedes every replacement job. */
#include <stdio.h>
#include <string.h>
#include "app.h"
#include "task.h"
#include "FreeRTOS_IP.h"
#include "FreeRTOS_Sockets.h"
#include "json_helpers.h"
#include "bitcoin.h"
#include "sha256_sw.h"
#include "xil_io.h"
#define MINER 0x44a30000U
#define LINE_MAX 24000
#define RANGE 0x01000000U
typedef struct {
    char id[128],time[9];
    uint8_t prev[32],version[4],bits[4],coin1[4096],coin2[4096],branches[32][32];
    size_t n1,n2,nb;
    uint32_t target[8];
} pool_job;
static pool_job job;
static uint8_t extra1[32],extra2[16],header[80];
static size_t extra1_size,extra2_size;
static uint32_t pending_target[8],range_start,next_id;
static struct {uint32_t id;TickType_t sent;} pending[8];
static char line[LINE_MAX],extra2_hex[33];
static int subscribed,authorized,have_job,running,extra_exhausted;
static Socket_t connection;
static miner_settings session;
static uint32_t reg_read(unsigned a){return Xil_In32(MINER+a);}
static void reg_write(unsigned a,uint32_t v){Xil_Out32(MINER+a,v);}
static void stop(void){
    reg_write(0xa0,1); /* poll result FIFO; no interrupt storm */
    reg_write(0,2);vTaskDelay(1); /* let an in-flight compression finish */
    reg_write(0,4);reg_write(0x98,3);running=0;
}
static int send_line(const char *s){
    size_t n=strlen(s),sent=0;
    while(sent<n){BaseType_t k=FreeRTOS_send(connection,s+sent,n-sent,0);if(k<=0)return -1;sent+=(size_t)k;}
    return 0;
}
static int json_hex(const char *s,size_t n,const char *query,uint8_t *out,size_t cap){
    const char *v;size_t len;JSONTypes_t type;
    if(JSON_SearchConst(s,n,query,strlen(query),&v,&len,&type)!=JSONSuccess||type!=JSONString)return -1;
    return hex_decode(v,len,out,cap);
}
static void start_range(void){
    reg_write(0,4);reg_write(0x80,range_start);reg_write(0x84,RANGE);reg_write(0,1);running=1;
}
static int build_header(void){
    if(extra_exhausted)return -1;
    uint32_t mid[8],tail[4];
    hex_encode(extra2,extra2_size,extra2_hex);
    /* Stratum V1 prevhash is a sequence of big-endian 32-bit words; the
     * serialized Bitcoin header swaps bytes in each word, not all 32 bytes. */
    uint8_t time[4];
    if(hex_decode(job.time,8,time,4)!=4)return -1;
    bitcoin_build_header(job.version,job.prev,job.bits,time,job.coin1,job.n1,
        extra1,extra1_size,extra2,extra2_size,job.coin2,job.n2,job.branches,job.nb,header);
    bitcoin_header_midstate(header,mid);bitcoin_header_tail_words(header,tail);
    for(unsigned i=0;i<8;i++){reg_write(0x20+i*4,mid[i]);reg_write(0x60+i*4,job.target[i]);}
    for(unsigned i=0;i<4;i++)reg_write(0x40+i*4,tail[i]);
    /* Allocate a fresh extranonce for every header, even repeated job IDs. */
    size_t i=extra2_size;while(i){if(++extra2[--i])break;if(i==0)extra_exhausted=1;}
    range_start=0;start_range();return 0;
}
static int notification(const char *s,size_t n){
    char method[64];
    if(json_string(s,n,"method",method,sizeof(method)))return -1;
    if(!strcmp(method,"mining.set_difficulty")){
        const char *v;size_t len;JSONTypes_t type;
        if(JSON_SearchConst(s,n,"params[0]",9,&v,&len,&type)!=JSONSuccess||type!=JSONNumber||bitcoin_target(v,len,pending_target))return -1;
        telemetry_event("difficulty_changed");return 0;
    }
    if(!strcmp(method,"mining.set_extranonce")){
        uint32_t count;int k=json_hex(s,n,"params[0]",extra1,sizeof(extra1));
        if(k<0||json_u32(s,n,"params[1]",&count)||!count||count>16)return -1;
        stop();have_job=0;extra1_size=(size_t)k;extra2_size=count;memset(extra2,0,sizeof(extra2));extra_exhausted=0;
        return 0;
    }
    if(strcmp(method,"mining.notify"))return 0;
    if(!subscribed)return -1;
    stop();have_job=0;
    int n1,n2;
    if(json_string(s,n,"params[0]",job.id,sizeof(job.id))||!job.id[0]||
       json_hex(s,n,"params[1]",job.prev,32)!=32||
       (n1=json_hex(s,n,"params[2]",job.coin1,sizeof(job.coin1)))<0||
       (n2=json_hex(s,n,"params[3]",job.coin2,sizeof(job.coin2)))<0||
       json_hex(s,n,"params[5]",job.version,4)!=4||json_hex(s,n,"params[6]",job.bits,4)!=4||
       json_string(s,n,"params[7]",job.time,sizeof(job.time))||strlen(job.time)!=8)return -1;
    const char *array;size_t length;JSONTypes_t type;
    if(JSON_SearchConst(s,n,"params[4]",9,&array,&length,&type)!=JSONSuccess||type!=JSONArray)return -1;
    if(JSON_SearchConst(s,n,"params[8]",9,&array,&length,&type)!=JSONSuccess||(type!=JSONTrue&&type!=JSONFalse))return -1;
    job.n1=(size_t)n1;job.n2=(size_t)n2;job.nb=0;
    for(unsigned i=0;i<=32;i++){
        char query[32];snprintf(query,sizeof(query),"params[4][%u]",i);
        JSONStatus_t rc=JSON_SearchConst(s,n,query,strlen(query),&array,&length,&type);
        if(rc==JSONNotFound)break;
        if(rc!=JSONSuccess||type!=JSONString||i==32||hex_decode(array,length,job.branches[i],32)!=32)return -1;
        job.nb++;
    }
    memcpy(job.target,pending_target,sizeof(job.target));have_job=1;
    telemetry_event("mining_job_received");return authorized?build_header():0;
}
static int reply(const char *s,size_t n){
    uint32_t id;if(json_u32(s,n,"id",&id))return 0;
    if(id==1){
        if(subscribed)return -1;
        uint32_t count;int k=json_hex(s,n,"result[1]",extra1,sizeof(extra1));
        if(k<0||json_u32(s,n,"result[2]",&count)||!count||count>16)return -1;
        extra1_size=(size_t)k;extra2_size=count;subscribed=1;
        char request[512];snprintf(request,sizeof(request),"{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"%s\",\"%s\"]}\n",session.worker,session.password);
        return send_line(request);
    }
    if(id==2){
        if(!subscribed||authorized)return -1;
        if(!json_true(s,n,"result")){telemetry_event("authorization_failed");return -1;}
        authorized=1;telemetry_event("pool_authorized");
        if(send_line("{\"id\":3,\"method\":\"mining.suggest_difficulty\",\"params\":[0.0001]}\n"))return -1;
        return have_job?build_header():0;
    }
    for(unsigned i=0;i<8;i++)if(id>=4&&pending[i].id==id){
        pending[i].id=0;telemetry_event(json_true(s,n,"result")?"solution_accepted":"solution_rejected");break;
    }
    return 0;
}
static int handle_line(const char *s,size_t n){
    if(JSON_Validate(s,n)!=JSONSuccess)return -1;
    const char *v;size_t len;JSONTypes_t type;
    if(JSON_SearchConst(s,n,"method",6,&v,&len,&type)==JSONSuccess)return notification(s,n);
    return reply(s,n);
}
static int service_results(void){
    if(!running)return 0;
    if(reg_read(4)&8){telemetry_event("result_fifo_overflow");return -1;}
    for(unsigned k=0;k<16&&(reg_read(0x98)&1);k++){
        uint32_t nonce=reg_read(0x90);reg_write(0x98,1);
        /* Verify against the immutable header/target before submitting. */
        uint8_t digest[32];for(unsigned i=0;i<4;i++)header[76+i]=(uint8_t)(nonce>>(24-i*8));
        sha256d(header,80,digest);int valid=1;
        for(unsigned i=0;i<32;i++){
            uint8_t target=(uint8_t)(job.target[i/4]>>(24-8*(i%4)));
            if(digest[31-i]<target)break;
            if(digest[31-i]>target){valid=0;break;}
        }
        if(!valid){telemetry_event("hardware_solution_invalid");return -1;}
        int slot=-1;for(unsigned i=0;i<8;i++)if(!pending[i].id){slot=(int)i;break;}
        if(slot<0){telemetry_event("share_queue_full");return -1;}
        if(next_id<4)return -1;
        uint32_t id=next_id++;
        char request[640];snprintf(request,sizeof(request),
            "{\"id\":%lu,\"method\":\"mining.submit\",\"params\":[\"%s\",\"%s\",\"%s\",\"%s\",\"%08lx\"]}\n",
            (unsigned long)id,session.worker,job.id,extra2_hex,job.time,(unsigned long)bitcoin_swap32(nonce));
        if(send_line(request))return -1;
        pending[slot].id=id;pending[slot].sent=xTaskGetTickCount();telemetry_event("solution_submitted");
    }
    if((reg_read(4)&4)&&!(reg_read(0x98)&1)){
        range_start+=RANGE;
        if(!range_start){stop();return build_header();}
        start_range();
    }
    return 0;
}
static void stratum_task(void *unused){
    (void)unused;stop();
    for(;;){
        unsigned generation;
        xSemaphoreTake(settings_lock,portMAX_DELAY);session=settings;generation=settings_generation;xSemaphoreGive(settings_lock);
        if(!network_up||!session.host[0]||!session.worker[0]){vTaskDelay(pdMS_TO_TICKS(1000));continue;}
        uint32_t address=FreeRTOS_gethostbyname(session.host);
        if(!address){telemetry_event("pool_dns_failed");vTaskDelay(pdMS_TO_TICKS(5000));continue;}
        connection=FreeRTOS_socket(FREERTOS_AF_INET,FREERTOS_SOCK_STREAM,FREERTOS_IPPROTO_TCP);
        if(connection==FREERTOS_INVALID_SOCKET){vTaskDelay(pdMS_TO_TICKS(1000));continue;}
        TickType_t timeout=pdMS_TO_TICKS(3000);FreeRTOS_setsockopt(connection,0,FREERTOS_SO_SNDTIMEO,&timeout,sizeof(timeout));
        /* FreeRTOS_connect uses the receive timeout, so allow WAN handshakes
         * to finish before switching to short mining-result polling waits. */
        FreeRTOS_setsockopt(connection,0,FREERTOS_SO_RCVTIMEO,&timeout,sizeof(timeout));
        struct freertos_sockaddr peer={0};peer.sin_family=FREERTOS_AF_INET;peer.sin_port=FreeRTOS_htons(session.port);peer.sin_address.ulIP_IPv4=address;
        subscribed=authorized=have_job=running=extra_exhausted=0;memset(extra2,0,sizeof(extra2));memset(pending,0,sizeof(pending));next_id=4;
        bitcoin_target("1",1,pending_target);
        if(FreeRTOS_connect(connection,&peer,sizeof(peer))==0&&
           !send_line("{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"SCU35/1\"]}\n")){
            timeout=pdMS_TO_TICKS(100);
            FreeRTOS_setsockopt(connection,0,FREERTOS_SO_RCVTIMEO,&timeout,sizeof(timeout));
            telemetry_event("pool_connected");size_t used=0;TickType_t started=xTaskGetTickCount(),last=started;
            while(network_up&&generation==settings_generation){
                char chunk[512];BaseType_t n=FreeRTOS_recv(connection,chunk,sizeof(chunk),0);int bad=0;
                if(n<0&&n!=-pdFREERTOS_ERRNO_EWOULDBLOCK)break;
                for(BaseType_t i=0;i<n;i++){
                    if(chunk[i]=='\n'){
                        if(used&&handle_line(line,used)){bad=1;break;}
                        used=0;last=xTaskGetTickCount();
                    }else if(used<sizeof(line))line[used++]=chunk[i];else{bad=1;break;}
                }
                TickType_t now=xTaskGetTickCount();
                if(bad||(!authorized&&now-started>pdMS_TO_TICKS(15000))||now-last>pdMS_TO_TICKS(120000)||service_results())break;
                for(unsigned i=0;i<8;i++)if(pending[i].id&&now-pending[i].sent>pdMS_TO_TICKS(30000)){telemetry_event("share_reply_timeout");bad=1;}
                if(bad)break;
            }
        }
        stop();have_job=0;FreeRTOS_closesocket(connection);telemetry_event("pool_disconnected");vTaskDelay(pdMS_TO_TICKS(3000));
    }
}
void stratum_start(void){configASSERT(xTaskCreate(stratum_task,"stratum",4096,0,3,0)==pdPASS);}
