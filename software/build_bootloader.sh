#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
toolroot=${VITIS_ROOT:-/tools/Xilinx/2026.1/Vitis}
bsp=build/vitis/scu35_platform/microblaze_0/standalone_microblaze_0/bsp
compiler=$toolroot/gnu/microblaze/lin/bin/mb-gcc
mkdir -p build/bootloader
"$compiler" -Os -g -Wall -Wextra -ffunction-sections -fdata-sections \
  -mxl-barrel-shift -mlittle-endian -mxl-pattern-compare \
  -mno-xl-soft-mul -mno-xl-soft-div -mcpu=v11.0 -DSDT \
  -specs="$bsp/Xilinx.spec" -I"$bsp/include" -Isoftware/common \
  -Ithird_party/hyperbus_controller/software \
  software/bootloader/main.c software/common/console.c software/common/srec.c \
  third_party/hyperbus_controller/software/hyperbus_odly.c \
  -Tsoftware/bootloader/lscript.ld -L"$bsp/lib" \
  -Wl,--gc-sections,-Map,build/bootloader/bootloader.map \
  -Wl,--start-group -lxil -lxilstandalone -lxiltimer -lc -lgcc -Wl,--end-group \
  -o build/bootloader/bootloader.elf
"$toolroot/gnu/microblaze/lin/bin/mb-size" build/bootloader/bootloader.elf
