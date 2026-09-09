#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
toolroot=${VITIS_ROOT:-/tools/Xilinx/2026.1/Vitis}
tcp=third_party/FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source
gcc -O2 -Wall -Wextra -Werror -ffunction-sections -fdata-sections \
  -fsanitize=address,undefined -Wl,--gc-sections -DSDT \
  -Isoftware/application -Isoftware/common \
  -Ibuild/vitis/scu35_platform/microblaze_0/standalone_microblaze_0/bsp/include \
  -Ithird_party/FreeRTOS-LTS/FreeRTOS/FreeRTOS-Kernel/include \
  -I"$toolroot/data/embeddedsw/ThirdParty/bsp/freertos10_xilinx_v1_18/src/Source/portable/GCC/MicroBlazeV9" \
  -I"$tcp/include" -I"$tcp/portable/Compiler/GCC" \
  tb/test_network.c -o build/test_network
build/test_network
