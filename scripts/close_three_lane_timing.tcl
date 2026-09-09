# Enable post-route optimization for the tight HyperRAM receive crossing.
# No clock, exception, I/O constraint, or RTL changes are made here.
set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
set run [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $run
reset_run impl_1 -from_step {phys_opt_design (Post-Route)}
launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS $run] ne "100%"} {error "Post-route optimization failed"}
close_project
exit
