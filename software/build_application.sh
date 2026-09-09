#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
toolroot=${VITIS_ROOT:-/tools/Xilinx/2026.1/Vitis}
bsp=build/vitis/scu35_platform/microblaze_0/standalone_microblaze_0/bsp
kernel=third_party/FreeRTOS-LTS/FreeRTOS/FreeRTOS-Kernel
tcp=third_party/FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source
json=third_party/FreeRTOS-LTS/FreeRTOS/coreJSON/source
port=$toolroot/data/embeddedsw/ThirdParty/bsp/freertos10_xilinx_v1_18/src/Source/portable/GCC/MicroBlazeV9
mkdir -p build/application
"$toolroot/gnu/microblaze/lin/bin/mb-gcc" -O2 -g -Wall -Wextra \
  -ffunction-sections -fdata-sections -mxl-barrel-shift -mlittle-endian \
  -mxl-pattern-compare -mno-xl-soft-mul -mno-xl-soft-div -mcpu=v11.0 -DSDT \
  -specs="$bsp/Xilinx.spec" -I"$bsp/include" -Isoftware/application -Isoftware/common \
  -I"$kernel/include" -I"$port" -I"$tcp/include" -I"$tcp/portable/Compiler/GCC" -I"$json/include" \
  software/application/*.c software/common/console.c software/common/settings.c software/common/bitcoin.c software/common/sha256_sw.c software/common/miner_protocol.c \
  "$kernel/tasks.c" "$kernel/queue.c" "$kernel/list.c" "$kernel/timers.c" \
  "$kernel/event_groups.c" "$kernel/stream_buffer.c" "$kernel/portable/MemMang/heap_4.c" \
  "$port/port.c" "$port/portasm.S" "$port/portmicroblaze.c" "$port/port_exceptions.c" \
  "$tcp"/*.c "$tcp/portable/BufferManagement/BufferAllocation_1.c" "$json/core_json.c" \
  -Tsoftware/application/lscript.ld -L"$bsp/lib" \
  -Wl,--gc-sections,-Map,build/application/miner.map \
  -Wl,--start-group -lxil -lxilstandalone -lxiltimer -lc -lm -lgcc -Wl,--end-group \
  -o build/application/miner.elf
"$toolroot/gnu/microblaze/lin/bin/mb-size" build/application/miner.elf
"$toolroot/gnu/microblaze/lin/bin/mb-objcopy" -O srec --srec-forceS3 build/application/miner.elf build/application/miner.srec
python3 scripts/verify_srec.py build/application/miner.srec
