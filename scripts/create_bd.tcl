# SPDX-License-Identifier: Apache-2.0
# Build the reviewable design only. No synthesis or implementation is launched.
set root [file normalize [file join [file dirname [info script]] ..]]
set out $root/build/vivado
if {[file exists $out/scu35_miner.xpr]} {
    error "Project already exists; open it with scripts/open_review.tcl or use a fresh build directory."
}
create_project scu35_miner $out -part xcsu35p-sbvb625-2-e
set_property board_part xilinx.com:scu35:part0:2.0 [current_project]
set_property ip_repo_paths [list $root/third_party/hyperbus_controller/ip_repo $root/build/ip_repo] [current_project]
update_ip_catalog
add_files [glob $root/rtl/*.sv]
set reference $root/third_party/hyperbus_controller/vivado_projects/hyperbus_test_proj/hyperbus_test_proj.srcs/sources_1/bd/design_1/design_1.bd
import_files -norecurse $reference
set bd [get_files */design_1.bd]
open_bd_design $bd
# Refresh imported metadata against the selected local IP packages.
upgrade_ip [get_ips -quiet *]
set_property CONFIG.CLKOUT3_REQUESTED_OUT_FREQ 50 [get_bd_cells clk_wiz_0]

proc wire_to {source args} {
    foreach dest $args {
        connect_bd_net [get_bd_pins $source] [get_bd_pins $dest]
    }
}
proc tie_low {pin} {
    connect_bd_net [get_bd_pins reset_zero/dout] [get_bd_pins $pin]
}

