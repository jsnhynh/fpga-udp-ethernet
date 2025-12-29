module dsp_trader (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] price_in,
    input  wire        price_valid,
    output reg  [31:0] trade_word,
    output reg         trade_valid
);
    // Q16.16 Fixed Point Math
    reg signed [31:0] ema_short = 0;
    reg signed [31:0] ema_long  = 0;
    reg signed [31:0] diff      = 0;
    reg signed [31:0] prev_diff = 0;
    
    // We calculate temporary wires for the "next" values
    // to fix the "lag" issue.
    reg signed [31:0] next_short;
    reg signed [31:0] next_long;
    
    
    // Warmup Counter: Don't trade until EMAs stabilize
    reg [7:0] warmup_cnt; 

    // Threshold: 1.0 (in Q16.16 fixed point, 1.0 = 65536)
    // This prevents trading on tiny noise.
    localparam THRESHOLD = 32'd65536; 

    always @(posedge clk) begin
        if (rst) begin
            ema_short   <= 0;
            ema_long    <= 0;
            diff        <= 0;
            prev_diff   <= 0;
            trade_valid <= 0;
            warmup_cnt  <= 0;
        end else begin
            trade_valid <= 0; // Default low

            if (price_valid) begin
                // 1. Handle Warmup
                if (warmup_cnt < 200) begin
                    // During warmup, force EMAs to jump directly to price
                    // This prevents the "0 to 1000" climb
                    if (warmup_cnt == 0) begin
                         ema_short <= {price_in, 16'd0};
                         ema_long  <= {price_in, 16'd0};
                    end else begin
                        // Standard update during warmup
                        ema_short <= ema_short + (({price_in, 16'd0} - ema_short) >>> 3);
                        ema_long  <= ema_long  + (({price_in, 16'd0} - ema_long)  >>> 6);
                    end
                    warmup_cnt <= warmup_cnt + 1;
                end 
                else begin
                    // Calculate new EMAs, use non-blocking to reduce latency
                    
                    next_short = ema_short + (({price_in, 16'd0} - ema_short) >>> 3);
                    next_long  = ema_long  + (({price_in, 16'd0} - ema_long)  >>> 6);
                    
                    ema_short <= next_short;
                    ema_long  <= next_long;

                    // Update Diff using the values we just calculated
                    prev_diff <= diff;
                    diff      <= next_short - next_long;

                    // 3. Trade Logic with Hysteresis
                    // BUY: Crossed above 0 AND gap is large enough
                    if ((prev_diff < THRESHOLD) && (diff >= THRESHOLD)) begin
                        trade_word  <= {1'b1, 15'd50, price_in}; // BUY
                        trade_valid <= 1;
                    end
                    // SELL: Crossed below 0 AND gap is large enough negative
                    else if ((prev_diff > -THRESHOLD) && (diff <= -THRESHOLD)) begin
                        trade_word  <= {1'b0, 15'd50, price_in}; // SELL
                        trade_valid <= 1;
                    end
                end
            end
        end
    end
endmodule