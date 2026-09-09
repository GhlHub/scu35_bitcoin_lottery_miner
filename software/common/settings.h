/* SPDX-License-Identifier: Apache-2.0 */
#ifndef SETTINGS_H
#define SETTINGS_H
#include <stdint.h>
#include <stddef.h>
#define SETTINGS_SLOT_SIZE 512U
#define SETTINGS_SLOT0 0x1000U
#define SETTINGS_SLOT1 0x1200U
typedef struct {
    uint8_t mac[6];
    uint16_t port;
    char host[96], worker[128], password[64];
} miner_settings;
typedef int (*settings_read)(uint16_t, void *, size_t);
typedef int (*settings_write)(uint16_t, const void *, size_t);
void settings_defaults(miner_settings *s);
int settings_valid(const miner_settings *s);
/* Returns 1 for a stored record, 0 for defaults, -1 for I/O failure. */
int settings_load(miner_settings *s, settings_read read);
/* Writes the other slot, verifies, then writes its commit byte last. */
int settings_save(const miner_settings *s, settings_read read, settings_write write);
#endif
