# Restrict inspection/reboot to the approved SCU35, never another JTAG target.
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
foreach property [list_property $device] {
    if {[regexp -nocase {boot|mode|done} $property]} {
        if {![catch {get_property $property $device} value]} { puts "$property=$value" }
    }
}
if {$argc == 1 && [lindex $argv 0] eq "BOOT_SCU35"} {
    puts "SCU35_BOOT_RESULT [boot_hw_device -timeout 30 $device]"
}
close_hw_target
disconnect_hw_server
close_hw_manager
exit
