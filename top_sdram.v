// top_sdram : DE2-115 top level, 5 images stored inside the FPGA (no SDRAM, no JTAG).
//   KEY[0] = reset (active low)   KEY[1] = start (active low)
// (module name kept the same, so the Quartus project settings need no change)
module top_sdram (
    input  wire        CLOCK_50,
    input  wire [1:0]  KEY,
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    output wire        LCD_ON, LCD_BLON, LCD_RW, LCD_RS, LCD_EN,
    output wire [7:0]  LCD_DATA
);
    wire sys_clk = CLOCK_50;
    wire rst_n   = KEY[0];

    wire [17:0] ledr_core;
    wire [4:0]  lcd_total, lcd_good, lcd_defect;
    wire        lcd_any, lcd_done, lcd_err;

    assign HEX0 = 7'b1111111;   // not used

    sdram_demo_core core (
        .clk(sys_clk), .rst(~rst_n), .btn(~KEY[1]),
        .HEX0(), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
        .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7),
        .LEDG(), .LEDR(ledr_core),
        .lcd_total(lcd_total), .lcd_good(lcd_good), .lcd_defect(lcd_defect),
        .lcd_any(lcd_any), .lcd_done(lcd_done), .lcd_err(lcd_err)
    );

    lcd_display lcd (
        .clk(sys_clk), .rst(~rst_n),
        .total_count(lcd_total), .good_count(lcd_good), .defect_count(lcd_defect),
        .any_result(lcd_any), .all_done(lcd_done), .load_err(lcd_err),
        .LCD_ON(LCD_ON), .LCD_BLON(LCD_BLON), .LCD_RW(LCD_RW),
        .LCD_RS(LCD_RS), .LCD_EN(LCD_EN), .LCD_DATA(LCD_DATA)
    );
endmodule
