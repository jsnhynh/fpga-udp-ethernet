`timescale 1ns / 1ps
//We use a Linear Shift Feedback Register to generate random numbers to simulate a stock price.
//This is just one type of data that could be considered for the "UDP Packet Generator for Real-Time Data Acquisition"
//We also considered working with digitally sampled seismic data, maybe taken during an underground nuclear test
//Utilizing the strengths of HDL to apply DSP to this type of data
//The data could be processed on the edge, and when a trigger happens, the event is transmitted on a UDP packet over the internet.

module market_gen #(
    parameter CLK_DIV = 100000 // Slowed down so you can see it happen!
) (
    input  wire        clk,
    input  wire        rst,
    output reg  [15:0] price,
    output reg         valid
);
    reg [31:0] lfsr = 32'hABCDE123;
    reg [31:0] clk_cnt = 0;
    integer tmp;
    initial price = 16'd1000;

    wire lsb = lfsr[0];
    wire signed [7:0] delta = (lfsr[3:0] % 8);
    wire signed [8:0] signed_delta = lsb ? delta : -delta;

    always @(posedge clk) begin
        if (rst) begin
            lfsr <= 32'hABCDE123;
            price <= 16'd1000;
            clk_cnt <= 0;
            valid <= 0;
        end else begin
            if (clk_cnt >= (CLK_DIV-1)) begin
                clk_cnt <= 0;
                valid <= 1;
                // LFSR Update
                lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
                // Random Walk

                tmp = $signed({1'b0, price}) + $signed(signed_delta);
                if (tmp < 100) tmp = 100;
                if (tmp > 60000) tmp = 60000;
                price <= tmp[15:0];
            end else begin
                clk_cnt <= clk_cnt + 1;
                valid <= 0;
            end
        end
    end
endmodule