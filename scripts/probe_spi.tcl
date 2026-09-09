# Read-only flash commands through the halted-at-failure bootloader's SPI core.
connect -url tcp:10.0.1.109:3121
targets -set -filter {name == "MicroBlaze #0" && jtag_cable_serial == "52041A454A5TA"}
puts "SPI_CONTROL [mrd 0x44a00060]"
puts "SPI_STATUS [mrd 0x44a00064]"
puts "SPI_ISR [mrd 0x44a00020]"
for {set attempt 0} {$attempt < 2} {incr attempt} {
    mwr 0x44a00060 0x1e6
    mwr 0x44a00060 0x186
    foreach byte {0x9f 0 0 0} {mwr 0x44a00068 $byte}
    mwr 0x44a00070 0xfffffffe
    mwr 0x44a00060 0x86
    after 10
    puts "ATTEMPT $attempt STATUS [mrd 0x44a00064] ISR [mrd 0x44a00020]"
    for {set i 0} {$i < 4} {incr i} {
        if {[expr {[mrd -value 0x44a00064] & 1}]} { break }
        puts "RX $i [mrd 0x44a0006c]"
    }
    mwr 0x44a00060 0x186
    mwr 0x44a00070 0xffffffff
}
mwr 0x44a00060 0x1e6
mwr 0x44a00060 0x186
foreach byte {3 0x80 0 0} {mwr 0x44a00068 $byte}
for {set i 0} {$i < 32} {incr i} {mwr 0x44a00068 0}
mwr 0x44a00070 0xfffffffe
mwr 0x44a00060 0x86
after 10
set data {}
for {set i 0} {$i < 36} {incr i} {
    if {[expr {[mrd -value 0x44a00064] & 1}]} { break }
    lappend data [format %02x [mrd -value 0x44a0006c]]
}
puts "SREC_READ $data"
mwr 0x44a00060 0x186
mwr 0x44a00070 0xffffffff
disconnect
exit
