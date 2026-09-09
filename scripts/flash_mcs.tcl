set root [file normalize [file join [file dirname [info script]] ..]]
# Raw PDI bytes at zero and raw ASCII SREC bytes at 8 MiB. Never pass the
# application's SREC as an address-bearing configuration record to this tool.
write_cfgmem -force -format mcs -interface SPIx4 -size 16 -disablebitswap \
    -loaddata [list up 0x00000000 $root/build/images/scu35_bootloader.pdi \
                   up 0x00800000 $root/build/images/miner.srec] \
    -file $root/build/images/scu35_flash.mcs
exit
