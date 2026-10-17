`default_nettype none

module tt_um_peakpachi_flappy_bird (
    input  wire [7:0] ui_in,    // dedicated inputs
    output wire [7:0] uo_out,   // dedicated outputs
    input  wire [7:0] uio_in,   // bidirectional pins, input path
    output wire [7:0] uio_out,  // bidirectional pins, output path
    output wire [7:0] uio_oe,   // bidirectional pins, 1 = drive
    input  wire       ena,      // high when the design is powered, ignore
    input  wire       clk,      // clock
    input  wire       rst_n     // reset, active low
);
    wire        hsync, vsync, active, frame;
    wire [9:0]  x, y;
    wire [5:0]  rgb;
    wire        speaker;

    vga_sync vga (.clk(clk), .rst_n(rst_n), .hsync(hsync), .vsync(vsync), .active(active), .x(x), .y(y), .frame(frame));

    game_core core (
        .clk(clk), .rst_n(rst_n),
        .left(ui_in[2]), 
        .x(x), .y(y), .active(active), .frame(frame),
        .rgb(rgb),
        .speaker(speaker) 
    );

    // TinyVGA PMOD pin order
    assign uo_out = {hsync, rgb[0], rgb[2], rgb[4], vsync, rgb[1], rgb[3], rgb[5]};
    
    // Route speaker to pin 7
    assign uio_out = {speaker, 7'b0000000};
    assign uio_oe  = {1'b1,    7'b0000000}; 

    // Unused wires
    wire _unused = &{ena, uio_in, ui_in[7:3], ui_in[1:0], 1'b0};
    
endmodule`default_nettype none

