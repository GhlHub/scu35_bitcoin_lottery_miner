set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
open_run impl_1
set dsps [get_cells -hier -filter {REF_NAME == DSP48E2}]
set miner_dsps [get_cells -hier -filter {REF_NAME == DSP48E2 && NAME =~ *miner*}]
puts "HYBRID_DSP_COUNT total=[llength $dsps] miner=[llength $miner_dsps]"
set expected 30
if {$argc == 1} {set expected [lindex $argv 0]}
if {[llength $miner_dsps] != $expected} {error "Expected $expected miner DSP48E2 slices"}
report_utilization -hierarchical -file $root/logs/route_hybrid_hier.rpt
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
puts "HYBRID_SLACK setup=[get_property SLACK $setup] hold=[get_property SLACK $hold]"
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {error "Timing failed"}
puts "HYBRID_IMPLEMENTATION_PASSED"
close_project
exit
