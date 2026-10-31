# Timing constraints (DE2-115) - ROM version, no SDRAM
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty

# buttons are asynchronous
set_false_path -from [get_ports {KEY[*]}]
# slow outputs: 7-segments, LCD
set_false_path -to [get_ports {HEX* LCD_*}]
