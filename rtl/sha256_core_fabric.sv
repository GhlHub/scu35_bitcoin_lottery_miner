`timescale 1ns/1ps

module sha256_core_fabric (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    input  wire [511:0] block_i,
    input  wire [255:0] h_i,
    output wire         busy_o,
    output wire         done_o,
    output wire [255:0] digest_o
);
    (* use_dsp = "no" *) sha256_core_iterative u_core (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(start_i),
        .block_i(block_i),
        .h_i(h_i),
        .busy_o(busy_o),
        .done_o(done_o),
        .digest_o(digest_o)
    );
endmodule
