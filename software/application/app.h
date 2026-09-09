/* SPDX-License-Identifier: Apache-2.0 */
#ifndef APP_H
#define APP_H
#include "settings.h"
#include "FreeRTOS.h"
#include "semphr.h"
extern miner_settings settings;
extern uint8_t active_mac[6];
extern SemaphoreHandle_t settings_lock;
extern volatile unsigned settings_generation;
extern volatile BaseType_t network_up;
int eeprom_read(uint16_t,void *,size_t);
int eeprom_write(uint16_t,const void *,size_t);
void console_init(void);
void dashboard_start(void);
void stratum_start(void);
void telemetry_event(const char *event);
#endif
