# Refresh the pinned upstream IP; source/bitstream checks precede programming.
set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
update_ip_catalog -rebuild
set bd [get_files */design_1.bd]
open_bd_design $bd
set ip [get_ips design_1_hyperbus_controller_0_0]
if {[llength $ip] != 1} {error "HyperBus IP instance not unique"}
upgrade_ip $ip
reset_target all $bd
generate_target all $bd
update_compile_order -fileset sources_1
source $root/scripts/audit_bd.tcl
save_bd_design
reset_run synth_1
close_project
exit
