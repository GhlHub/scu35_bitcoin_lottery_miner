connect -url tcp:10.0.1.109:3121
targets -set -filter {name == "MicroBlaze #0" && jtag_cable_serial == "52041A454A5TA"}
if {[catch {stop} result]} {puts "STOP: $result"}
puts [rrd pc]
puts [rrd msr]
puts [mrd 0x80000000 8]
puts [mrd 0x10800]
disconnect
exit
