`timescale 1ns/1ps
module irq_sync (
    input wire clk,
    input wire resetn,
    input wire async_irq,
    output wire irq
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_q;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) sync_q <= 2'b00;
        else sync_q <= {sync_q[0], async_irq};
    end
    assign irq = sync_q[1];
endmodule
