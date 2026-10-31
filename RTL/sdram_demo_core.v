// ============================================================================
// sdram_demo_core : everything except the Platform Designer system.
//   KEY[1] -> processes all NUM_IMAGES images stored in on-chip ROM, one after the
//   other, and shows TOTAL / GOOD / DEFECT on the 7-segments and LEDs.
//   Image n = chip0(n+1).mif inside rom_image_mem.
// ============================================================================
module sdram_demo_core #(
    parameter NUM_IMAGES   = 5,
    parameter PAUSE_CYCLES = 25_000_000    // ~0.5 s between images (clk = 50 MHz)
)(
    input  wire        clk,
    input  wire        rst,           // active high
    input  wire        btn,           // active high, start

    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    output wire [8:0]  LEDG,
    output wire [17:0] LEDR,

    // tally / status for the LCD
    output wire [4:0]  lcd_total,
    output wire [4:0]  lcd_good,
    output wire [4:0]  lcd_defect,
    output wire        lcd_any,
    output wire        lcd_done,
    output wire        lcd_err
);

    // ---- button edge ----
    reg btn_prev;
    wire btn_edge = btn && !btn_prev;
    always @(posedge clk or posedge rst)
        if (rst) btn_prev <= 0; else btn_prev <= btn;

    // ---- control ----
    localparam S_IDLE = 0, S_START = 1, S_RUN = 2, S_PAUSE = 3, S_DONE = 4;
    reg [2:0]  state;
    reg [4:0]  img_idx;
    reg        go, count_reset;
    reg [25:0] pause_cnt;
    reg [4:0]  total_count, good_count, defect_count;


    // ---- B1 replacement ----
    wire [15:0] pixel_out;
    wire [8:0]  col;
    wire [7:0]  row;
    wire        pixel_valid, frame_done, busy;
    wire        load_err = 1'b0;   // no SDRAM any more, so no load error

    rom_image_mem #(.WIDTH(320), .HEIGHT(240)) b1 (
        .clk(clk), .rst(rst), .go(go), .img_sel(img_idx[2:0]),
        .busy(busy),
        .pixel_out(pixel_out), .col(col), .row(row),
        .pixel_valid(pixel_valid), .frame_done(frame_done)
    );

    // ---- B2 -> B3 -> B4 (unchanged) ----
    wire [7:0] r_b2, g_b2, b_b2;
    wire [8:0] col_b2;  wire [7:0] row_b2;  wire pixel_valid_b2;

    rgb565_to_rgb888 b2 (
        .clk(clk), .rst(rst),
        .pixel_in(pixel_out), .pixel_valid_in(pixel_valid),
        .col_in(col), .row_in(row),
        .r_out(r_b2), .g_out(g_b2), .b_out(b_b2),
        .col_out(col_b2), .row_out(row_b2),
        .pixel_valid_out(pixel_valid_b2)
    );

    wire [7:0] r_b3, g_b3, b_b3;
    wire [8:0] col_b3;  wire [7:0] row_b3;  wire in_roi, pixel_valid_b3;

    roi_segmentation b3 (
        .clk(clk), .rst(rst),
        .r_in(r_b2), .g_in(g_b2), .b_in(b_b2),
        .col_in(col_b2), .row_in(row_b2), .pixel_valid_in(pixel_valid_b2),
        .r_out(r_b3), .g_out(g_b3), .b_out(b_b3),
        .col_out(col_b3), .row_out(row_b3),
        .in_roi(in_roi), .pixel_valid_out(pixel_valid_b3)
    );

    wire [16:0] defect_count_raw;
    wire        result_valid, is_defect;

    defect_detector #(.WIDTH(320), .HEIGHT(240), .DELTA(10), .COUNT_THRESHOLD(360)) b4 (
        .clk(clk), .rst(rst), .count_reset(count_reset),
        .r_in(r_b3), .col_in(col_b3), .row_in(row_b3),
        .in_roi(in_roi), .pixel_valid_in(pixel_valid_b3),
        .frame_done_in(frame_done),
        .defect_pixel_count(defect_count_raw),
        .result_valid(result_valid), .is_defect(is_defect)
    );

    // ---- FSM: run all images ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE; img_idx <= 0; go <= 0; count_reset <= 0; pause_cnt <= 0;
            total_count <= 0; good_count <= 0; defect_count <= 0;
        end else begin
            go <= 0; count_reset <= 0;
            case (state)
                S_IDLE:  if (btn_edge) state <= S_START;

                S_START: begin go <= 1'b1; count_reset <= 1'b1; state <= S_RUN; end

                S_RUN: begin
                    if (result_valid) begin
                        total_count <= total_count + 1'b1;
                        if (is_defect) defect_count <= defect_count + 1'b1;
                        else           good_count   <= good_count   + 1'b1;
                        if (img_idx == NUM_IMAGES-1) state <= S_DONE;
                        else begin
                            img_idx <= img_idx + 1'b1;
                            pause_cnt <= 0;
                            state <= S_PAUSE;
                        end
                    end
                    else if (load_err) state <= S_DONE;   // stop, error LED shows
                end

                S_PAUSE: begin
                    if (pause_cnt >= PAUSE_CYCLES) state <= S_START;
                    else pause_cnt <= pause_cnt + 1'b1;
                end

                S_DONE: ;
                default: state <= S_IDLE;
            endcase
        end
    end

    // ---- latest verdict for the LEDs ----
    reg any_result, last_is_defect;
    always @(posedge clk or posedge rst) begin
        if (rst) begin any_result <= 0; last_is_defect <= 0; end
        else if (result_valid) begin any_result <= 1'b1; last_is_defect <= is_defect; end
    end

    // ---- 7-segment: two digits for TOTAL and DEFECT, one for GOOD ----
    wire [7:0] total_d  = total_count;
    wire [7:0] defect_d = defect_count;
    wire [7:0] good_d   = good_count;

    wire [3:0] total_tens  = total_d  / 10;
    wire [3:0] total_ones  = total_d  % 10;
    wire [3:0] defect_tens = defect_d / 10;
    wire [3:0] defect_ones = defect_d % 10;
    wire [3:0] good_tens   = good_d   / 10;
    wire [3:0] good_ones   = good_d   % 10;

    seg7_decoder d_total_tens  (.value(total_tens),  .seg(HEX7));
    seg7_decoder d_total_ones  (.value(total_ones),  .seg(HEX6));
    seg7_decoder d_good_ones   (.value(good_ones),   .seg(HEX4));
    seg7_decoder d_defect_tens (.value(defect_tens), .seg(HEX2));
    seg7_decoder d_defect_ones (.value(defect_ones), .seg(HEX1));

    assign HEX5 = 7'b0010001;   // 'G'
    assign HEX3 = 7'b0100001;   // 'd'
    assign HEX0 = 7'b1111111;

    // ---- LEDs ----
    wire [8:0]  ledg_w;
    wire [17:0] ledr_w;
    led_display leds (
        .total_count(total_count), .good_count(good_count), .defect_count(defect_count),
        .any_result(any_result), .last_is_defect(last_is_defect),
        .LEDG(ledg_w), .LEDR(ledr_w)
    );

    wire all_done = (state == S_DONE) && !load_err;
    assign LEDG = ledg_w | {1'b0, all_done, 7'b0};   // LEDG[7] = all images finished
    assign LEDR = ledr_w | {1'b0, load_err, 16'b0};  // LEDR[16] = SDRAM read error

    assign lcd_total  = total_count;
    assign lcd_good   = good_count;
    assign lcd_defect = defect_count;
    assign lcd_any    = any_result;
    assign lcd_done   = all_done;
    assign lcd_err    = load_err;

endmodule
