set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado_attempt3/scu35_miner.xpr
open_bd_design [get_files */design_1.bd]
help get_bd_nets
help find_bd_objs
foreach pin {reset_gen/axi_clk_reset_gen/aux_reset_in reset_zero/dout reset_gen/axi_clk_reset_gen/mb_debug_sys_rst mdm_0/Debug_SYS_Rst} {
    puts "NETS $pin [get_bd_nets -of_objects [get_bd_pins $pin]]"
    puts "CONNECTED $pin [find_bd_objs -relation connected_to -thru_hier [get_bd_pins $pin]]"
}
exit