# Exactly 16 KiB of shared instruction/data local boot memory.
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces microblaze_0/*] -filter {NAME =~ *lmb*}] {
    set_property range 16K $seg
}
# Integer-only controller, with caches covering the 8 MiB external HyperRAM.
set_property -dict [list CONFIG.C_USE_FPU 0 CONFIG.C_FPU_EXCEPTION 0] [get_bd_cells microblaze_0]

# Make every reset cause explicit. Each domain releases reset on its own
# continuously running clock, never on the gated HyperRAM forwarding clock.
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 reset_zero
set_property CONFIG.CONST_VAL 0 [get_bd_cells reset_zero]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 reset_one
set_property CONFIG.CONST_VAL 1 [get_bd_cells reset_one]
foreach cell [get_bd_cells -hier -filter {VLNV =~ *:proc_sys_reset:*}] {
    # Polarity is propagated from the ACTIVE_LOW source reset interface.
    set debug_pin [get_bd_pins $cell/mb_debug_sys_rst]
    set old [get_bd_nets -quiet -of_objects $debug_pin]
    if {[llength $old]} {disconnect_bd_net $old $debug_pin}
    connect_bd_net [get_bd_pins mdm_0/Debug_SYS_Rst] $debug_pin
    set_property CONFIG.C_AUX_RESET_HIGH 0 $cell
    connect_bd_net [get_bd_pins reset_one/dout] [get_bd_pins $cell/aux_reset_in]
}
# The wizard runs through board/debug reset so all synchronizers retain clocks.
tie_low clk_wiz_0/reset

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernetlite:3.0 ethernet
set_property -dict [list CONFIG.C_INCLUDE_MDIO 1 CONFIG.C_TX_PING_PONG 1 CONFIG.C_RX_PING_PONG 1] [get_bd_cells ethernet]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 eeprom_iic
create_bd_cell -type ip -vlnv xilinx.com:ip:system_management_wiz:1.3 sysmon
set_property -dict [list CONFIG.INTERFACE_SELECTION Enable_AXI CONFIG.CHANNEL_ENABLE_TEMPERATURE true CONFIG.CHANNEL_ENABLE_VCCINT true CONFIG.CHANNEL_ENABLE_VCCAUX true CONFIG.SEQUENCER_MODE Continuous] [get_bd_cells sysmon]
tie_low sysmon/vp
tie_low sysmon/vn

create_bd_cell -type module -reference bitcoin_miner_axi miner
set_property -dict [list CONFIG.NUM_ENGINES 3 CONFIG.CLUSTER_SIZE 2 CONFIG.CLUSTER_FIFO_DEPTH 4 CONFIG.EXPLICIT_DSP_SCHEDULE 1 CONFIG.DSP_ROUND_STATE 1] [get_bd_cells miner]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter:2.1 miner_clock_crossing
set_property -dict [list CONFIG.PROTOCOL AXI4LITE CONFIG.ADDR_WIDTH 12 CONFIG.DATA_WIDTH 32 CONFIG.ACLK_ASYNC 1] [get_bd_cells miner_clock_crossing]

set_property CONFIG.NUM_MI 9 [get_bd_cells axi_crossbar_0]
foreach {slot intf} {05 ethernet/S_AXI 06 eeprom_iic/S_AXI 07 sysmon/S_AXI_LITE 08 miner_clock_crossing/S_AXI} {
    connect_bd_intf_net [get_bd_intf_pins axi_crossbar_0/M${slot}_AXI] [get_bd_intf_pins $intf]
}
connect_bd_intf_net [get_bd_intf_pins miner_clock_crossing/M_AXI] [get_bd_intf_pins miner/S_AXI]
wire_to clk_wiz_0/clk_out3 ethernet/s_axi_aclk eeprom_iic/s_axi_aclk sysmon/s_axi_aclk miner_clock_crossing/s_axi_aclk
wire_to reset_gen/axi_clk_peripheral_aresetn ethernet/s_axi_aresetn eeprom_iic/s_axi_aresetn sysmon/s_axi_aresetn miner_clock_crossing/s_axi_aresetn
wire_to clk_wiz_0/clk_out1 miner/s_axi_aclk miner_clock_crossing/m_axi_aclk
wire_to reset_gen/hb_clk_peripheral_aresetn miner/s_axi_aresetn miner_clock_crossing/m_axi_aresetn

# Dedicated two-flop level interrupt crossing (miner 200 MHz -> CPU 50 MHz).
create_bd_cell -type module -reference irq_sync miner_irq_sync
wire_to clk_wiz_0/clk_out3 miner_irq_sync/clk
wire_to reset_gen/axi_clk_peripheral_aresetn miner_irq_sync/resetn
wire_to miner/irq_o miner_irq_sync/async_irq
set_property CONFIG.NUM_PORTS 7 [get_bd_cells ilconcat_0]
foreach {pin source} {In3 ethernet/ip2intc_irpt In4 eeprom_iic/iic2intc_irpt In5 sysmon/ip2intc_irpt In6 miner_irq_sync/irq} {
    connect_bd_net [get_bd_pins ilconcat_0/$pin] [get_bd_pins $source]
}
# Quad SPI (bit 2) and EthernetLite (bit 3) specify rising-edge IRQs in
# their vendor interfaces. UART, timer, IIC, SysMon and miner are level-high.
set_property CONFIG.C_KIND_OF_INTR 0x0000000C [get_bd_cells axi_intc_0]

# Export MII signals individually because PHY reset is stretched below.
foreach {pin suffix direction width} {
    phy_col col I 1 phy_crs crs I 1 phy_rx_clk rx_clk I 1
    phy_dv rx_dv I 1 phy_rx_er rx_er I 1 phy_rx_data rxd I 4
    phy_tx_clk tx_clk I 1 phy_tx_en tx_en O 1 phy_tx_data txd O 4
} {
    if {$width == 1} {create_bd_port -dir $direction MII_0_$suffix} else {
        create_bd_port -dir $direction -from 3 -to 0 MII_0_$suffix
    }
    connect_bd_net [get_bd_pins ethernet/$pin] [get_bd_ports MII_0_$suffix]
}
# EthernetLite never transmits an errored symbol; drive the PHY TX_ER input low.
create_bd_port -dir O MII_0_tx_er
connect_bd_net [get_bd_pins reset_zero/dout] [get_bd_ports MII_0_tx_er]
make_bd_intf_pins_external [get_bd_intf_pins ethernet/MDIO]
make_bd_intf_pins_external [get_bd_intf_pins eeprom_iic/IIC]
# Hold the PHY in reset for at least 10 ms after the system reset releases.
create_bd_cell -type module -reference phy_reset_hold phy_reset
wire_to clk_wiz_0/clk_out3 phy_reset/clk
wire_to ethernet/phy_rst_n phy_reset/resetn
create_bd_port -dir O -type rst phy_reset_n
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports phy_reset_n]
connect_bd_net [get_bd_pins phy_reset/phy_resetn] [get_bd_ports phy_reset_n]

foreach {path offset range} {ethernet/S_AXI/Reg 0x40E00000 64K eeprom_iic/S_AXI/Reg 0x40800000 64K sysmon/S_AXI_LITE/Reg 0x44A20000 64K miner/S_AXI/reg0 0x44A30000 4K} {
    assign_bd_address -offset $offset -range $range -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs $path]
}
# Imported crossbar parameters have user provenance, so address-editor changes
# alone do not update these previously disabled decode windows.
foreach {slot address bits} {05 0x40E00000 16 06 0x40800000 16 07 0x44A20000 16 08 0x44A30000 12} {
    set_property CONFIG.M${slot}_A00_BASE_ADDR $address [get_bd_cells axi_crossbar_0]
    set_property CONFIG.M${slot}_A00_ADDR_WIDTH $bits [get_bd_cells axi_crossbar_0]
}
validate_bd_design
source $root/scripts/audit_bd.tcl
save_bd_design
write_bd_tcl -force $root/build/scu35_miner_recreate.tcl
make_wrapper -files $bd -top
add_files $out/scu35_miner.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v
set_property top design_1_wrapper [current_fileset]
add_files -fileset constrs_1 $root/constraints/scu35.xdc
add_files -fileset constrs_1 $root/constraints/interfaces.xdc
set_property PROCESSING_ORDER LATE [get_files $root/constraints/interfaces.xdc]
set_property USED_IN_SYNTHESIS false [get_files $root/constraints/interfaces.xdc]
update_compile_order -fileset sources_1
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
puts "REVIEW_READY: [get_property DIRECTORY [current_project]]/scu35_miner.xpr"
puts "SYNTHESIS_NOT_STARTED: user block-design/reset review required."
close_project
exit
