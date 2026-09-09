set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $root/build/vivado/scu35_miner.runs/synth_1/design_1_wrapper.dcp
write_verilog -force $root/build/synth_debug.v
close_design
open_checkpoint $root/build/vivado/scu35_miner.runs/impl_1/design_1_wrapper_opt.dcp
write_verilog -force $root/build/opt_debug.v
exit
