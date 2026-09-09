/* SPDX-License-Identifier: Apache-2.0 */
#ifndef SCU_SREC_H
#define SCU_SREC_H
#include <stddef.h>
#include <stdint.h>
typedef struct { uint32_t address; uint8_t data[252]; size_t size; unsigned type; } srec_record;
int srec_parse(const char *line, size_t size, srec_record *record);
#endif
