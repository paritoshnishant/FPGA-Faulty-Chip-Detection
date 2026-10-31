// ============================================================================
// B4: defect detector  -  PIPELINED version (same ports, same results as the
//     original single-cycle version, but every stage is short enough for 50 MHz).
//
//   The original computed the 25-pixel window sum, /25, |centre-avg| and the
//   compare in ONE clock cycle - far too much logic for 20 ns on hardware.
//
//   Pipeline (one pixel per clock, valid flags travel with the data):
//     A  read the 4 stored rows above for this column      (line memory, 320 x 32 bit)
//     B  column sum of the 5 pixels; write the memory; shift the window
//     C  add the 5 column sums           -> window total
//     D  total * 5243                    -> (total / 25 after >>17, exact for total <= 6375)
//     E  |centre - average|, compare with DELTA
//     F  count
//   The result is released 16 clocks after frame_done so the last pixels are counted.
// ============================================================================
module defect_detector #(
    parameter WIDTH           = 320,
    parameter HEIGHT          = 240,
    parameter DELTA           = 10,
    parameter COUNT_THRESHOLD = 360
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        count_reset,   // pulse to clear defect_pixel_count before a new image
    input  wire [7:0]  r_in,
    input  wire [8:0]  col_in,
    input  wire [7:0]  row_in,
    input  wire        in_roi,
    input  wire        pixel_valid_in,
    input  wire        frame_done_in,

    output reg  [16:0] defect_pixel_count,
    output reg         result_valid,
    output reg         is_defect
);

    // ---------------- stage A : line memory read ----------------
    // word per column = { row-4 , row-3 , row-2 , row-1 }  (8 bits each)
    (* ramstyle = "M9K" *) reg [31:0] lmem [0:WIDTH-1];
    reg [31:0] q;

    reg [7:0]  r_d;
    reg [8:0]  col_d;
    reg [7:0]  row_d;
    reg        roi_d, valid_d;

    always @(posedge clk) q <= lmem[col_in];          // plain registered read

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r_d <= 0; col_d <= 0; row_d <= 0; roi_d <= 0; valid_d <= 0;
        end else begin
            r_d <= r_in; col_d <= col_in; row_d <= row_in;
            roi_d <= in_roi; valid_d <= pixel_valid_in;
        end
    end

    // ---------------- stage B : column sum, write-back, window shift ----------------
    wire [7:0]  v0 = r_d;
    wire [7:0]  v1 = q[7:0];
    wire [7:0]  v2 = q[15:8];
    wire [7:0]  v3 = q[23:16];
    wire [7:0]  v4 = q[31:24];
    wire [10:0] cs_new = v0 + v1 + v2 + v3 + v4;      // max 1275

    always @(posedge clk)
        if (valid_d) lmem[col_d] <= {q[23:0], r_d};

    reg [10:0] csr0, csr1, csr2, csr3, csr4;          // column sums, csr0 = newest
    reg [7:0]  c2r0, c2r1, c2r2;                      // row-2 pixel of the last 3 columns
    reg        ready_c, roi_c, valid_c;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            csr0 <= 0; csr1 <= 0; csr2 <= 0; csr3 <= 0; csr4 <= 0;
            c2r0 <= 0; c2r1 <= 0; c2r2 <= 0;
            ready_c <= 0; roi_c <= 0; valid_c <= 0;
        end else begin
            valid_c <= valid_d;
            ready_c <= (col_d >= 4) && (row_d >= 4);
            roi_c   <= roi_d;
            if (valid_d) begin
                csr0 <= cs_new; csr1 <= csr0; csr2 <= csr1; csr3 <= csr2; csr4 <= csr3;
                c2r0 <= v2;     c2r1 <= c2r0; c2r2 <= c2r1;
            end
        end
    end

    // ---------------- stage C : window total ----------------
    reg [12:0] total_q;
    reg [7:0]  centre_q;
    reg        act_q;
    always @(posedge clk or posedge rst) begin
        if (rst) begin total_q <= 0; centre_q <= 0; act_q <= 0; end
        else begin
            total_q  <= csr0 + csr1 + csr2 + csr3 + csr4;   // max 6375
            centre_q <= c2r2;
            act_q    <= valid_c & ready_c & roi_c;
        end
    end

    // ---------------- stage D : divide by 25 ----------------
    reg [25:0] prod_q;
    reg [7:0]  centre_q2;
    reg        act_q2;
    always @(posedge clk or posedge rst) begin
        if (rst) begin prod_q <= 0; centre_q2 <= 0; act_q2 <= 0; end
        else begin
            prod_q    <= total_q * 13'd5243;
            centre_q2 <= centre_q;
            act_q2    <= act_q;
        end
    end
    wire [7:0] avg = prod_q[24:17];                       // = total / 25

    // ---------------- stage E : deviation and compare ----------------
    reg        hit_q;
    wire [7:0] dev = (centre_q2 > avg) ? (centre_q2 - avg) : (avg - centre_q2);
    always @(posedge clk or posedge rst) begin
        if (rst) hit_q <= 0;
        else     hit_q <= act_q2 && (dev > DELTA);
    end

    // ---------------- stage F : count ----------------
    always @(posedge clk or posedge rst) begin
        if (rst) defect_pixel_count <= 0;
        else if (count_reset) defect_pixel_count <= 0;
        else if (hit_q) defect_pixel_count <= defect_pixel_count + 1'b1;
    end

    // ---------------- result: 16 clocks after frame_done rises ----------------
    reg       fd_prev;
    reg [4:0] fd_cnt;
    reg       fd_run;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fd_prev <= 0; fd_cnt <= 0; fd_run <= 0; result_valid <= 0; is_defect <= 0;
        end else begin
            fd_prev      <= frame_done_in;
            result_valid <= 1'b0;
            if (frame_done_in && !fd_prev) begin fd_run <= 1'b1; fd_cnt <= 0; end
            else if (fd_run) begin
                fd_cnt <= fd_cnt + 1'b1;
                if (fd_cnt == 5'd15) begin
                    fd_run       <= 1'b0;
                    is_defect    <= (defect_pixel_count > COUNT_THRESHOLD);
                    result_valid <= 1'b1;
                end
            end
        end
    end
endmodule