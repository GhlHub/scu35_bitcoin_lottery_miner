# Withdraw the 210 MHz experiment and restore the original shared domain.
set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
set bd [get_files */design_1.bd]
open_bd_design $bd
update_module_reference [get_ips design_1_miner_0]
foreach {source destination} {
    clk_wiz_0/clk_out1 miner/s_axi_aclk
    clk_wiz_0/clk_out1 miner_clock_crossing/m_axi_aclk
    reset_gen/hb_clk_peripheral_aresetn miner/s_axi_aresetn
    reset_gen/hb_clk_peripheral_aresetn miner_clock_crossing/m_axi_aresetn
    clk_wiz_0/clk_out3 miner_clock_crossing/s_axi_aclk
    reset_gen/axi_clk_peripheral_aresetn miner_clock_crossing/s_axi_aresetn
} {
    set pin [get_bd_pins $destination]
    set old [get_bd_nets -quiet -of_objects $pin]
    if {[llength $old]} {disconnect_bd_net $old $pin}
    connect_bd_net [get_bd_pins $source] $pin
}
foreach name {hash_reset_210 hash_reset_50 hash_clk_wiz} {
    set cell [get_bd_cells -quiet $name]
    if {[llength $cell]} {delete_bd_objs $cell}
}
set_property CONFIG.ACLK_ASYNC 1 [get_bd_cells miner_clock_crossing]
source $root/scripts/audit_bd.tcl
save_bd_design
write_bd_tcl -force $root/build/scu35_miner_recreate.tcl
reset_target all $bd
generate_target all $bd
reset_run synth_1
close_project
exit
