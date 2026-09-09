/* SPDX-License-Identifier: Apache-2.0 */
#ifndef SCU35_VERSIONS_H
#define SCU35_VERSIONS_H
#include <stdint.h>
/* Independent semantic versions; bump the component that changes.
 * Packed hardware/handoff values: major[31:24], minor[23:16], patch[15:0].
 * Zero means unavailable (older hardware or bootloader bypassed).
 */
#define BOOTLOADER_VERSION "1.0.0"
#define BOOTLOADER_VERSION_CODE UINT32_C(0x01000000)
#define APPLICATION_VERSION "1.0.0"
#define MINER_ENGINES_REG UINT32_C(0x44a30008)
#define MINER_HW_VERSION_REG UINT32_C(0x44a300b0)
#define MINER_BOOT_VERSION_REG UINT32_C(0x44a300b4)
#endif
