# Volatile test: calibrate RAM using the loader, stop before SPI, load the app.
set root [file normalize [file join [file dirname [info script]] ..]]
connect -url tcp:10.0.1.109:3121
targets -set -filter {name == "MicroBlaze #0" && jtag_cable_serial == "52041A454A5TA"}
rst -system
stop
dow $root/build/bootloader/bootloader.elf
set symbols [exec /tools/Xilinx/2026.1/Vitis/gnu/microblaze/lin/bin/mb-nm $root/build/bootloader/bootloader.elf]
if {![regexp -line {^([0-9a-f]+) [tT] transfer$} $symbols match address]} {error "No transfer symbol"}
puts "CALIBRATION_HOLD 0x$address"
# Volatile branch-to-self at first SPI transfer; avoids unreliable breakpoints.
mwr 0x$address 0xb8000000
con
after 2000
stop
puts "CALIBRATION_STOPPED [rrd pc]"
dow $root/build/application/miner.elf
puts "APPLICATION_DOWNLOADED [rrd pc]"
# Execute a real absolute branch; this server's PC-write path does not move PC.
mwr 0x$address {0xb0008000 0xb8080000 0x80000000}
con
disconnect
exit
