# Source with design_1 open, for both fresh and existing projects.
if {![llength [get_bd_cells -quiet power_iic]]} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 power_iic
    set_property CONFIG.NUM_MI 10 [get_bd_cells axi_crossbar_0]
    connect_bd_intf_net [get_bd_intf_pins axi_crossbar_0/M09_AXI] [get_bd_intf_pins power_iic/S_AXI]
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins power_iic/s_axi_aclk]
    connect_bd_net [get_bd_pins reset_gen/axi_clk_peripheral_aresetn] [get_bd_pins power_iic/s_axi_aresetn]
    set_property CONFIG.NUM_PORTS 8 [get_bd_cells ilconcat_0]
    connect_bd_net [get_bd_pins power_iic/iic2intc_irpt] [get_bd_pins ilconcat_0/In7]
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 POWER_IIC
    connect_bd_intf_net [get_bd_intf_ports POWER_IIC] [get_bd_intf_pins power_iic/IIC]
}
assign_bd_address -offset 0x40810000 -range 64K -target_address_space [get_bd_addr_spaces microblaze_0/Data] [get_bd_addr_segs power_iic/S_AXI/Reg]
set_property CONFIG.M09_A00_BASE_ADDR 0x40810000 [get_bd_cells axi_crossbar_0]
set_property CONFIG.M09_A00_ADDR_WIDTH 16 [get_bd_cells axi_crossbar_0]
