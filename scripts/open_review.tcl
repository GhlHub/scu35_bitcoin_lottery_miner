set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
open_bd_design [get_files */design_1.bd]
start_gui
regenerate_bd_layout
save_bd_design
