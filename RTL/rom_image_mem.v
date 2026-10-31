// rom_image_mem : replaces sdram_image_mem.
// 5 images are stored inside the FPGA (red channel only, 5 bit per pixel).
// Same stream outputs as before, so B2 / B3 / B4 are not changed.
module rom_image_mem #(
    parameter WIDTH  = 320,
    parameter HEIGHT = 240
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        go,            // 1-clock pulse: start streaming one image
    input  wire [2:0]  img_sel,       // 0..4

    output reg         busy,
    output wire [15:0] pixel_out,     // RGB565, only red is real
    output reg  [8:0]  col,
    output reg  [7:0]  row,
    output reg         pixel_valid,
    output reg         frame_done
);
    localparam TOTAL = WIDTH * HEIGHT;
    localparam S_IDLE = 1'b0, S_STREAM = 1'b1;

    reg        state;
    reg [16:0] addr;
    reg [8:0]  next_col;
    reg [7:0]  next_row;
    reg [2:0]  sel_q;

    // ---- 5 ROMs, each starts from its own .mif file ----
    (* ramstyle = "M9K", ram_init_file = "chip05.mif" *) reg [4:0] mem0 [0:TOTAL-1];
    (* ramstyle = "M9K", ram_init_file = "chip05.mif" *) reg [4:0] mem1 [0:TOTAL-1];
    (* ramstyle = "M9K", ram_init_file = "chip05.mif" *) reg [4:0] mem2 [0:TOTAL-1];
    (* ramstyle = "M9K", ram_init_file = "chip01.mif" *) reg [4:0] mem3 [0:TOTAL-1];
    (* ramstyle = "M9K", ram_init_file = "chip05.mif" *) reg [4:0] mem4 [0:TOTAL-1];

    reg [4:0] q0, q1, q2, q3, q4;
    wire re = (state == S_STREAM) && !frame_done;

    always @(posedge clk) if (re) q0 <= mem0[addr];
    always @(posedge clk) if (re) q1 <= mem1[addr];
    always @(posedge clk) if (re) q2 <= mem2[addr];
    always @(posedge clk) if (re) q3 <= mem3[addr];
    always @(posedge clk) if (re) q4 <= mem4[addr];

    reg [4:0] red;
    always @(*) begin
        case (sel_q)
            3'd0:    red = q0;
            3'd1:    red = q1;
            3'd2:    red = q2;
            3'd3:    red = q3;
            default: red = q4;
        endcase
    end
    assign pixel_out = {red, 11'b0};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE; busy <= 0; addr <= 0; sel_q <= 0;
            next_col <= 0; next_row <= 0; col <= 0; row <= 0;
            pixel_valid <= 0; frame_done <= 0;
        end
        else if (go && state == S_IDLE) begin
            busy <= 1; frame_done <= 0; pixel_valid <= 0;
            sel_q <= img_sel; addr <= 0;
            next_col <= 0; next_row <= 0; col <= 0; row <= 0;
            state <= S_STREAM;
        end
        else begin
            case (state)
                S_IDLE: pixel_valid <= 0;
                S_STREAM: begin
                    if (!frame_done) begin
                        col         <= next_col;
                        row         <= next_row;
                        pixel_valid <= 1'b1;
                        if (next_col == WIDTH-1) begin
                            next_col <= 0;
                            if (next_row == HEIGHT-1) frame_done <= 1'b1;
                            else next_row <= next_row + 1'b1;
                        end else next_col <= next_col + 1'b1;
                        addr <= addr + 1'b1;
                    end else begin
                        pixel_valid <= 1'b0;
                        busy        <= 1'b0;
                        state       <= S_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
