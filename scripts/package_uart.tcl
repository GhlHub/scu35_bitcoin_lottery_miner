# Refresh upstream packaging for the supported Spartan UltraScale+ target.
# The downloaded source remains unchanged; derived packaging lives under build/.
set root [file normalize [file join [file dirname [info script]] ..]]
set dest $root/build/ip_repo/e_uart
if {[file exists $dest]} {error "Derived UART package already exists: $dest"}
file mkdir [file dirname $dest]
file copy $root/third_party/e_uart/ip_repo/e_uart $dest
ipx::open_core $dest/component.xml
set core [ipx::current_core]
set_property vendor github.com $core
set_property supported_families {spartanuplus Production} $core
ipx::update_checksums $core
ipx::save_core $core
exit
