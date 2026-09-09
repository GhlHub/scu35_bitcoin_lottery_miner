# Static design checks only; no synthesis.
proc require {condition message} {
    if {![uplevel 1 [list expr $condition]]} {error "AUDIT FAILED: $message"}
}
proc same_net {a b} {
    set connected [find_bd_objs -relation connected_to -thru_hier [get_bd_pins $a]]
    set target [get_bd_pins $b]
    require {[llength $target] == 1 && [lsearch -exact $connected $target] >= 0} "$a and $b must share a net"
}
validate_bd_design
foreach space {Data Instruction} {
    set local [get_bd_addr_segs microblaze_0/$space/SEG_lmb_bram_if_cntlr_0_Mem]
    require {[get_property RANGE $local] == 16384} "$space local RAM must be 16 KiB"
}
foreach cell [get_bd_cells -hier -filter {VLNV =~ *:proc_sys_reset:*}] {
    require {[get_property CONFIG.C_EXT_RESET_HIGH $cell] == 0} "$cell board/cascade reset polarity"
    require {[get_property CONFIG.C_AUX_RESET_HIGH $cell] == 0} "$cell auxiliary reset polarity"
    same_net $cell/aux_reset_in reset_one/dout
    same_net $cell/mb_debug_sys_rst mdm_0/Debug_SYS_Rst
    puts "RESET_AUDIT $cell external=active-low auxiliary=inactive-high debug=MDM"
}
same_net clk_wiz_0/clk_out1 miner/s_axi_aclk
require {[get_property CONFIG.CLKOUT2_REQUESTED_PHASE [get_bd_cells clk_wiz_0]] == 90} "HyperRAM receive clock must retain its 90 degree phase"
same_net clk_wiz_0/clk_out3 microblaze_0/Clk
require {[get_property CONFIG.FREQ_HZ [get_bd_pins microblaze_0/Clk]] == 50000000} "MicroBlaze must run at exactly 50 MHz"
same_net clk_wiz_0/clk_out5 hyperbus_controller_0/i_hb_clk_200_gated
same_net hyperbus_controller_0/o_hb_clk_ce clk_wiz_0/clk_out5_ce
same_net miner/irq_o miner_irq_sync/async_irq
same_net miner_irq_sync/irq ilconcat_0/In6
require {[get_property CONFIG.ACLK_ASYNC [get_bd_cells miner_clock_crossing]] == 1} "AXI CDC mode"
require {[get_property CONFIG.NUM_ENGINES [get_bd_cells miner]] == 2} "Engine count"
require {[get_property CONFIG.C_KIND_OF_INTR [get_bd_cells axi_intc_0]] == 12} "IRQ modes must match source interfaces (miner level-high)"
# Confirm physical AXI decode, not only the address-editor view. Imported
# user-valued crossbar parameters otherwise leave new peripherals unreachable.
foreach {slot address bits} {05 0x40E00000 16 06 0x40800000 16 07 0x44A20000 16 08 0x44A30000 12} {
    set actual [get_property CONFIG.M${slot}_A00_BASE_ADDR [get_bd_cells axi_crossbar_0]]
    if {$actual != $address} {error "Crossbar M$slot base is $actual, expected $address"}
    if {[get_property CONFIG.M${slot}_A00_ADDR_WIDTH [get_bd_cells axi_crossbar_0]] != $bits} {
        error "Crossbar M$slot decode width is wrong"
    }
}
puts "BD_AUDIT_PASSED"