`default_nettype none

module game_core #(
    parameter DB = 500000    
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       left,      // ui_in[2] from top module (Button 3)
    input  wire [9:0] x,         
    input  wire [9:0] y,         
    input  wire       active,    
    input  wire       frame,     
    output wire [5:0] rgb,
    output wire       speaker    
);

    localparam [9:0] BIRD_X     = 10'd160; 
    localparam [9:0] BIRD_SIZE  = 10'd16;  
    localparam [9:0] PIPE_W     = 10'd48;  
    localparam [9:0] GAP_H      = 10'd130; 
    
    localparam signed [6:0] JUMP_VEL = -7'sd8; 
    localparam signed [6:0] GRAVITY  = 7'sd1;

    // 1. Button Handling
    wire flap_raw = left;
    wire flap_clean;
    reg  flap_last;
    
    ip_debounce #(.N(DB)) db_flap (.clk(clk), .rst_n(rst_n), .noisy(flap_raw), .clean(flap_clean));
    always @(posedge clk) flap_last <= flap_clean;
    
    wire jump_pulse = flap_clean & ~flap_last; 
    reg jump_pending;
    always @(posedge clk) begin
        if (!rst_n) jump_pending <= 1'b0;
        else if (jump_pulse) jump_pending <= 1'b1;
        else if (frame) jump_pending <= 1'b0;
    end

    // 2. High-Speed Random Number Generator 
    reg [7:0] rand_y;
    always @(posedge clk) begin
        if (rand_y >= 8'd180) rand_y <= 8'd0;
        else rand_y <= rand_y + 1'b1;
    end

    // 3. Game State Registers
    reg [9:0] bird_y;
    reg signed [6:0] velocity;
    
    reg [9:0] pipe1_x, pipe1_gap_y;
    reg [9:0] pipe2_x, pipe2_gap_y;
    reg       pipe1_passed, pipe2_passed;
    
    reg [3:0] score_tens, score_ones;
    reg [3:0] h_score_tens, h_score_ones; 
    reg       game_over;

    wire signed [10:0] bird_y_11 = {1'b0, bird_y};
    wire signed [10:0] vel_11    = {{4{velocity[6]}}, velocity};
    wire signed [10:0] next_y    = bird_y_11 + vel_11;

    wire [9:0] pipe_speed = 10'd3 + {6'd0, score_tens};
    wire [9:0] rand_y_10  = {2'b00, rand_y};

    wire game_restart = game_over && (bird_y >= 10'd480 - BIRD_SIZE) && jump_pending;

    // 4. Main Game Loop
    always @(posedge clk) begin
        if (!rst_n) begin
            bird_y       <= 10'd240;
            velocity     <= 7'sd0;
            pipe1_x      <= 10'd640;
            pipe2_x      <= 10'd960;
            pipe1_gap_y  <= 10'd160;
            pipe2_gap_y  <= 10'd220;
            pipe1_passed <= 1'b0;
            pipe2_passed <= 1'b0;
            score_tens   <= 4'd0;
            score_ones   <= 4'd0;
            h_score_tens <= 4'd0;
            h_score_ones <= 4'd0;
            game_over    <= 1'b0;
        end else if (frame) begin

            // Single driver for game_over: crash / ground contact is set here.
            // The restart branch below clears it again, so a restart still wins.
            if (crash1 || crash2 || (bird_y >= 10'd480 - BIRD_SIZE)) game_over <= 1'b1;

            if ((score_tens > h_score_tens) || ((score_tens == h_score_tens) && (score_ones > h_score_ones))) begin
                h_score_tens <= score_tens;
                h_score_ones <= score_ones;
            end

            if (game_over) begin
                if (velocity < 7'sd15) velocity <= velocity + GRAVITY;
                
                if (next_y > 10'd480 - BIRD_SIZE) bird_y <= 10'd480 - BIRD_SIZE;
                else bird_y <= next_y[9:0];

                if (game_restart) begin
                    bird_y       <= 10'd240;
                    velocity     <= 7'sd0;
                    pipe1_x      <= 10'd640;
                    pipe2_x      <= 10'd960;
                    pipe1_passed <= 1'b0;
                    pipe2_passed <= 1'b0;
                    score_tens   <= 4'd0;
                    score_ones   <= 4'd0;
                    game_over    <= 1'b0;
                end
            end else begin
                if (jump_pending) velocity <= JUMP_VEL;
                else if (velocity < 7'sd15) velocity <= velocity + GRAVITY;
                
                if (next_y < 0) bird_y <= 10'd0;
                else if (next_y > 10'd480 - BIRD_SIZE) bird_y <= 10'd480 - BIRD_SIZE;
                else bird_y <= next_y[9:0];
                
                if (pipe1_x < pipe_speed) begin
                    pipe1_x <= 10'd640;
                    pipe1_gap_y <= 10'd50 + rand_y_10;
                    pipe1_passed <= 1'b0;
                end else pipe1_x <= pipe1_x - pipe_speed;

                if (pipe2_x < pipe_speed) begin
                    pipe2_x <= 10'd640;
                    pipe2_gap_y <= 10'd50 + rand_y_10;
                    pipe2_passed <= 1'b0;
                end else pipe2_x <= pipe2_x - pipe_speed;

                if ((!pipe1_passed && (pipe1_x + PIPE_W < BIRD_X)) || 
                    (!pipe2_passed && (pipe2_x + PIPE_W < BIRD_X))) begin
                    
                    if (score_ones == 4'd9) begin
                        score_ones <= 4'd0;
                        if (score_tens != 4'd9) score_tens <= score_tens + 4'd1;
                    end else score_ones <= score_ones + 4'd1;
                    
                    if (!pipe1_passed && (pipe1_x + PIPE_W < BIRD_X)) pipe1_passed <= 1'b1;
                    if (!pipe2_passed && (pipe2_x + PIPE_W < BIRD_X)) pipe2_passed <= 1'b1;
                end
            end
        end
    end

    // 5. Collision Detection
    wire [9:0] bot_pipe1_y = pipe1_gap_y + GAP_H;
    wire [9:0] bot_pipe1_h = 10'd480 - bot_pipe1_y;
    wire [9:0] bot_pipe2_y = pipe2_gap_y + GAP_H;
    wire [9:0] bot_pipe2_h = 10'd480 - bot_pipe2_y;

    wire crash1 = (BIRD_X + BIRD_SIZE > pipe1_x) && (BIRD_X < pipe1_x + PIPE_W) &&
                  ((bird_y < pipe1_gap_y) || (bird_y + BIRD_SIZE > bot_pipe1_y));
                  
    wire crash2 = (BIRD_X + BIRD_SIZE > pipe2_x) && (BIRD_X < pipe2_x + PIPE_W) &&
                  ((bird_y < pipe2_gap_y) || (bird_y + BIRD_SIZE > bot_pipe2_y));

    // 6. Graphics Hitboxes
    wire bird_hit, t_p1_hit, b_p1_hit, t_p2_hit, b_p2_hit;
    ip_rect bird_rect (.x(x), .y(y), .rx(BIRD_X), .ry(bird_y), .rw(BIRD_SIZE), .rh(BIRD_SIZE), .hit(bird_hit));
    ip_rect t_p1 (.x(x), .y(y), .rx(pipe1_x), .ry(10'd0),       .rw(PIPE_W), .rh(pipe1_gap_y), .hit(t_p1_hit));
    ip_rect b_p1 (.x(x), .y(y), .rx(pipe1_x), .ry(bot_pipe1_y), .rw(PIPE_W), .rh(bot_pipe1_h), .hit(b_p1_hit));
    ip_rect t_p2 (.x(x), .y(y), .rx(pipe2_x), .ry(10'd0),       .rw(PIPE_W), .rh(pipe2_gap_y), .hit(t_p2_hit));
    ip_rect b_p2 (.x(x), .y(y), .rx(pipe2_x), .ry(bot_pipe2_y), .rw(PIPE_W), .rh(bot_pipe2_h), .hit(b_p2_hit));
    wire pipe_hit = t_p1_hit | b_p1_hit | t_p2_hit | b_p2_hit;

    // 7. SCORE Rendering
    wire in_tens = (x >= 10'd292) && (x < 10'd316) && (y >= 10'd32) && (y < 10'd72);
    wire in_ones = (x >= 10'd324) && (x < 10'd348) && (y >= 10'd32) && (y < 10'd72);
    wire [9:0] xt = x - 10'd292;
    wire [9:0] xo = x - 10'd324;
    wire [9:0] y_rel = y - 10'd32;
    wire [3:0] t_bit = 4'd14 - ({1'b0, y_rel[5:3]} * 4'd3) - {2'b00, xt[4:3]};
    wire [3:0] o_bit = 4'd14 - ({1'b0, y_rel[5:3]} * 4'd3) - {2'b00, xo[4:3]};

    wire in_h_tens = (x >= 10'd560) && (x < 10'd584) && (y >= 10'd32) && (y < 10'd72);
    wire in_h_ones = (x >= 10'd592) && (x < 10'd616) && (y >= 10'd32) && (y < 10'd72);
    wire [9:0] hxt = x - 10'd560;
    wire [9:0] hxo = x - 10'd592;
    wire [3:0] ht_bit = 4'd14 - ({1'b0, y_rel[5:3]} * 4'd3) - {2'b00, hxt[4:3]};
    wire [3:0] ho_bit = 4'd14 - ({1'b0, y_rel[5:3]} * 4'd3) - {2'b00, hxo[4:3]};
    
    reg [14:0] tens_font, ones_font, h_tens_font, h_ones_font;
    always @(*) begin
        case(score_tens)
            4'd0: tens_font = 15'b111_101_101_101_111; 4'd1: tens_font = 15'b010_110_010_010_111;
            4'd2: tens_font = 15'b111_001_111_100_111; 4'd3: tens_font = 15'b111_001_111_001_111;
            4'd4: tens_font = 15'b101_101_111_001_001; 4'd5: tens_font = 15'b111_100_111_001_111;
            4'd6: tens_font = 15'b111_100_111_101_111; 4'd7: tens_font = 15'b111_001_001_001_001;
            4'd8: tens_font = 15'b111_101_111_101_111; 4'd9: tens_font = 15'b111_101_111_001_111;
            default: tens_font = 15'b0;
        endcase
        case(score_ones)
            4'd0: ones_font = 15'b111_101_101_101_111; 4'd1: ones_font = 15'b010_110_010_010_111;
            4'd2: ones_font = 15'b111_001_111_100_111; 4'd3: ones_font = 15'b111_001_111_001_111;
            4'd4: ones_font = 15'b101_101_111_001_001; 4'd5: ones_font = 15'b111_100_111_001_111;
            4'd6: ones_font = 15'b111_100_111_101_111; 4'd7: ones_font = 15'b111_001_001_001_001;
            4'd8: ones_font = 15'b111_101_111_101_111; 4'd9: ones_font = 15'b111_101_111_001_111;
            default: ones_font = 15'b0;
        endcase
        case(h_score_tens)
            4'd0: h_tens_font = 15'b111_101_101_101_111; 4'd1: h_tens_font = 15'b010_110_010_010_111;
            4'd2: h_tens_font = 15'b111_001_111_100_111; 4'd3: h_tens_font = 15'b111_001_111_001_111;
            4'd4: h_tens_font = 15'b101_101_111_001_001; 4'd5: h_tens_font = 15'b111_100_111_001_111;
            4'd6: h_tens_font = 15'b111_100_111_101_111; 4'd7: h_tens_font = 15'b111_001_001_001_001;
            4'd8: h_tens_font = 15'b111_101_111_101_111; 4'd9: h_tens_font = 15'b111_101_111_001_111;
            default: h_tens_font = 15'b0;
        endcase
        case(h_score_ones)
            4'd0: h_ones_font = 15'b111_101_101_101_111; 4'd1: h_ones_font = 15'b010_110_010_010_111;
            4'd2: h_ones_font = 15'b111_001_111_100_111; 4'd3: h_ones_font = 15'b111_001_111_001_111;
            4'd4: h_ones_font = 15'b101_101_111_001_001; 4'd5: h_ones_font = 15'b111_100_111_001_111;
            4'd6: h_ones_font = 15'b111_100_111_101_111; 4'd7: h_ones_font = 15'b111_001_001_001_001;
            4'd8: h_ones_font = 15'b111_101_111_101_111; 4'd9: h_ones_font = 15'b111_101_111_001_111;
            default: h_ones_font = 15'b0;
        endcase
    end
    
    wire draw_tens = (score_tens != 4'd0) && in_tens && tens_font[t_bit];
    wire draw_ones = in_ones && ones_font[o_bit];
    wire score_hit = draw_tens | draw_ones;

    wire draw_h_tens = (h_score_tens != 4'd0) && in_h_tens && h_tens_font[ht_bit];
    wire draw_h_ones = in_h_ones && h_ones_font[ho_bit];
    wire h_score_hit = draw_h_tens | draw_h_ones;

    // 8. "YOU LOST" Text Rendering
    wire in_yl = (x >= 10'd192) && (x < 10'd448) && (y >= 10'd220) && (y < 10'd260);
    wire [9:0] x_rel_yl = x - 10'd192;
    wire [9:0] y_rel_yl = y - 10'd220;
    wire [2:0] char_idx = x_rel_yl[7:5];    
    wire [4:0] char_x   = x_rel_yl[4:0];    
    wire in_char = (char_x < 5'd24);             
    wire [2:0] char_y_grid = y_rel_yl[5:3]; 
    wire [1:0] char_x_grid = char_x[4:3];   
    wire [3:0] yl_bit = 4'd14 - ({1'b0, char_y_grid} * 4'd3) - {2'b00, char_x_grid};
    
    reg [14:0] yl_font;
    always @(*) begin
        case(char_idx)
            3'd0: yl_font = 15'b101_101_111_010_010; 
            3'd1: yl_font = 15'b111_101_101_101_111; 
            3'd2: yl_font = 15'b101_101_101_101_111; 
            3'd3: yl_font = 15'b000_000_000_000_000; 
            3'd4: yl_font = 15'b100_100_100_100_111; 
            3'd5: yl_font = 15'b111_101_101_101_111; 
            3'd6: yl_font = 15'b111_100_111_001_111; 
            3'd7: yl_font = 15'b111_010_010_010_010; 
        endcase
    end
    wire draw_yl = game_over && in_yl && in_char && yl_font[yl_bit];

    // 9. Colour Palette Pipeline
    assign rgb = !active     ? 6'b00_00_00 :
                 draw_yl     ? 6'b11_11_11 : 
                 score_hit   ? 6'b11_11_11 : 
                 h_score_hit ? 6'b11_11_00 : 
                 bird_hit    ? 6'b11_11_00 : 
                 pipe_hit    ? 6'b00_11_00 : 
                 game_over   ? 6'b01_00_00 : 
                               6'b00_10_11 ; 

    // ---------------------------------------------------------------------------
    // 10. ROM AUDIO SEQUENCER ("Sheet Music" architecture)
    // ---------------------------------------------------------------------------
    
    // Notes Pitch Dictionary (3-bit codes)
    localparam REST = 4'd0, D4 = 4'd1, Ds4 = 4'd2, E4 = 4'd3, F4 = 4'd4,
               C5 = 4'd5, E5 = 4'd6, G5 = 4'd7, C6 = 4'd8;

    // Clock ticks in a sixteenth note (Adjusted for 25MHz clock, approx 50ms per tick)
    localparam [20:0] SIXTEENTH_TICKS = 21'd1_250_000;

    // State Variables
    reg        audio_active;
    reg [4:0]  index;
    reg [4:0]  end_index;
    reg [3:0]  pitch;
    reg [3:0]  length;

    // Event Detectors
    reg game_over_last;
    reg [3:0] score_tens_last;
    reg h_score_beaten;

    always @(posedge clk) begin
        if (!rst_n) begin
            game_over_last <= 1'b0;
            score_tens_last <= 4'd0;
        end else begin
            game_over_last <= game_over;
            score_tens_last <= score_tens;
        end
    end

    wire crash_pulse    = game_over & ~game_over_last;
    wire score_10_pulse = (score_tens != score_tens_last) && (score_tens != 4'd0) && !game_over;
    wire is_new_high    = ((score_tens > h_score_tens) || ((score_tens == h_score_tens) && (score_ones > h_score_ones))) && (score_tens != 4'd0 || score_ones != 4'd0);
    wire high_score_pulse = is_new_high && !h_score_beaten && !game_over;

    always @(posedge clk) begin
        if (!rst_n || game_restart) h_score_beaten <= 1'b0;
        else if (high_score_pulse)  h_score_beaten <= 1'b1;
    end

    // --- THE SCORE (ROM) ---
    always @(*) begin
        case (index)
            // Track 1: Jump (Index 0)
            5'd0: begin pitch = E5; length = 4'd1; end

            // Track 2: Score 10 columns (Index 1 to 2)
            5'd1: begin pitch = C5; length = 4'd2; end
            5'd2: begin pitch = G5; length = 4'd4; end

            // Track 3: New High Score! (Index 3 to 6)
            5'd3: begin pitch = C5; length = 4'd2; end
            5'd4: begin pitch = E5; length = 4'd2; end
            5'd5: begin pitch = G5; length = 4'd2; end
            5'd6: begin pitch = C6; length = 4'd6; end

            // Track 4: Game Over (Index 7 to 10)
            5'd7: begin pitch = F4;  length = 4'd4; end
            5'd8: begin pitch = E4;  length = 4'd4; end
            5'd9: begin pitch = Ds4; length = 4'd4; end
            5'd10:begin pitch = D4;  length = 4'd8; end

            default: begin pitch = REST; length = 4'd1; end
        endcase
    end

    // --- THE PITCH TABLE (Math adjusted for 25 MHz) ---
    reg [15:0] half_period;
    always @(*) begin
        case (pitch)
            D4:  half_period = 16'd42662;
            Ds4: half_period = 16'd40192;
            E4:  half_period = 16'd37993;
            F4:  half_period = 16'd35816;
            C5:  half_period = 16'd23900;
            E5:  half_period = 16'd18968;
            G5:  half_period = 16'd15943;
            C6:  half_period = 16'd11950;
            default: half_period = 16'd0; // REST
        endcase
    end

    // --- THE TEMPO ---
    reg [20:0] tick;
    reg [3:0]  step;
    wire sixteenth_done = (tick == SIXTEENTH_TICKS - 21'd1);
    wire note_done      = sixteenth_done && (step == length - 4'd1);

    always @(posedge clk) begin
        if (!rst_n) begin
            tick         <= 21'd0;
            step         <= 4'd0;
            index        <= 5'd0;
            end_index    <= 5'd0;
            audio_active <= 1'b0;
        end else begin
            
            // Event Listeners (Set the track bounds and press play)
            if (crash_pulse) begin
                index <= 5'd7; end_index <= 5'd10; audio_active <= 1'b1; tick <= 21'd0; step <= 4'd0;
            end else if (high_score_pulse) begin
                index <= 5'd3; end_index <= 5'd6;  audio_active <= 1'b1; tick <= 21'd0; step <= 4'd0;
            end else if (score_10_pulse) begin
                index <= 5'd1; end_index <= 5'd2;  audio_active <= 1'b1; tick <= 21'd0; step <= 4'd0;
            end else if (jump_pulse && !game_over) begin
                index <= 5'd0; end_index <= 5'd0;  audio_active <= 1'b1; tick <= 21'd0; step <= 4'd0;
            end 
            // Music Player Engine
            else if (audio_active) begin
                tick <= sixteenth_done ? 21'd0 : tick + 21'd1;
                
                if (note_done) begin
                    step <= 4'd0;
                    if (index == end_index) begin
                        audio_active <= 1'b0; // Track finished
                    end else begin
                        index <= index + 5'd1; // Next note
                    end
                end else if (sixteenth_done) begin
                    step <= step + 4'd1;
                end
            end
        end
    end

    // Create the signature gap between notes
    wire gap = (step == length - 4'd1) && (tick >= SIXTEENTH_TICKS - (SIXTEENTH_TICKS >> 2));

    // --- THE TONE ---
    reg [15:0] tone_count;
    reg        audio_out;
    
    always @(posedge clk) begin
        if (!rst_n || pitch == REST || !audio_active) begin
            tone_count <= 16'd0;
            audio_out  <= 1'b0;
        end else if (tone_count >= half_period - 16'd1) begin
            tone_count <= 16'd0;
            audio_out  <= ~audio_out;
        end else begin
            tone_count <= tone_count + 16'd1;
        end
    end

    assign speaker = audio_out & ~gap & audio_active;

    // 11. Verilator Lint Fix 
    wire _unused_bits = &{
        1'b0,
        xt[9:5], xt[2:0], xo[9:5], xo[2:0],
        y_rel[9:6], y_rel[2:0],
        hxt[9:5], hxt[2:0], hxo[9:5], hxo[2:0],
        x_rel_yl[9:8], y_rel_yl[9:6], y_rel_yl[2:0]
    };

endmodule
