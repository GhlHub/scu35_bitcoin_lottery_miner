open_hw_manager
connect_hw_server -url 10.0.1.109:3121
set target [lsearch -all -inline -glob [get_hw_targets] */52041A454A5TA]
if {[llength $target] != 1} { error "SCU35 cable not uniquely found" }
current_hw_target $target
open_hw_target
set device [get_hw_devices xcsu35p_0]
if {[llength $device] != 1 || [get_property PART $device] ne "xcsu35p"} { error "Wrong FPGA" }
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
puts "COMPATIBLE_CFGMEM [get_cfgmem_parts -of_objects $device]"
set mempart [get_cfgmem_parts -of_objects $device -filter {NAME == "cfgmem-128-qspi-x4-single"}]
if {[llength $mempart] != 1} { error "Flash part not unique" }
report_property $mempart
create_hw_cfgmem -hw_device $device $mempart
report_property [get_property PROGRAM.HW_CFGMEM $device]
foreach property [list_property $device] {
    if {[string match PROGRAM.* $property]} { puts "$property=[get_property $property $device]" }
}
close_hw_target
disconnect_hw_server
close_hw_manager
exit
