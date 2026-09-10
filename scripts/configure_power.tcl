set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
set bd [get_files */design_1.bd]
open_bd_design $bd
update_module_reference [get_ips design_1_miner_0]
source $root/scripts/power_iic_bd.tcl
source $root/scripts/audit_bd.tcl
save_bd_design
write_bd_tcl -force $root/build/scu35_miner_recreate.tcl
reset_target all $bd
generate_target all $bd
make_wrapper -files $bd -top -force
update_compile_order -fileset sources_1
reset_run synth_1
close_project
exit
