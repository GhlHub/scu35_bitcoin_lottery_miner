set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
open_bd_design [get_files */design_1.bd]
foreach {slot address bits} {05 0x40E00000 16 06 0x40800000 16 07 0x44A20000 16 08 0x44A30000 12} {
    set_property CONFIG.M${slot}_A00_BASE_ADDR $address [get_bd_cells axi_crossbar_0]
    set_property CONFIG.M${slot}_A00_ADDR_WIDTH $bits [get_bd_cells axi_crossbar_0]
}
validate_bd_design
source $root/scripts/audit_bd.tcl
save_bd_design
write_bd_tcl -force $root/build/scu35_miner_recreate.tcl
reset_run synth_1
close_project
source $root/scripts/build_hardware.tcl
