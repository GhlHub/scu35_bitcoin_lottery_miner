# HyperRAM direct DQ datapath budgets from the selected controller's reference.
# Calibration establishes the actual CK/RWDS phase. These are routing budgets,
# not a claim that a fixed untrained external timing model is valid.
set_max_delay -datapath_only 0.800 -from [get_ports {io_hb_dq_0[0]}] -to [get_pins {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[0].u_iddr_dq/D}]
set_max_delay -datapath_only 0.800 -from [get_ports {io_hb_dq_0[1]}] -to [get_pins {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[1].u_iddr_dq/D}]
set_max_delay -datapath_only 0.800 -from [get_ports {io_hb_dq_0[2]}] -to [get_pins {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[2].u_iddr_dq/D}]
set_max_delay -datapath_only 0.800 -from [get_ports {io_hb_dq_0[3]}] -to [get_pins {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[3].u_iddr_dq/D}]
set_max_delay -datapath_only 0.800 -from [get_ports {io_hb_dq_0[4]}] -to [get_pins {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[4].u_iddr_dq/D}]
set_max_delay -datapath_only 0.800 -from [get_ports {io_hb_dq_0[5]}] -to [get_pins {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[5].u_iddr_dq/D}]
set_max_delay -datapath_only 0.800 -from [get_ports {io_hb_dq_0[6]}] -to [get_pins {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[6].u_iddr_dq/D}]
set_max_delay -datapath_only 0.800 -from [get_ports {io_hb_dq_0[7]}] -to [get_pins {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[7].u_iddr_dq/D}]

set_max_delay -datapath_only 1.700 -from [get_cells {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[0].u_oddr_dq}] -to [get_ports {io_hb_dq_0[0]}]
set_max_delay -datapath_only 1.700 -from [get_cells {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[1].u_oddr_dq}] -to [get_ports {io_hb_dq_0[1]}]
set_max_delay -datapath_only 1.700 -from [get_cells {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[2].u_oddr_dq}] -to [get_ports {io_hb_dq_0[2]}]
set_max_delay -datapath_only 1.700 -from [get_cells {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[3].u_oddr_dq}] -to [get_ports {io_hb_dq_0[3]}]
set_max_delay -datapath_only 1.700 -from [get_cells {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[4].u_oddr_dq}] -to [get_ports {io_hb_dq_0[4]}]
set_max_delay -datapath_only 1.700 -from [get_cells {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[5].u_oddr_dq}] -to [get_ports {io_hb_dq_0[5]}]
set_max_delay -datapath_only 1.700 -from [get_cells {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[6].u_oddr_dq}] -to [get_ports {io_hb_dq_0[6]}]
set_max_delay -datapath_only 1.700 -from [get_cells {design_1_i/hyperbus_controller_0/inst/u_hyperbus_phy/g_phy_ultrascale_plus.u_phy_impl/g_dq_phy[7].u_oddr_dq}] -to [get_ports {io_hb_dq_0[7]}]

# DP83867IR Rev J, sections 6.12 and 6.13 (100-Mbit MII).
# Allow 0.5 ns differential board trace uncertainty in each direction.
# Vendor EthernetLite XDC creates both 40 ns MII clocks.
set_input_delay -clock [get_clocks MII_0_rx_clk] -min 9.500 [get_ports {MII_0_rxd[*] MII_0_rx_dv MII_0_rx_er}]
set_input_delay -clock [get_clocks MII_0_rx_clk] -max 30.500 [get_ports {MII_0_rxd[*] MII_0_rx_dv MII_0_rx_er}]
set_output_delay -clock [get_clocks MII_0_tx_clk] -min -0.500 [get_ports {MII_0_txd[*] MII_0_tx_en}]
set_output_delay -clock [get_clocks MII_0_tx_clk] -max 10.500 [get_ports {MII_0_txd[*] MII_0_tx_en}]
