# The user approved the block design/reset review on 2026-09-09.
set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
set bd [get_files */design_1.bd]
open_bd_design $bd
source $root/scripts/audit_bd.tcl
generate_target all $bd
update_compile_order -fileset sources_1
write_hw_platform -fixed -force -file $root/build/scu35_miner.xsa
if {[get_property NEEDS_REFRESH [get_runs synth_1]]} {reset_run synth_1}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
}
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
open_run synth_1
report_utilization -file $root/logs/synth_utilization.rpt
report_utilization -hierarchical -file $root/logs/synth_utilization_hier.rpt
report_timing_summary -file $root/logs/synth_timing.rpt
report_drc -file $root/logs/synth_drc.rpt
report_clocks -file $root/logs/synth_clocks.rpt
puts "SYNTHESIS_COMPLETE"
close_project
exit
