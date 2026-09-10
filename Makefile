VIVADO ?= vivado
RTL := $(wildcard rtl/*.sv)

.PHONY: bd review sim synth platform bootloader application implement images image-base package test test-hybrid
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
	gcc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -Isoftware/common tb/test_ina700.c software/common/ina700.c -o build/test_ina700
	build/test_ina700
	bash tb/test_power_iic.sh
	iverilog -g2012 -s tb_hyperbus_wready_probe -o build/sim/hyperbus_wready_probe third_party/hyperbus_controller/rtl/hyperbus_axi_full_frontend.sv tb/tb_hyperbus_wready_probe.sv
	vvp build/sim/hyperbus_wready_probe
	gcc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -Isoftware/common tb/test_settings.c software/common/settings.c software/common/srec.c -o build/test_settings
	build/test_settings
	gcc -std=c11 -Wall -Wextra -Werror -Isoftware/common -Ithird_party/FreeRTOS-LTS/FreeRTOS/coreJSON/source/include tb/test_json.c third_party/FreeRTOS-LTS/FreeRTOS/coreJSON/source/core_json.c -o build/test_json
	build/test_json
	gcc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -Isoftware/common -Ithird_party/FreeRTOS-LTS/FreeRTOS/coreJSON/source/include tb/test_miner_protocol.c software/common/miner_protocol.c software/common/settings.c third_party/FreeRTOS-LTS/FreeRTOS/coreJSON/source/core_json.c -o build/test_miner_protocol
	build/test_miner_protocol
	python3 tb/test_bitcoin.py
	python3 tb/test_dashboard.py
	bash tb/test_network.sh
	bash tb/test_stratum_telemetry.sh
test-hybrid:
	bash scripts/test_hybrid_xsim.sh
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
	verilator --binary --timing -Wno-fatal --top-module tb_genesis -GHYBRID=1 --Mdir build/sim/genesis_hybrid $(RTL) tb/tb_genesis.sv > build/sim/genesis_hybrid_compile.log 2>&1
	build/sim/genesis_hybrid/Vtb_genesis
	verilator --binary --timing -Wno-fatal --top-module tb_bitcoin_miner_axi -GHYBRID=1 --Mdir build/sim/miner_hybrid $(RTL) tb/tb_bitcoin_miner_axi.sv > build/sim/miner_hybrid_compile.log 2>&1
	build/sim/miner_hybrid/Vtb_bitcoin_miner_axi
