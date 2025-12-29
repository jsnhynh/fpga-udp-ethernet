// udp_packet_gen_top.v
// Top-level UDP packet generator with FSM.
// Instantiates:
//   - udp_payload_rng      (random data source)
//   - crc16_ccitt          (CRC over output bytes; optional use)
//   - udp_formatter_core   (UDP header + payload → AXI-Stream bytes)

module udp_packet_gen_top #(
    parameter SRC_PORT        = 16'd50000,
    parameter DST_PORT        = 16'd60000,
    parameter PAYLOAD_BYTES   = 16'd64,
    parameter INTERVAL_CYCLES = 32'd100000   // gap between packets
)(
    input  wire        clk,
    input  wire        rst,

    // AXI-Stream-like interface to Ethernet MAC
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,

    output reg  [31:0] packet_counter,
    output reg         busy
);

    // RNG outputs
    wire [15:0] rng_sample;
    wire        rng_valid;

    // CRC16 over outgoing bytes
    reg         crc_init;
    reg         crc_enable;
    wire [15:0] crc_value;

    // UDP formatter control
    reg         fmt_start;
    wire        fmt_busy;

    // Payload interface to formatter
    wire        pl_req;
    reg  [15:0] pl_data;
    reg         pl_valid;
    reg         pl_last;

    // Rate control
    reg [31:0] interval_count;

    // FSM states
    localparam ST_IDLE      = 3'd0;
    localparam ST_WAIT_INT  = 3'd1;
    localparam ST_START_PKT = 3'd2;
    localparam ST_SEND_PAY  = 3'd3;
    localparam ST_DONE      = 3'd4;

    reg [2:0] state, next_state;

    // Count payload bytes sent in current packet
    reg [15:0] payload_bytes_sent;

    //----------------------------------------------------------------------
    // Submodules
    //----------------------------------------------------------------------

    udp_payload_rng rng_inst (
        .clk   (clk),
        .rst   (rst),
        .enable(1'b1),
        .sample(rng_sample),
        .valid (rng_valid)
    );

    crc16_ccitt crc16_inst (
        .clk    (clk),
        .rst    (rst),
        .init   (crc_init),
        .enable (crc_enable),
        .data_in(m_axis_tdata),
        .crc_out(crc_value)
    );

    udp_formatter_core #(
        .SRC_PORT      (SRC_PORT),
        .DST_PORT      (DST_PORT),
        .PAYLOAD_BYTES (PAYLOAD_BYTES)
    ) fmt_inst (
        .clk          (clk),
        .rst          (rst),
        .start        (fmt_start),
        .busy         (fmt_busy),

        .pl_req       (pl_req),
        .pl_data      (pl_data),
        .pl_valid     (pl_valid),
        .pl_last      (pl_last),

        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast)
    );

    //----------------------------------------------------------------------
    // FSM: handle timing, payload feeding, and CRC control
    //----------------------------------------------------------------------

    // state register + interval counter + packet counter
    always @(posedge clk) begin
        if (rst) begin
            state          <= ST_IDLE;
            interval_count <= 32'd0;
            packet_counter <= 32'd0;
            busy           <= 1'b0;
        end
        else begin
            state <= next_state;

            if (state == ST_WAIT_INT)
                interval_count <= interval_count + 1;
            else if (state == ST_IDLE)
                interval_count <= 32'd0;

            if (state == ST_DONE && next_state == ST_WAIT_INT)
                packet_counter <= packet_counter + 1;

            busy <= (next_state != ST_IDLE);
        end
    end

    // next-state combinational logic
    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE:      next_state = ST_WAIT_INT;

            ST_WAIT_INT:  if (interval_count >= INTERVAL_CYCLES)
                               next_state = ST_START_PKT;

            ST_START_PKT: next_state = ST_SEND_PAY;

            ST_SEND_PAY:  if (!fmt_busy)
                               next_state = ST_DONE;

            ST_DONE:      next_state = ST_WAIT_INT;

            default:      next_state = ST_IDLE;
        endcase
    end

    // payload feeding + CRC enables
    always @(posedge clk) begin
        if (rst) begin
            fmt_start          <= 1'b0;
            pl_data            <= 16'd0;
            pl_valid           <= 1'b0;
            pl_last            <= 1'b0;
            crc_init           <= 1'b0;
            crc_enable         <= 1'b0;
            payload_bytes_sent <= 16'd0;
        end
        else begin
            // defaults (single-cycle pulses)
            fmt_start  <= 1'b0;
            crc_init   <= 1'b0;
            pl_valid   <= 1'b0;
            pl_last    <= 1'b0;

            case (state)
                ST_IDLE: begin
                    crc_enable         <= 1'b0;
                    payload_bytes_sent <= 16'd0;
                end

                ST_WAIT_INT: begin
                    crc_enable         <= 1'b0;
                    payload_bytes_sent <= 16'd0;
                end

                ST_START_PKT: begin
                    // reset CRC and start formatter
                    fmt_start          <= 1'b1;
                    crc_init           <= 1'b1;
                    crc_enable         <= 1'b1;
                    payload_bytes_sent <= 16'd0;
                end

                ST_SEND_PAY: begin
                    crc_enable <= 1'b1;

                    if (pl_req && rng_valid) begin
                        pl_data  <= rng_sample;
                        pl_valid <= 1'b1;

                        // this design assumes PAYLOAD_BYTES is even
                        if (payload_bytes_sent + 16'd2 >= PAYLOAD_BYTES)
                            pl_last <= 1'b1;

                        payload_bytes_sent <= payload_bytes_sent + 16'd2;
                    end
                end

                ST_DONE: begin
                    crc_enable <= 1'b0;
                end

                default: begin
                    crc_enable <= 1'b0;
                end
            endcase
        end
    end

endmodule