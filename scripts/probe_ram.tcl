# Scratch HyperRAM only; use while loader is stopped in its failure loop.
connect -url tcp:10.0.1.109:3121
targets -set -filter {name == "MicroBlaze #0" && jtag_cable_serial == "52041A454A5TA"}
set cr0 [mrd -value 0x10800]
puts "ORIGINAL_CR0 [format %04x $cr0]"
foreach mode {variable fixed} {
    set value [expr {$mode eq "fixed" ? $cr0 | 8 : $cr0 & ~8}]
    mwr 0x10800 $value
    puts "MODE $mode CR0 [mrd 0x10800]"
    mwr 0x807ff000 {0x12345678 0xabcdef01 0xdeadbeef 0x87654321}
    puts [mrd 0x807ff000 4]
    puts [mrd 0x807ff000 4]
    mwr -size b 0x807ff000 0x55
    puts "BYTE_WRITE [mrd 0x807ff000 4]"
}
mwr 0x10800 $cr0
disconnect
exit
