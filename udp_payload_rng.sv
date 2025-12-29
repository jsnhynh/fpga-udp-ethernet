// udp_payload_rng.v
// 16-bit LFSR-based random number generator for payload data.

module udp_payload_rng (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    output reg [15:0]  sample,
    output reg         valid
);
    // Simple 16-bit maximal-length LFSR with taps [16,14,13,11]
    reg [15:0] lfsr;

    always @(posedge clk) begin
        if (rst) begin
            lfsr   <= 16'h1;  // non-zero seed
            sample <= 16'd0;
            valid  <= 1'b0;
        end
        else if (enable) begin
            // polynomial: x^16 + x^14 + x^13 + x^11 + 1
            lfsr <= { lfsr[14:0],
                      lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10] };

            sample <= lfsr;
            valid  <= 1'b1;
        end
        else begin
            valid <= 1'b0;
        end
    end

endmodule
