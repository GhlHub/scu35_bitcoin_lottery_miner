set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
foreach run {synth_1 impl_1} {
    if {[get_property NEEDS_REFRESH [get_runs $run]] || [get_property PROGRESS [get_runs $run]] ne "100%"} {
        error "$run is absent or stale; rebuild before generating an image"
    }
}
open_run impl_1
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {![llength $setup] || ![llength $hold]} {error "Missing timing analysis"}
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {
    error "Timing is not closed; refusing image generation"
}
# These must be real receive nets, not unused pads from disabled AXI windows.
foreach buffer {IIC_0_scl_iobuf IIC_0_sda_iobuf MDIO_0_mdio_iobuf} {
    set loads [get_pins -leaf -of_objects [get_nets -segments -of_objects [get_pins $buffer/O]] -filter {DIRECTION == IN}]
    if {![llength $loads]} {error "No receive logic on $buffer"}
}
report_cdc -details -file $root/logs/route_cdc_details.rpt
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Bitstream generation failed"}
open_run impl_1
write_hw_platform -fixed -include_bit -force -file $root/build/scu35_miner.xsa
write_mem_info -force $root/build/scu35_miner.mmi
close_project
exit
