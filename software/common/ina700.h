/* SPDX-License-Identifier: Apache-2.0 */
#ifndef INA700_H
#define INA700_H
#include <stdint.h>
#include <stddef.h>
#define INA700_ADC_CONFIG 0xfb6aU /* continuous V/I/T, 1052 us each, 16 averages */
typedef int (*ina700_read_fn)(uint8_t,uint8_t,uint8_t *,size_t);
typedef int (*ina700_write_fn)(uint8_t,uint8_t,uint16_t);
typedef struct {
    int valid;
    uint32_t voltage_uv, power_uw, sampled_ms, errors;
    int32_t current_ua, temp_milli_c;
} ina700_sample;
int ina700_init(uint8_t,ina700_read_fn,ina700_write_fn);
int ina700_sample_read(uint8_t,ina700_read_fn,ina700_sample *);
#endif
