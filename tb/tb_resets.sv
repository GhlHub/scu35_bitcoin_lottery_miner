`timescale 1ns/1ps
module tb_resets;
    reg clk = 0;
    always #10 clk = ~clk;
    reg resetn = 0, async_irq = 0;
    wire phy_resetn, irq;
    phy_reset_hold #(.HOLD_CYCLES(8)) hold_dut (.*);
    irq_sync sync_dut (.*);
    initial begin
        repeat (3) @(negedge clk);
        if (phy_resetn || irq) $fatal(1, "Outputs asserted during reset");
        resetn = 1;
        repeat (7) begin
            @(negedge clk);
            if (phy_resetn) $fatal(1, "PHY reset released too early");
        end
        @(negedge clk);
        if (!phy_resetn) $fatal(1, "PHY reset never released");
        async_irq = 1;
        @(negedge clk);
        if (irq) $fatal(1, "IRQ bypassed synchronizer");
        @(negedge clk);
        if (!irq) $fatal(1, "IRQ lost");
        #3 resetn = 0;
        #1;
        if (phy_resetn || irq) $fatal(1, "Reset failed to assert asynchronously");
        repeat (2) @(negedge clk);
        resetn = 1; async_irq = 0;
        repeat (7) begin
            @(negedge clk);
            if (phy_resetn) $fatal(1, "PHY delay failed on repeated reset");
        end
        @(negedge clk);
        if (!phy_resetn || irq) $fatal(1, "Incorrect repeated-reset recovery");
        $display("RESET HOLD AND IRQ SYNCHRONIZER TESTS PASSED");
        $finish;
    end
endmodule
