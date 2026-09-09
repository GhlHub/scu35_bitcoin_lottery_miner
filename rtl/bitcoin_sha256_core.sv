`timescale 1ns/1ps

// SHA-256 compression wrapper specialized for the two fixed Bitcoin blocks.
// It removes the per-engine registered 512-bit block and 256-bit state buses;
// only the dynamic Bitcoin fields are presented to the compression core.
module bitcoin_sha256_core (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    input  wire         first_pass_i,
    input  wire [255:0] midstate_i,
    input  wire [127:0] header_tail_i,
    input  wire [31:0]  nonce_i,
    input  wire [255:0] first_digest_i,
    output wire         busy_o,
    output wire         done_o,
    output wire [255:0] digest_o
);
    localparam [255:0] SHA256_IV = {
        32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
        32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
    };
    wire [511:0] block = first_pass_i ? {
        header_tail_i[127:96], header_tail_i[95:64], header_tail_i[63:32],
        (nonce_i | (header_tail_i[31:0] & 32'h00000000)),
        32'h80000000, 320'h0, 32'h00000280
    } : {
        first_digest_i, 32'h80000000, 192'h0, 32'h00000100
    };

    // Portable fabric path: SU35P has DSP48E2, not the VEK280's DSP58.
    sha256_core_fabric u_core (
        .clk_i(clk_i), .rst_ni(rst_ni), .start_i(start_i), .block_i(block),
        .h_i(first_pass_i ? midstate_i : SHA256_IV), .busy_o(busy_o),
        .done_o(done_o), .digest_o(digest_o)
    );
endmodule
