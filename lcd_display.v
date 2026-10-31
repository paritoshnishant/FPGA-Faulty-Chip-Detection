// ============================================================================
// lcd_display : drives the DE2-115 16x2 character LCD (HD44780, 8-bit mode)
//   Line 1:  TOTAL:20 GOOD:03
//   Line 2:  DEFECT:17 DONE        (status: READY / RUN / DONE / ERR)
// It rewrites both lines forever (~every 4 ms) so the text always follows the
// counters.  clk = 50 MHz.
// ============================================================================
module lcd_display (
    input  wire       clk,
    input  wire       rst,           // active high
    input  wire [4:0] total_count,
    input  wire [4:0] good_count,
    input  wire [4:0] defect_count,
    input  wire       any_result,
    input  wire       all_done,
    input  wire       load_err,

    output wire       LCD_ON,
    output wire       LCD_BLON,
    output wire       LCD_RW,
    output reg        LCD_RS,
    output reg        LCD_EN,
    output reg  [7:0] LCD_DATA
);
    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;   // backlight (not wired on some board revisions)
    assign LCD_RW   = 1'b0;   // write only

    // ---------- text ----------
    function [7:0] digit(input [3:0] v); digit = 8'h30 + v; endfunction

    wire [3:0] t_t = total_count  / 10, t_o = total_count  % 10;
    wire [3:0] g_t = good_count   / 10, g_o = good_count   % 10;
    wire [3:0] d_t = defect_count / 10, d_o = defect_count % 10;

    function [7:0] char_at(input [4:0] i);
        begin
            case (i)
                // line 1: "TOTAL:20 GOOD:03"
                0:  char_at = "T";  1:  char_at = "O";  2:  char_at = "T";  3:  char_at = "A";
                4:  char_at = "L";  5:  char_at = ":";  6:  char_at = digit(t_t);
                7:  char_at = digit(t_o);  8:  char_at = " ";
                9:  char_at = "G";  10: char_at = "O";  11: char_at = "O";  12: char_at = "D";
                13: char_at = ":";  14: char_at = digit(g_t);  15: char_at = digit(g_o);
                // line 2: "DEFECT:17 " + status
                16: char_at = "D";  17: char_at = "E";  18: char_at = "F";  19: char_at = "E";
                20: char_at = "C";  21: char_at = "T";  22: char_at = ":";
                23: char_at = digit(d_t);  24: char_at = digit(d_o);  25: char_at = " ";
                26: char_at = load_err ? "E" : all_done ? "D" : any_result ? "R" : "R";
                27: char_at = load_err ? "R" : all_done ? "O" : any_result ? "U" : "E";
                28: char_at = load_err ? "R" : all_done ? "N" : any_result ? "N" : "A";
                29: char_at = load_err ? " " : all_done ? "E" : any_result ? " " : "D";
                30: char_at = load_err ? " " : all_done ? " " : any_result ? " " : "Y";
                default: char_at = " ";
            endcase
        end
    endfunction

    // ---------- init sequence: command and wait (clocks) ----------
    function [7:0]  init_cmd (input [2:0] s);
        case (s) 0: init_cmd = 8'h38; 1: init_cmd = 8'h38; 2: init_cmd = 8'h38;
                 3: init_cmd = 8'h0C; 4: init_cmd = 8'h01; default: init_cmd = 8'h06; endcase
    endfunction
    function [19:0] init_wait(input [2:0] s);
        case (s) 0: init_wait = 250000; 1: init_wait = 5000; 2: init_wait = 5000;
                 3: init_wait = 3000;   4: init_wait = 100000; default: init_wait = 3000; endcase
    endfunction

    // ---------- FSM ----------
    localparam ST_PWR = 0, ST_LOAD = 1, ST_SETUP = 2, ST_EN = 3, ST_WAIT = 4;
    reg [2:0]  state;
    reg [20:0] cnt;
    reg [19:0] wait_len;
    reg        in_init;
    reg [2:0]  istep;
    reg [5:0]  lstep;          // 0: cmd 0x80, 1..16 chars 0..15, 17: cmd 0xC0, 18..33 chars 16..31

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_PWR; cnt <= 0; LCD_EN <= 0; LCD_RS <= 0; LCD_DATA <= 0;
            in_init <= 1; istep <= 0; lstep <= 0; wait_len <= 0;
        end else begin
            case (state)
                ST_PWR: begin   // 20 ms power-up
                    if (cnt == 1_000_000) begin cnt <= 0; state <= ST_LOAD; end
                    else cnt <= cnt + 1'b1;
                end

                ST_LOAD: begin
                    cnt <= 0;
                    if (in_init) begin
                        LCD_RS <= 0; LCD_DATA <= init_cmd(istep); wait_len <= init_wait(istep);
                    end else if (lstep == 0)  begin LCD_RS <= 0; LCD_DATA <= 8'h80; wait_len <= 3000; end
                    else if (lstep == 17)     begin LCD_RS <= 0; LCD_DATA <= 8'hC0; wait_len <= 3000; end
                    else if (lstep < 17)      begin LCD_RS <= 1; LCD_DATA <= char_at(lstep - 1);  wait_len <= 3000; end
                    else                      begin LCD_RS <= 1; LCD_DATA <= char_at(lstep - 2);  wait_len <= 3000; end
                    state <= ST_SETUP;
                end

                ST_SETUP: begin  // data/RS stable before E rises
                    if (cnt == 5) begin LCD_EN <= 1; cnt <= 0; state <= ST_EN; end
                    else cnt <= cnt + 1'b1;
                end

                ST_EN: begin     // E high ~500 ns
                    if (cnt == 25) begin LCD_EN <= 0; cnt <= 0; state <= ST_WAIT; end
                    else cnt <= cnt + 1'b1;
                end

                ST_WAIT: begin
                    if (cnt >= wait_len) begin
                        cnt <= 0; state <= ST_LOAD;
                        if (in_init) begin
                            if (istep == 5) begin in_init <= 0; lstep <= 0; end
                            else istep <= istep + 1'b1;
                        end else begin
                            if (lstep == 33) lstep <= 0; else lstep <= lstep + 1'b1;
                        end
                    end else cnt <= cnt + 1'b1;
                end
                default: state <= ST_PWR;
            endcase
        end
    end
endmodule
