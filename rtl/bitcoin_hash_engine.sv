`timescale 1ns/1ps

module bitcoin_hash_engine #(
    parameter int unsigned NONCE_STRIDE = 1,
    parameter bit EXPLICIT_DSP_SCHEDULE = 1'b0
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    input  wire         stop_i,
    input  wire [255:0] midstate_i,
    input  wire [127:0] header_tail_i,
    input  wire [255:0] target_i,
    input  wire [31:0]  nonce_start_i,
    input  wire [31:0]  nonce_count_i,
    output wire         busy_o,
    output reg          done_o,
    output reg          result_valid_o,
    output reg  [31:0]  result_nonce_o
);
    localparam [3:0] ST_IDLE    = 4'd0;
    localparam [3:0] ST_LAUNCH  = 4'd1;
    localparam [3:0] ST_PASS1   = 4'd2;
    localparam [3:0] ST_PASS2   = 4'd3;
    localparam [3:0] ST_COMPARE = 4'd4;
    localparam [3:0] ST_CHECK   = 4'd5;

    (* max_fanout = 64 *) reg [3:0] state_q;
    (* max_fanout = 64 *) reg       core_start_q;
    reg [3:0]   launch_state_q;
    reg         core_first_pass_q;
    wire        core_busy;
    wire        core_done;
    wire [255:0] core_digest;
    localparam [31:0] NONCE_STRIDE_W = NONCE_STRIDE;

    reg [255:0] midstate_q;
    reg [127:0] header_tail_q;
    reg [255:0] target_q;
    reg [31:0]  nonce_q;
    reg [31:0]  remaining_q;
    reg [255:0] digest_q;
    reg [2:0]   cmp_idx_q;
    reg         cmp_lt_q;
    reg         cmp_gt_q;

    // Bitcoin interprets the SHA256d digest bytes as a little-endian uint256.
    // Keep the raw first digest unchanged for the second SHA compression.
    wire [255:0] bitcoin_digest;
    for (genvar b = 0; b < 32; b = b + 1) begin : g_digest_byte_order
        assign bitcoin_digest[255 - b*8 -: 8] = digest_q[b*8 +: 8];
    end

    assign busy_o = (state_q != ST_IDLE) || core_busy;

    generate
    if (EXPLICIT_DSP_SCHEDULE) begin : g_explicit_dsp
    bitcoin_sha256_core_dsp_explicit u_core (
        .clk_i(clk_i), .rst_ni(rst_ni), .start_i(core_start_q),
        .first_pass_i(core_first_pass_q), .midstate_i(midstate_q),
        .header_tail_i(header_tail_q), .nonce_i(nonce_q), .first_digest_i(digest_q),
        .busy_o(core_busy), .done_o(core_done), .digest_o(core_digest)
    );
    end else begin : g_default
    bitcoin_sha256_core u_core (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(core_start_q),
        .first_pass_i(core_first_pass_q),
        .midstate_i(midstate_q),
        .header_tail_i(header_tail_q),
        .nonce_i(nonce_q),
        .first_digest_i(digest_q),
        .busy_o(core_busy),
        .done_o(core_done),
        .digest_o(core_digest)
    );
    end
    endgenerate

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_IDLE;
            launch_state_q <= ST_IDLE;
            core_start_q <= 1'b0;
            core_first_pass_q <= 1'b1;
            midstate_q <= 256'h0;
            header_tail_q <= 128'h0;
            target_q <= 256'h0;
            nonce_q <= 32'h0;
            remaining_q <= 32'h0;
            digest_q <= 256'h0;
            cmp_idx_q <= 3'd0;
            cmp_lt_q <= 1'b0;
            cmp_gt_q <= 1'b0;
            done_o <= 1'b0;
            result_valid_o <= 1'b0;
            result_nonce_o <= 32'h0;
        end else begin
            core_start_q <= 1'b0;
            done_o <= 1'b0;
            result_valid_o <= 1'b0;

            if (stop_i) begin
                state_q <= ST_IDLE;
                done_o <= (state_q != ST_IDLE);
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        if (start_i && (nonce_count_i != 32'd0)) begin
                            midstate_q <= midstate_i;
                            header_tail_q <= header_tail_i;
                            target_q <= target_i;
                            nonce_q <= nonce_start_i;
                            remaining_q <= nonce_count_i;
                            digest_q <= 256'h0;
                            cmp_idx_q <= 3'd0;
                            cmp_lt_q <= 1'b0;
                            cmp_gt_q <= 1'b0;
                            core_first_pass_q <= 1'b1;
                            launch_state_q <= ST_PASS1;
                            state_q <= ST_LAUNCH;
                        end
                    end

                    ST_LAUNCH: begin
                        core_start_q <= 1'b1;
                        state_q <= launch_state_q;
                    end

                    ST_PASS1: begin
                        if (core_done) begin
                            digest_q <= core_digest;
                            core_first_pass_q <= 1'b0;
                            launch_state_q <= ST_PASS2;
                            state_q <= ST_LAUNCH;
                        end
                    end

                    ST_PASS2: begin
                        if (core_done) begin
                            digest_q <= core_digest;
                            cmp_idx_q <= 3'd0;
                            cmp_lt_q <= 1'b0;
                            cmp_gt_q <= 1'b0;
                            state_q <= ST_COMPARE;
                        end
                    end

                    ST_COMPARE: begin
                        if (!cmp_lt_q && !cmp_gt_q) begin
                            if (bitcoin_digest[255 - (cmp_idx_q * 32) -: 32] <
                                target_q[255 - (cmp_idx_q * 32) -: 32]) begin
                                cmp_lt_q <= 1'b1;
                            end else if (bitcoin_digest[255 - (cmp_idx_q * 32) -: 32] >
                                         target_q[255 - (cmp_idx_q * 32) -: 32]) begin
                                cmp_gt_q <= 1'b1;
                            end
                        end

                        if (cmp_idx_q == 3'd7) begin
                            if (cmp_lt_q ||
                                (!cmp_gt_q &&
                                 (bitcoin_digest[31:0] <= target_q[31:0]))) begin
                                result_valid_o <= 1'b1;
                                result_nonce_o <= nonce_q;
                            end
                            state_q <= ST_CHECK;
                        end else begin
                            cmp_idx_q <= cmp_idx_q + 3'd1;
                        end
                    end

                    ST_CHECK: begin
                        if (remaining_q <= 32'd1) begin
                            done_o <= 1'b1;
                            state_q <= ST_IDLE;
                        end else begin
                            remaining_q <= remaining_q - 32'd1;
                            nonce_q <= nonce_q + NONCE_STRIDE_W;
                            core_first_pass_q <= 1'b1;
                            launch_state_q <= ST_PASS1;
                            state_q <= ST_LAUNCH;
                        end
                    end

                    default: begin
                        state_q <= ST_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
