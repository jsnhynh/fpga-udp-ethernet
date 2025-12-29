`timescale 1ns / 1ps

module tb_market_gen;

    //Signals
    logic clk;
    logic rst;
    logic [15:0] price;
    logic valid;

    //Parameters
    //Override the divider to 4 because it's too high
    localparam TEST_CLK_DIV = 4;

    //DUT Instantiation
    market_gen #(
        .CLK_DIV(TEST_CLK_DIV)
    ) dut (
        .clk(clk),
        .rst(rst),
        .price(price),
        .valid(valid)
    );

    //Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period (100 MHz)
    end

    //Test Stimulus
    initial begin
        $display("--- Starting Market Gen Simulation ---");
        
        // 1. Reset Sequence
        rst = 1;
        #100;
        rst = 0;
        $display("[%0t] Reset Released. Start Price: %d", $time, price);

        // 2. Monitor Loop
        // Run for 1000 clock cycles and observe the behavior
        repeat (200) begin
            @(posedge clk);
            
            // Check Bound Constraints
            if (price < 100 || price > 60000) begin
                $error("ERROR: Price out of bounds! Price: %d", price);
            end

            // Print on valid pulse
            if (valid) begin
                $display("[%0t] Price Update: %d", $time, price);
            end
        end

        $display("--- Market Gen Simulation Finished ---");
        $finish;
    end

endmodule