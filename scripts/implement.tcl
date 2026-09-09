set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
if {[get_property NEEDS_REFRESH [get_runs synth_1]] || [get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis is absent or stale; run make synth first"
}
if {[get_property NEEDS_REFRESH [get_runs impl_1]]} {reset_run impl_1}
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 4
    wait_on_run impl_1
}
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_utilization -file $root/logs/route_utilization.rpt
report_timing_summary -report_unconstrained -max_paths 20 -file $root/logs/route_timing.rpt
report_drc -file $root/logs/route_drc.rpt
report_cdc -file $root/logs/route_cdc.rpt
report_bus_skew -file $root/logs/route_bus_skew.rpt
# No bitstream until timing and board-interface constraints have been reviewed.
close_project
exit
