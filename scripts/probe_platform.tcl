set root [file normalize [file join [file dirname [info script]] ..]]
create_project -in_memory -part xcsu35p-sbvb625-2-e
report_property [get_parts xcsu35p-sbvb625-2-e]
puts "SCU35_BOARDS [get_board_parts -quiet *scu35*]"
set_property ip_repo_paths [list $root/third_party/hyperbus_controller/ip_repo $root/third_party/e_uart/ip_repo] [current_project]
update_ip_catalog
create_bd_design probe
foreach {name pattern} {hb *:hyperbus_controller:* uart *:e_uart:* sysmon *:system_management_wiz:* pmc *:pmcbridge:* eth *:axi_ethernetlite:*} {
    set defs [get_ipdefs -all -filter "VLNV =~ $pattern"]
    puts "IPDEFS $name $defs"
    if {[llength $defs]} {
        if {[catch {set cell [create_bd_cell -type ip -vlnv [lindex $defs end] $name]} err]} {puts "PROBE_SKIP $err"; continue}
        puts "PINS $name [get_bd_pins -of_objects $cell]"
        puts "INTFS $name [get_bd_intf_pins -of_objects $cell]"
        foreach p [list_property $cell] {
            if {[string match CONFIG.* $p]} {puts "$name $p [get_property $p $cell]"}
        }
    }
}
exit
