// Initial value: 0xFFFF

module crc16_ccitt (
    input  wire       clk,
    input  wire       rst,
    input  wire       init,          // pulse to re-init CRC to 0xFFFF
    input  wire       enable,        // update when 1
    input  wire [7:0] data_in,       // next input byte
    output reg [15:0] crc_out
);

    reg [15:0] crc_next;
    reg [15:0] crc_tmp;
    integer    i;

    always @(*) begin
        crc_tmp = crc_out;
        if (enable) begin
            crc_tmp = crc_tmp ^ {data_in, 8'h00};
            // process 8 bits
            for (i = 0; i < 8; i = i + 1) begin
                if (crc_tmp[15])
                    crc_tmp = (crc_tmp << 1) ^ 16'h1021;
                else
                    crc_tmp = (crc_tmp << 1);
            end
        end
        crc_next = crc_tmp;
    end

    always @(posedge clk) begin
        if (rst) begin
            crc_out <= 16'hFFFF;
        end
        else if (init) begin
            crc_out <= 16'hFFFF;
        end
        else begin
            crc_out <= crc_next;
        end
    end

endmodule