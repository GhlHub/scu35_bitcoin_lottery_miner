VIVADO ?= vivado
RTL := $(wildcard rtl/*.sv)

.PHONY: bd review sim synth platform bootloader application implement images image-base package test
platform:
	/tools/Xilinx/2026.1/Vitis/bin/vitis -s software/build_platform.py
bootloader:
	bash software/build_bootloader.sh
application:
	bash software/build_application.sh
implement:
	$(VIVADO) -mode batch -source scripts/implement.tcl -log logs/implementation.log -journal logs/implementation.jou
images:
	$(MAKE) image-base
	$(MAKE) package
image-base:
	$(VIVADO) -mode batch -source scripts/write_image.tcl -log logs/write_image.log -journal logs/write_image.jou
package:
	python3 scripts/package_images.py
	$(VIVADO) -mode batch -source scripts/flash_mcs.tcl -log logs/flash_mcs.log -journal logs/flash_mcs.jou
	python3 scripts/verify_mcs.py
test: sim
	iverilog -g2012 -s tb_hyperbus_wready_probe -o build/sim/hyperbus_wready_probe third_party/hyperbus_controller/rtl/hyperbus_axi_full_frontend.sv tb/tb_hyperbus_wready_probe.sv
	vvp build/sim/hyperbus_wready_probe
	gcc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -Isoftware/common tb/test_settings.c software/common/settings.c software/common/srec.c -o build/test_settings
	build/test_settings
	gcc -std=c11 -Wall -Wextra -Werror -Isoftware/common -Ithird_party/FreeRTOS-LTS/FreeRTOS/coreJSON/source/include tb/test_json.c third_party/FreeRTOS-LTS/FreeRTOS/coreJSON/source/core_json.c -o build/test_json
	build/test_json
	python3 tb/test_bitcoin.py
	python3 tb/test_dashboard.py
	bash tb/test_network.sh
synth:
	mkdir -p logs
	$(VIVADO) -mode batch -source scripts/build_hardware.tcl -log logs/hardware.log -journal logs/hardware.jou
bd:
	mkdir -p logs
	$(VIVADO) -mode batch -source scripts/create_bd.tcl -log logs/create_bd.log -journal logs/create_bd.jou

review:
	mkdir -p logs
	$(VIVADO) -mode gui -source scripts/open_review.tcl -log logs/review.log -journal logs/review.jou

sim:
	mkdir -p build/sim
	verilator --binary --timing -Wno-fatal --top-module tb_bitcoin_miner_axi --Mdir build/sim/miner $(RTL) tb/tb_bitcoin_miner_axi.sv > build/sim/compile.log 2>&1
	build/sim/miner/Vtb_bitcoin_miner_axi
	verilator --binary --timing -Wno-fatal --top-module tb_genesis --Mdir build/sim/genesis $(RTL) tb/tb_genesis.sv > build/sim/genesis_compile.log 2>&1
	build/sim/genesis/Vtb_genesis
	verilator --binary --timing -Wno-fatal --top-module tb_resets --Mdir build/sim/resets rtl/irq_sync.sv rtl/phy_reset_hold.sv tb/tb_resets.sv > build/sim/resets_compile.log 2>&1
	build/sim/resets/Vtb_resets
