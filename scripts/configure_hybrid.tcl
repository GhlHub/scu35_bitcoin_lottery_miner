# Select the local DSP48E2 variant without changing clocks or interfaces.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc ni {1 2} || [lindex $argv 0] ni {0 1}} {error "Usage: -tclargs 0|1 (fabric|hybrid) ?0|1 (extra DSP adders)?"}
set extra 1
if {$argc == 2} {set extra [lindex $argv 1]}
if {$extra ni {0 1}} {error "Extra DSP adders must be 0 or 1"}
open_project $root/build/vivado/scu35_miner.xpr
foreach source [glob $root/rtl/*.sv] {
    if {![llength [get_files -quiet $source]]} {add_files -norecurse $source}
}
update_compile_order -fileset sources_1
set bd [get_files */design_1.bd]
open_bd_design $bd
update_module_reference [get_ips design_1_miner_0]
set_property CONFIG.EXPLICIT_DSP_SCHEDULE [lindex $argv 0] [get_bd_cells miner]
set_property CONFIG.DSP_ROUND_STATE $extra [get_bd_cells miner]
set_property CONFIG.NUM_ENGINES 3 [get_bd_cells miner]
source $root/scripts/audit_bd.tcl
save_bd_design
reset_target all $bd
generate_target all $bd
reset_run synth_1
close_project
exit
