`timescale 1ns/1ps
module phy_reset_hold #(
    parameter integer HOLD_CYCLES = 500000
) (
    input wire clk,
    input wire resetn,
    output wire phy_resetn
);
    localparam integer WIDTH = $clog2(HOLD_CYCLES + 1);
    reg [WIDTH-1:0] count_q;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) count_q <= 0;
        else if (count_q < HOLD_CYCLES) count_q <= count_q + 1'b1;
    end
    assign phy_resetn = resetn && (count_q == HOLD_CYCLES);
endmodule
