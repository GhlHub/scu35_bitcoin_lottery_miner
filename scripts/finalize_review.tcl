set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/build/vivado/scu35_miner.xpr
set bd [get_files */design_1.bd]
open_bd_design $bd
if {![llength [get_bd_ports -quiet MII_0_tx_er]]} {
    create_bd_port -dir O MII_0_tx_er
    connect_bd_net [get_bd_pins reset_zero/dout] [get_bd_ports MII_0_tx_er]
}
source $root/scripts/audit_bd.tcl
save_bd_design
write_bd_tcl -force $root/build/scu35_miner_recreate.tcl
make_wrapper -files $bd -top
report_ip_status -file $root/logs/ip_status.rpt
foreach run [get_runs] {
    puts "RUN_STATUS $run [get_property STATUS $run] [get_property PROGRESS $run]"
    require {[get_property PROGRESS $run] eq "0%"} "Synthesis must not have started"
}
puts "FINAL_REVIEW_READY"
close_project
exit
