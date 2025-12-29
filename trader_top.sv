module trader_top(
    input wire clk,
    input wire rst_n, 
    // AXI Stream Interface
    output reg [31:0] axis_tdata,
    output reg        axis_tvalid,
    output reg        axis_tlast,  // REQUIRED for FIFO Packet Mode
    input  wire       axis_tready
);
    wire [15:0] raw_price;
    wire        price_valid;
    wire [31:0] trade_data;
    wire        trade_pulse;
    wire        rst = ~rst_n;

    market_gen mkt (.clk(clk), .rst(rst), .price(raw_price), .valid(price_valid));
    dsp_trader trd (.clk(clk), .rst(rst), .price_in(raw_price), .price_valid(price_valid), .trade_word(trade_data), .trade_valid(trade_pulse));

    always @(posedge clk) begin
        if (rst) begin
            axis_tvalid <= 0; axis_tlast <= 0; axis_tdata <= 0;
        end else begin
            axis_tvalid <= 0; axis_tlast <= 0;
            // Only push if trade occurred AND FIFO is ready
            if (trade_pulse && axis_tready) begin
                axis_tdata  <= trade_data;
                axis_tvalid <= 1; 
                axis_tlast  <= 1; // Mark as 1-word packet
            end
        end
    end
endmodule