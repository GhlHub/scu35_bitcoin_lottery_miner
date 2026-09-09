set root [file normalize [file join [file dirname [info script]] ..]]
connect -url tcp:10.0.1.109:3121
targets -set -filter {name == "MicroBlaze #0" && jtag_cable_serial == "52041A454A5TA"}
set symbols [exec /tools/Xilinx/2026.1/Vitis/gnu/microblaze/lin/bin/mb-nm $root/build/application/miner.elf]
foreach name {xTickCount network_up uxCurrentNumberOfTasks xSchedulerRunning} {
    if {[regexp -line [format {^([0-9a-f]+) [bBdD] %s$} $name] $symbols match addr]} {
        puts "$name [mrd 0x$addr]"
        after 100
        puts "$name [mrd 0x$addr]"
    }
}
puts "TIMER [mrd 0x41c00000 3]"
puts "INTC [mrd 0x41200000 8]"
if {![catch {stop} result]} {
    puts [rrd pc]
    puts [rrd msr]
    con
} else {puts "STOP: $result"}
disconnect
exit
