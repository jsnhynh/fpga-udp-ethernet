module udp_formatter_core #(
    parameter SRC_PORT      = 16'd50000,
    parameter DST_PORT      = 16'd60000,
    parameter PAYLOAD_BYTES = 16'd64    // must be even for this simple version
)(
    input  wire        clk,
    input  wire        rst,

    // Control
    input  wire        start,        // pulse to start one packet
    output reg         busy,         // high while sending

    // Payload word interface (16-bit words)
    output reg         pl_req,       // request next word
    input  wire [15:0] pl_data,
    input  wire        pl_valid,
    input  wire        pl_last,

    // Byte stream output (to MAC)
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);

    // State encoding
    localparam FMT_IDLE      = 3'd0;
    localparam FMT_HDR0      = 3'd1;
    localparam FMT_HDR1      = 3'd2;
    localparam FMT_PAYLOAD_H = 3'd3;
    localparam FMT_PAYLOAD_L = 3'd4;
    localparam FMT_DONE      = 3'd5;

    reg [2:0] state, next_state;

    // Header byte index (0..3 for each header half)
    reg [2:0] hdr_idx;

    // UDP length = header(8 bytes) + payload
    wire [15:0] udp_length = 16'd8 + PAYLOAD_BYTES;

    // Buffered payload word
    reg [15:0] current_word;
    reg        current_word_valid;
    reg        current_word_last;

    //--------------------------------------------------------------------------
    // State machine + datapath
    //--------------------------------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            state               <= FMT_IDLE;
            busy                <= 1'b0;
            hdr_idx             <= 3'd0;
            m_axis_tdata        <= 8'h00;
            m_axis_tvalid       <= 1'b0;
            m_axis_tlast        <= 1'b0;
            pl_req              <= 1'b0;
            current_word        <= 16'd0;
            current_word_valid  <= 1'b0;
            current_word_last   <= 1'b0;
        end
        else begin
            state          <= next_state;
            m_axis_tlast   <= 1'b0; // default
            pl_req         <= 1'b0;

            case (state)
                FMT_IDLE: begin
                    busy               <= 1'b0;
                    m_axis_tvalid      <= 1'b0;
                    current_word_valid <= 1'b0;
                    current_word_last  <= 1'b0;
                    hdr_idx            <= 3'd0;
                end

                FMT_HDR0: begin
                    busy <= 1'b1;
                    if (!m_axis_tvalid || m_axis_tready) begin
                        m_axis_tvalid <= 1'b1;
                        case (hdr_idx)
                            3'd0: m_axis_tdata <= SRC_PORT[15:8];
                            3'd1: m_axis_tdata <= SRC_PORT[7:0];
                            3'd2: m_axis_tdata <= DST_PORT[15:8];
                            3'd3: m_axis_tdata <= DST_PORT[7:0];
                            default: m_axis_tdata <= 8'h00;
                        endcase
                        hdr_idx <= (hdr_idx == 3'd3) ? 3'd0 : (hdr_idx + 1'b1);
                    end
                end

                FMT_HDR1: begin
                    busy <= 1'b1;
                    if (!m_axis_tvalid || m_axis_tready) begin
                        m_axis_tvalid <= 1'b1;
                        case (hdr_idx)
                            3'd0: m_axis_tdata <= udp_length[15:8];
                            3'd1: m_axis_tdata <= udp_length[7:0];
                            3'd2: m_axis_tdata <= 8'h00; // checksum msb
                            3'd3: m_axis_tdata <= 8'h00; // checksum lsb
                            default: m_axis_tdata <= 8'h00;
                        endcase
                        hdr_idx <= (hdr_idx == 3'd3) ? 3'd0 : (hdr_idx + 1'b1);
                    end
                end

                FMT_PAYLOAD_H: begin
                    busy <= 1'b1;

                    if (!current_word_valid) begin
                        // request a new payload word
                        pl_req <= 1'b1;
                        if (pl_valid) begin
                            current_word       <= pl_data;
                            current_word_last  <= pl_last;
                            current_word_valid <= 1'b1;
                        end
                        m_axis_tvalid <= 1'b0;
                    end
                    else if (!m_axis_tvalid || m_axis_tready) begin
                        // send high byte
                        m_axis_tvalid <= 1'b1;
                        m_axis_tdata  <= current_word[15:8];
                    end
                end

                FMT_PAYLOAD_L: begin
                    busy <= 1'b1;

                    if (!m_axis_tvalid || m_axis_tready) begin
                        m_axis_tvalid <= 1'b1;
                        m_axis_tdata  <= current_word[7:0];

                        if (current_word_last) begin
                            m_axis_tlast        <= 1'b1; // end of packet
                            current_word_valid  <= 1'b0;
                        end
                        else begin
                            current_word_valid <= 1'b0; // need next word
                        end
                    end
                end

                FMT_DONE: begin
                    busy          <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                end

                default: begin
                    busy          <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Next-state combinational logic
    //--------------------------------------------------------------------------

    always @(*) begin
        next_state = state;
        case (state)
            FMT_IDLE: begin
                if (start)
                    next_state = FMT_HDR0;
            end

            FMT_HDR0: begin
                if (hdr_idx == 3'd3 && m_axis_tvalid && m_axis_tready)
                    next_state = FMT_HDR1;
            end

            FMT_HDR1: begin
                if (hdr_idx == 3'd3 && m_axis_tvalid && m_axis_tready)
                    next_state = FMT_PAYLOAD_H;
            end

            FMT_PAYLOAD_H: begin
                if (current_word_valid && m_axis_tvalid && m_axis_tready)
                    next_state = FMT_PAYLOAD_L;
            end

            FMT_PAYLOAD_L: begin
                if (current_word_last && m_axis_tvalid && m_axis_tready)
                    next_state = FMT_DONE;
                else if (m_axis_tvalid && m_axis_tready)
                    next_state = FMT_PAYLOAD_H;
            end

            FMT_DONE: begin
                next_state = FMT_IDLE;
            end

            default: next_state = FMT_IDLE;
        endcase
    end

endmodule