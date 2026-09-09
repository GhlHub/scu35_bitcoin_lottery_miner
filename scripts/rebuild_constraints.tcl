set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
reset_run synth_1
close_project
source $root/scripts/build_hardware.tcl
