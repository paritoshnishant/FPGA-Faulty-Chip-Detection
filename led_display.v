module led_display (
    input  wire [4:0]  total_count,
    input  wire [4:0]  good_count,
    input  wire [4:0]  defect_count,
    input  wire        any_result,
    input  wire        last_is_defect,

    output wire [8:0]  LEDG,
    output wire [17:0] LEDR
);
    assign LEDG[4:0]   = good_count;
    assign LEDG[7:5]   = 3'b000;
    assign LEDG[8]     = any_result & ~last_is_defect;

    assign LEDR[4:0]   = defect_count;
    assign LEDR[7:5]   = 3'b000;
    assign LEDR[12:8]  = total_count;
    assign LEDR[16:13] = 4'b0000;
    assign LEDR[17]    = any_result & last_is_defect;
endmodule
