set_property -dict { PACKAGE_PIN H11 IOSTANDARD LVCMOS33 } [get_ports {clk}]
set_property -dict { PACKAGE_PIN K12 IOSTANDARD LVCMOS33 } [get_ports {led}]
create_clock -name sys_clk -period 20.000 [get_ports {clk}]
