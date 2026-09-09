set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $root/build/vivado/scu35_miner.runs/impl_1/design_1_wrapper_routed.dcp
foreach name {IIC_0_scl_iobuf IIC_0_sda_iobuf MDIO_0_mdio_iobuf} {
    foreach c [get_cells -hier -filter "NAME =~ $name/*"] {
        puts "CELL $c [get_property REF_NAME $c]"
        foreach p [get_pins -of $c -filter {DIRECTION == OUT}] {puts "PIN $p NET [get_nets -of $p] LOADS [get_pins -leaf -of [get_nets -segments -of $p]]"}
    }
}
foreach p [get_pins {design_1_i/eeprom_iic/scl_i design_1_i/eeprom_iic/sda_i design_1_i/ethernet/phy_mdio_i}] {
    puts "INPUT $p NETS [get_nets -segments -of $p] LOADS [get_pins -leaf -of [get_nets -segments -of $p]]"
}
foreach n [get_nets -hier -filter {NAME =~ *scl* || NAME =~ *sda_i* || NAME =~ *mdio_i*}] {puts "TRACE $n [get_pins -leaf -of [get_nets -segments $n]]"}
exit
