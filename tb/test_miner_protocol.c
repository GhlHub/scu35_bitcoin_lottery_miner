/* SPDX-License-Identifier: Apache-2.0 */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "miner_protocol.h"
#include "json_helpers.h"
int main(void){
    miner_settings saved,next;settings_defaults(&saved);
    strcpy(saved.host,"pool.example");strcpy(saved.worker,"wallet.worker");strcpy(saved.password,"do-not-disclose");
    const char *keep="{\"command\":\"configure\",\"mac\":\"02:00:00:11:22:34\",\"host\":\"new.example\",\"port\":3334,\"worker\":\"wallet.new\"}";
    assert(!miner_config_parse(keep,strlen(keep),&saved,&next));
    assert(!strcmp(next.password,saved.password)&&next.port==3334&&next.mac[5]==0x34);
    char line[1024];snprintf(line,sizeof(line),"%.*s,\"password\":\"\"}",(int)strlen(keep)-1,keep);
    assert(!miner_config_parse(line,strlen(line),&saved,&next)&&!next.password[0]);
    snprintf(line,sizeof(line),"%.*s,\"password\":false}",(int)strlen(keep)-1,keep);
    assert(miner_config_parse(line,strlen(line),&saved,&next));
    char out[MINER_TELEMETRY_MAX];int n=miner_config_json(out,sizeof(out),&saved,1,next.mac);
    assert(n>0&&(size_t)n<sizeof(out)&&JSON_Validate(out,n)==JSONSuccess);
    assert(!strstr(out,"do-not-disclose")&&!strstr(out,"\"password\":"));
    assert(strstr(out,"\"stored\":true")&&strstr(out,"wallet.worker"));
    settings_defaults(&next);n=miner_config_json(out,sizeof(out),&next,0,saved.mac);
    assert(n>0&&strstr(out,"\"stored\":false"));
    assert(miner_hashrate(100,759100,100,100)==759000);
    assert(miner_hashrate(0xfffffff0U,16,100,100)==32);
    assert(miner_hashrate(10,10,100,100)==0);
    assert(miner_hashrate(10,20,0,100)==0);
    miner_stats s={0};miner_event e={0};
    s.engines=3;s.hw_version=0x01000000;s.bootloader_version=0x02030004;
    memset(s.job_id,'a',127);memset(e.job_id,'b',127);memset(e.name,'c',63);memset(e.hash,'d',64);
    s.jobs=20;e.job_number=19;s.hashrate_valid=1;s.hashrate_hps=759000;s.hashes_total=5000000000ULL;s.sample_ms=1000;
    strcpy(e.submission,"{\"id\":4,\"method\":\"mining.submit\",\"params\":[\"wallet.worker\",\"previous-job\",\"0001\",\"12345678\",\"7c2bac1d\"]}");
    n=miner_telemetry_json(out,sizeof(out),&s,&e,1,1,1000,3700,saved.mac,1,1);
    assert(n>0&&(size_t)n<sizeof(out)&&JSON_Validate(out,n)==JSONSuccess);
    char field[128];assert(!json_string(out,n,"details.submission.params[4]",field,sizeof(field))&&!strcmp(field,"7c2bac1d"));
    uint32_t number;assert(!json_u32(out,n,"details.job_number",&number)&&number==19);
    assert(!json_u32(out,n,"engines",&number)&&number==3);
    assert(!json_string(out,n,"hw_version",field,sizeof(field))&&!strcmp(field,"1.0.0"));
    assert(!json_string(out,n,"bootloader_version",field,sizeof(field))&&!strcmp(field,"2.3.4"));
    assert(!json_string(out,n,"application_version",field,sizeof(field))&&!strcmp(field,"1.1.0"));
    assert(!json_u32(out,n,"job_number",&number)&&number==20);
    assert(strstr(out,"5000000000")&&!strstr(out,"do-not-disclose"));
    assert(miner_telemetry_json(out,10,&s,&e,1,1,1000,3700,saved.mac,1,1)>=10);
    s.hashrate_valid=0;e.submission[0]=0;s.hw_version=s.bootloader_version=0;
    n=miner_telemetry_json(out,sizeof(out),&s,&e,1,1,0,0,saved.mac,0,0);
    assert(JSON_Validate(out,n)==JSONSuccess&&strstr(out,"\"hashrate_hps\":null")&&strstr(out,"\"submission\":null"));
    assert(strstr(out,"\"hw_version\":null")&&strstr(out,"\"bootloader_version\":null"));
    assert(strstr(out,"\"power_uw\":null"));
    s.power[0]=(ina700_sample){.valid=1,.voltage_uv=5000000,.current_ua=1200000,
        .power_uw=6000000,.temp_milli_c=30000,.sampled_ms=0xfffffff0U,.errors=2};
    n=miner_telemetry_json(out,sizeof(out),&s,&e,1,1,16,0,saved.mac,1,1);
    assert(JSON_Validate(out,n)==JSONSuccess);
    assert(!json_u32(out,n,"power.internal_5v.power_uw",&number)&&number==6000000);
    assert(!json_u32(out,n,"power.internal_5v.age_ms",&number)&&number==32);
    n=miner_telemetry_json(out,sizeof(out),&s,&e,1,1,4000,0,saved.mac,1,1);
    assert(strstr(out,"\"power_uw\":null")&&!strstr(out,"6000000"));
    /* Maximum-size event must still fit the UDP/dashboard limit. */
    memset(e.submission,' ',sizeof(e.submission)-1);
    e.submission[0]='{';e.submission[1]='}';e.submission[sizeof(e.submission)-1]=0;
    s.jobs=s.submitted=s.accepted=s.rejected=s.invalid=s.dropped=UINT32_MAX;
    s.hashrate_valid=1;s.hashrate_hps=s.sample_ms=UINT32_MAX;s.hashes_total=UINT64_MAX;
    s.engines=3;s.hw_version=s.bootloader_version=UINT32_MAX;e.job_number=UINT32_MAX;
    for(unsigned k=0;k<2;k++)s.power[k]=(ina700_sample){.valid=1,.voltage_uv=UINT32_MAX,
        .current_ua=INT32_MIN,.power_uw=UINT32_MAX,.temp_milli_c=INT32_MIN,
        .sampled_ms=UINT32_MAX-3000,.errors=UINT32_MAX};
    n=miner_telemetry_json(out,sizeof(out),&s,&e,UINT32_MAX,UINT32_MAX,UINT32_MAX,99999,saved.mac,1,1);
    assert(n>0&&(size_t)n<sizeof(out)&&JSON_Validate(out,n)==JSONSuccess);
    n=miner_event_json(out,sizeof(out),&e,UINT32_MAX,UINT32_MAX,UINT32_MAX,99999,saved.mac);
    assert(n>0&&n<=1472&&JSON_Validate(out,n)==JSONSuccess);
    assert(strstr(out,"\"partial\":true"));
    miner_event status={.name="status"};
    n=miner_telemetry_json(out,sizeof(out),&s,&status,UINT32_MAX,UINT32_MAX,UINT32_MAX,99999,saved.mac,1,1);
    assert(n>0&&n<=1472&&JSON_Validate(out,n)==JSONSuccess);
    puts("PASS: EEPROM redaction, hashrate, power validity/staleness, share JSON and MTU-bounded split packets");
}
