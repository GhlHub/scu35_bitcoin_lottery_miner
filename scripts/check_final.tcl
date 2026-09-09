set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
open_bd_design [get_files */design_1.bd]
source $root/scripts/audit_bd.tcl
foreach run {synth_1 impl_1} {
    puts "FINAL_RUN $run progress=[get_property PROGRESS [get_runs $run]] stale=[get_property NEEDS_REFRESH [get_runs $run]]"
    if {[get_property NEEDS_REFRESH [get_runs $run]] || [get_property PROGRESS [get_runs $run]] ne "100%"} {
        error "$run is not current"
    }
}
puts "FINAL_HARDWARE_AUDIT_PASSED"
close_project
exit
