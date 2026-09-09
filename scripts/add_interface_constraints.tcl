set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
if {![llength [get_files -quiet $root/constraints/interfaces.xdc]]} {
    add_files -fileset constrs_1 $root/constraints/interfaces.xdc
}
set_property PROCESSING_ORDER LATE [get_files $root/constraints/interfaces.xdc]
set_property USED_IN_SYNTHESIS false [get_files $root/constraints/interfaces.xdc]
reset_run impl_1
close_project
source $root/scripts/implement.tcl
