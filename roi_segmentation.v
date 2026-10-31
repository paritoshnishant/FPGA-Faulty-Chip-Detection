// B3: ROI Segmentation
// ROI is defined as the full 320x240 frame for this demo (no cropping) -
// keeps the validated detector threshold (from Colab sweep) valid, since
// it was tuned against full-frame defect-pixel counts.
// Structured as its own pipeline stage (not skipped entirely) so the
// block diagram/report accurately shows a segmentation stage, and so a
// real windowed ROI could be dropped in later without restructuring B4.

module roi_segmentation #(
    parameter ROI_X_MIN = 0,
    parameter ROI_X_MAX = 319,
    parameter ROI_Y_MIN = 0,
    parameter ROI_Y_MAX = 239
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  r_in,
    input  wire [7:0]  g_in,
    input  wire [7:0]  b_in,
    input  wire [8:0]  col_in,
    input  wire [7:0]  row_in,
    input  wire        pixel_valid_in,

    output reg  [7:0]  r_out,
    output reg  [7:0]  g_out,
    output reg  [7:0]  b_out,
    output reg  [8:0]  col_out,
    output reg  [7:0]  row_out,
    output reg         in_roi,        // 1 if pixel is inside the ROI window
    output reg         pixel_valid_out
);

    wire pixel_in_roi = (col_in >= ROI_X_MIN) && (col_in <= ROI_X_MAX) &&
                         (row_in >= ROI_Y_MIN) && (row_in <= ROI_Y_MAX);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r_out <= 0; g_out <= 0; b_out <= 0;
            col_out <= 0; row_out <= 0;
            in_roi <= 0; pixel_valid_out <= 0;
        end else begin
            r_out   <= r_in;
            g_out   <= g_in;
            b_out   <= b_in;
            col_out <= col_in;
            row_out <= row_in;
            in_roi  <= pixel_in_roi;
            pixel_valid_out <= pixel_valid_in;
        end
    end

endmodule
