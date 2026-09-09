# Volatile bootloader test only; no flash or EEPROM programming.
set root [file normalize [file join [file dirname [info script]] ..]]
connect -url tcp:10.0.1.109:3121
targets -set -filter {name == "MicroBlaze #0" && jtag_cable_serial == "52041A454A5TA"}
rst -system
stop
dow $root/build/bootloader/bootloader.elf
con
disconnect
exit
