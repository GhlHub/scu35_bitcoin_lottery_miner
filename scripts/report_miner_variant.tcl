# Read-only analysis of a saved routed checkpoint; no project changes.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 2} {error "Usage: -tclargs checkpoint report_tag"}
set checkpoint [file normalize [lindex $argv 0]]
set tag [lindex $argv 1]
if {![regexp {^[A-Za-z0-9_]+$} $tag]} {error "Invalid report tag"}
open_checkpoint $checkpoint
set registers [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ design_1_i/miner/*}]
if {![llength $registers]} {error "Miner registers not found"}
report_timing -from $registers -to $registers -delay_type max -max_paths 10 -file $root/logs/${tag}_miner_timing.rpt
report_utilization -hierarchical -file $root/logs/${tag}_hier.rpt
set paths [get_timing_paths -from $registers -to $registers -delay_type max -max_paths 1]
if {![llength $paths]} {error "No miner timing paths"}
puts "MINER_VARIANT $tag registers=[llength $registers] setup_slack=[get_property SLACK $paths]"
puts "MINER_DSPS [llength [get_cells -hier -filter {REF_NAME == DSP48E2 && NAME =~ design_1_i/miner/*}]]"
close_design
exit
