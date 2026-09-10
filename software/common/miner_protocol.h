/* SPDX-License-Identifier: Apache-2.0 */
#ifndef MINER_PROTOCOL_H
#define MINER_PROTOCOL_H
#include "settings.h"
#include "ina700.h"
#define MINER_TELEMETRY_MAX 3072
typedef struct {
    char name[64], job_id[128], submission[640], hash[65];
    uint32_t job_number;
} miner_event;
typedef struct {
    char job_id[128];
    uint32_t jobs, submitted, accepted, rejected, invalid, dropped;
    uint32_t hashrate_hps, sample_ms;
    uint32_t engines, hw_version, bootloader_version;
    uint64_t hashes_total;
    int connected, authorized, mining, hashrate_valid;
    ina700_sample power[2];
} miner_stats;
const char *miner_config_parse(const char *,size_t,const miner_settings *,miner_settings *);
int miner_config_json(char *,size_t,const miner_settings *,int,const uint8_t *);
int miner_telemetry_json(char *,size_t,const miner_stats *,const miner_event *,
                       uint32_t,uint32_t,uint32_t,int,const uint8_t *,int,int);
uint32_t miner_hashrate(uint32_t previous,uint32_t current,uint32_t ticks,uint32_t tick_hz);
int miner_event_json(char *,size_t,const miner_event *,uint32_t,uint32_t,uint32_t,int,const uint8_t *);
#endif
