# Destructive: explicit user authorization is required before running this file.
# Restricted to the SCU35 cable on the user's specified hardware server.
set root [file normalize [file join [file dirname [info script]] ..]]
if {$argc != 1 || [lindex $argv 0] ne "OVERWRITE_SCU35"} {
    error "Pass OVERWRITE_SCU35 only after approval to overwrite this board's flash"
}
exec python3 $root/scripts/verify_mcs.py
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
set mempart [get_cfgmem_parts -of_objects $device -filter {NAME == "cfgmem-128-qspi-x4-single"}]
if {[llength $mempart] != 1} { error "Flash part not unique" }
create_hw_cfgmem -hw_device $device $mempart
set memory [get_property PROGRAM.HW_CFGMEM $device]
set_property PROGRAM.FILES [list $root/build/images/scu35_flash.mcs] $memory
set_property PROGRAM.ERASE 1 $memory
set_property PROGRAM.BLANK_CHECK 1 $memory
set_property PROGRAM.CFG_PROGRAM 1 $memory
set_property PROGRAM.VERIFY 1 $memory
puts "PROGRAMMING_SCU35_FLASH target=$target device=$device image=$root/build/images/scu35_flash.mcs"
# create_hw_cfgmem selects AMD's SpartanUP embedded flash-programmer PDI.
set programmer [get_property PROGRAM.FILE $device]
if {![file exists $programmer] || ![string match */embedded_programmer/flash/xcsu35p/xcsu35p.pdi $programmer]} {
    error "Unexpected or missing embedded flash programmer: $programmer"
}
program_hw_devices $device
program_hw_cfgmem $memory
puts "SCU35_FLASH_PROGRAM_AND_VERIFY_PASSED"
close_hw_target
disconnect_hw_server
close_hw_manager
exit
