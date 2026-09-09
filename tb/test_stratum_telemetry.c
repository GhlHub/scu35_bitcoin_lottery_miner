/* SPDX-License-Identifier: Apache-2.0 */
/* Exercise the actual Stratum result and acknowledgment paths with host I/O. */
#include <assert.h>
#include <stdio.h>
#include "xil_types.h"
#define XIL_IO_H
static int ready;
static inline u32 Xil_In32(UINTPTR a){
    if((a&0xfff)==0x98)return ready;
    if((a&0xfff)==0x90)return 0x1dac2b7c;
    return 0;
}
static inline void Xil_Out32(UINTPTR a,u32 v){if((a&0xfff)==0x98&&(v&1))ready=0;}
#include "../software/application/stratum.c"
static char transmitted[640];static size_t transmitted_size;
static miner_event last_event;
BaseType_t FreeRTOS_send(Socket_t socket,const void *buffer,size_t size,BaseType_t flags){
    (void)socket;(void)flags;
    /* Force partial sends, checking telemetry records the full actual payload. */
    size_t part=size>7?7:size;assert(transmitted_size+part<sizeof(transmitted));
    memcpy(transmitted+transmitted_size,buffer,part);transmitted_size+=part;transmitted[transmitted_size]=0;
    return (BaseType_t)part;
}
TickType_t xTaskGetTickCount(void){return 100;}
void vTaskDelay(TickType_t ticks){(void)ticks;}
void telemetry_mining(int active){(void)active;}
void telemetry_detail(const miner_event *event){last_event=*event;}
void telemetry_event(const char *event){memset(&last_event,0,sizeof(last_event));strcpy(last_event.name,event);}
uint32_t telemetry_job(const char *id){(void)id;return 1;}
int main(void){
    const char *genesis="0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c";
    assert(hex_decode(genesis,strlen(genesis),header,sizeof(header))==80);
    strcpy(session.worker,"wallet.worker");strcpy(session.password,"NEVER-RETURN-THIS");
    strcpy(job.id,"first-job");strcpy(job.time,"495fab29");job.number=7;
    strcpy(extra2_hex,"00000001");for(unsigned i=0;i<8;i++)job.target[i]=UINT32_MAX;
    next_id=4;running=ready=1;
    assert(!service_results());
    assert(!strcmp(last_event.name,"solution_submitted"));
    assert(!strcmp(last_event.submission,transmitted)&&!strstr(transmitted,session.password));
    assert(!strcmp(last_event.hash,"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"));
    char nonce[9];assert(!json_string(transmitted,strlen(transmitted),"params[4]",nonce,sizeof(nonce))&&!strcmp(nonce,"7c2bac1d"));
    /* A late share acknowledgment must retain its old job and full submission. */
    strcpy(job.id,"second-job");job.number=8;
    const char *ack="{\"id\":4,\"result\":true,\"error\":null}";
    assert(!reply(ack,strlen(ack)));
    assert(!strcmp(last_event.name,"solution_accepted")&&last_event.job_number==7&&!strcmp(last_event.job_id,"first-job"));
    assert(!strcmp(last_event.submission,transmitted));
    pending[0].id=5;ack="{\"id\":5,\"result\":false,\"error\":[23,\"low difficulty\",null]}";
    assert(!reply(ack,strlen(ack))&&!strcmp(last_event.name,"solution_rejected"));
    puts("PASS: actual Stratum submission, nonce/hash byte order, partial send, late job correlation");
}
