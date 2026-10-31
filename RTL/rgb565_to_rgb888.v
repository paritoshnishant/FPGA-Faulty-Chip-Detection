// B2: RGB565 -> RGB888 Decoder
// RGB565 packs as: [15:11]=R(5 bits) [10:5]=G(6 bits) [4:0]=B(5 bits)
// Expands each channel to 8 bits via bit-replication (not just zero-padding)
// so intensity scaling stays accurate - needed since B4's detector works
// on 8-bit grayscale/intensity values derived from these channels.

module rgb565_to_rgb888 (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] pixel_in,     // RGB565 from B1
    input  wire        pixel_valid_in,
    input  wire [8:0]  col_in,
    input  wire [7:0]  row_in,

    output reg  [7:0]  r_out,
    output reg  [7:0]  g_out,
    output reg  [7:0]  b_out,
    output reg  [8:0]  col_out,
    output reg  [7:0]  row_out,
    output reg         pixel_valid_out
);

    wire [4:0] r5 = pixel_in[15:11];
    wire [5:0] g6 = pixel_in[10:5];
    wire [4:0] b5 = pixel_in[4:0];

    // Bit-replication expansion: repeat the top bits into the new low bits
    wire [7:0] r8 = {r5, r5[4:2]};      // 5 bits -> 8 bits
    wire [7:0] g8 = {g6, g6[5:4]};      // 6 bits -> 8 bits
    wire [7:0] b8 = {b5, b5[4:2]};      // 5 bits -> 8 bits

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r_out           <= 0;
            g_out           <= 0;
            b_out           <= 0;
            col_out         <= 0;
            row_out         <= 0;
            pixel_valid_out <= 0;
        end
        else begin
            r_out           <= r8;
            g_out           <= g8;
            b_out           <= b8;
            col_out         <= col_in;
            row_out         <= row_in;
            pixel_valid_out <= pixel_valid_in;
        end
    end

endmodule
