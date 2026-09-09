# Read-only JTAG inventory: never program a device or configuration memory.
set server "10.0.1.109:3121"
if {$argc > 0} { set server [lindex $argv 0] }
open_hw_manager
connect_hw_server -url $server
foreach target [get_hw_targets] {
    puts "REMOTE_TARGET $target"
    current_hw_target $target
    open_hw_target
    foreach device [get_hw_devices] {
        puts "REMOTE_DEVICE $device"
        foreach property {NAME PART IDCODE DNA IS_PROGRAMMED PROGRAM.FILE} {
            if {[lsearch -exact [list_property $device] $property] >= 0} {
                if {![catch {get_property $property $device} value]} {
                    puts "REMOTE_PROPERTY $property=$value"
                }
            }
        }
    }
    close_hw_target
}
disconnect_hw_server
close_hw_manager
exit
