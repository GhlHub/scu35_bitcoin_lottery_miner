/* SPDX-License-Identifier: Apache-2.0 */
#include "miner_protocol.h"
#include "versions.h"
#include "json_helpers.h"
#include <stdio.h>

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
const char *miner_config_parse(const char *line,size_t n,const miner_settings *current,miner_settings *next){
    char command[24],mac[18];uint32_t port;
    if(JSON_Validate(line,n)!=JSONSuccess||json_string(line,n,"command",command,sizeof(command)))return "invalid JSON request";
    if(strcmp(command,"configure"))return "unsupported command";
    *next=*current;
    if(json_string(line,n,"mac",mac,sizeof(mac))||parse_mac(mac,next->mac)||
       json_string(line,n,"host",next->host,sizeof(next->host))||json_string(line,n,"worker",next->worker,sizeof(next->worker))||
       json_u32(line,n,"port",&port)||port>65535)return "invalid fields";
    const char *v;size_t len;JSONTypes_t type;
    JSONStatus_t found=JSON_SearchConst(line,n,"password",8,&v,&len,&type);
    /* Omission preserves the stored secret; explicit empty string clears it. */
    if(found!=JSONNotFound && (found!=JSONSuccess||json_string(line,n,"password",next->password,sizeof(next->password))))return "invalid password";
    next->port=(uint16_t)port;
    return settings_valid(next)?0:"invalid settings";
}
int miner_config_json(char *out,size_t cap,const miner_settings *s,int stored,const uint8_t *active){
    if(!settings_valid(s))return -1;
    return snprintf(out,cap,
        "{\"ok\":true,\"stored\":%s,\"mac\":\"%02x:%02x:%02x:%02x:%02x:%02x\","
        "\"active_mac\":\"%02x:%02x:%02x:%02x:%02x:%02x\",\"host\":\"%s\",\"port\":%u,"
        "\"worker\":\"%s\",\"password_set\":%s}\n",stored?"true":"false",
        s->mac[0],s->mac[1],s->mac[2],s->mac[3],s->mac[4],s->mac[5],
        active[0],active[1],active[2],active[3],active[4],active[5],s->host,s->port,s->worker,s->password[0]?"true":"false");
}
uint32_t miner_hashrate(uint32_t previous,uint32_t current,uint32_t ticks,uint32_t tick_hz){
    return ticks?(uint32_t)(((uint64_t)(uint32_t)(current-previous)*tick_hz)/ticks):0;
}
static void version_json(char *out,size_t cap,uint32_t version){
    if(!version)snprintf(out,cap,"null");
    else snprintf(out,cap,"\"%u.%u.%u\"",(unsigned)(version>>24),
        (unsigned)((version>>16)&255U),(unsigned)(version&65535U));
}
int miner_event_json(char *out,size_t cap,const miner_event *e,uint32_t seq,uint32_t event_seq,uint32_t uptime,int centi,const uint8_t *mac){
    return snprintf(out,cap,
        "{\"protocol\":\"SCU35/1\",\"partial\":true,\"seq\":%lu,\"event_seq\":%lu,\"event\":\"%s\","
        "\"mac\":\"%02x:%02x:%02x:%02x:%02x:%02x\",\"uptime_ms\":%lu,\"temp_centi\":%d,"
        "\"details\":{\"job_number\":%lu,\"job_id\":\"%s\",\"submission\":%s,\"hash\":\"%s\"}}",
        (unsigned long)seq,(unsigned long)event_seq,e->name,
        mac[0],mac[1],mac[2],mac[3],mac[4],mac[5],(unsigned long)uptime,centi,
        (unsigned long)e->job_number,e->job_id,e->submission[0]?e->submission:"null",e->hash);
}
static void power_json(char *out,size_t cap,const ina700_sample *s,uint32_t now){
    uint32_t age=now-s->sampled_ms;
    if(!s->valid||age>3000U){
        snprintf(out,cap,"{\"valid\":false,\"voltage_uv\":null,\"current_ua\":null,\"power_uw\":null,\"temp_milli_c\":null,\"age_ms\":null,\"errors\":%lu}",(unsigned long)s->errors);
    }else{
        snprintf(out,cap,"{\"valid\":true,\"voltage_uv\":%lu,\"current_ua\":%ld,\"power_uw\":%lu,\"temp_milli_c\":%ld,\"age_ms\":%lu,\"errors\":%lu}",
            (unsigned long)s->voltage_uv,(long)s->current_ua,(unsigned long)s->power_uw,
            (long)s->temp_milli_c,(unsigned long)age,(unsigned long)s->errors);
    }
}
int miner_telemetry_json(char *out,size_t cap,const miner_stats *s,const miner_event *e,
                       uint32_t seq,uint32_t event_seq,uint32_t uptime,int centi,const uint8_t *mac,int network,int phy){
    char rate[24];
    char hw[24],boot[24];
    char power5[256],core[256];
    power_json(power5,sizeof(power5),&s->power[0],uptime);
    power_json(core,sizeof(core),&s->power[1],uptime);
    version_json(hw,sizeof(hw),s->hw_version);
    version_json(boot,sizeof(boot),s->bootloader_version);
    if(s->hashrate_valid)snprintf(rate,sizeof(rate),"%lu",(unsigned long)s->hashrate_hps);else strcpy(rate,"null");
    return snprintf(out,cap,
        "{\"protocol\":\"SCU35/1\",\"seq\":%lu,\"event_seq\":%lu,\"event\":\"%s\","
        "\"mac\":\"%02x:%02x:%02x:%02x:%02x:%02x\",\"uptime_ms\":%lu,\"temp_centi\":%d,"
        "\"cpu_mhz\":50,\"engines\":%lu,\"hw_version\":%s,\"bootloader_version\":%s,\"application_version\":\"" APPLICATION_VERSION "\","
        "\"network_up\":%s,\"phy_known\":%s,\"reboot_supported\":false,\"config_port\":4029,"
        "\"pool_connected\":%s,\"pool_authorized\":%s,\"mining\":%s,"
        "\"job_number\":%lu,\"job_id\":\"%s\",\"shares_submitted\":%lu,\"shares_accepted\":%lu,\"shares_rejected\":%lu,"
        "\"hardware_errors\":%lu,\"events_dropped\":%lu,\"hashrate_hps\":%s,\"hashrate_source\":\"hardware_counter\","
        "\"hashrate_sample_ms\":%lu,\"hashes_total\":%llu,"
        "\"power\":{\"source\":\"INA700\",\"internal_5v\":%s,\"vccint\":%s},"
        "\"details\":{\"job_number\":%lu,\"job_id\":\"%s\",\"submission\":%s,\"hash\":\"%s\"}}",
        (unsigned long)seq,(unsigned long)event_seq,e->name,
        mac[0],mac[1],mac[2],mac[3],mac[4],mac[5],(unsigned long)uptime,centi,
        (unsigned long)s->engines,hw,boot,network?"true":"false",phy?"true":"false",
        s->connected?"true":"false",s->authorized?"true":"false",s->mining?"true":"false",
        (unsigned long)s->jobs,s->job_id,(unsigned long)s->submitted,(unsigned long)s->accepted,(unsigned long)s->rejected,
        (unsigned long)s->invalid,(unsigned long)s->dropped,rate,(unsigned long)s->sample_ms,(unsigned long long)s->hashes_total,
        power5,core,(unsigned long)e->job_number,e->job_id,e->submission[0]?e->submission:"null",e->hash);
}
