`timescale 1ns/1ps
module tb_genesis #(parameter bit HYBRID = 0);
    reg clk = 0;
    always #2.5 clk = ~clk;
    reg resetn = 0;
    reg start = 0;
    reg stop = 0;
    reg [255:0] target;
    reg [31:0] nonce_count = 1;
    wire busy, done, valid;
    wire [31:0] nonce;
    localparam [255:0] GENESIS_HASH = 256'h000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f;
    bitcoin_hash_engine #(.EXPLICIT_DSP_SCHEDULE(HYBRID)) dut (
        .clk_i(clk), .rst_ni(resetn), .start_i(start), .stop_i(stop),
        .midstate_i(256'hbc909a336358bff090ccac7d1e59caa8c3c8d8e94f0103c896b187364719f91b),
        .header_tail_i(128'h4b1e5e4a29ab5f49ffff001d00000000),
        .nonce_start_i(32'h1dac2b7c), .nonce_count_i(nonce_count),
        .target_i(target), .busy_o(busy), .done_o(done),
        .result_valid_o(valid), .result_nonce_o(nonce)
    );
    task automatic run_case(input [255:0] threshold, input bit expect_result);
        integer seen, cycles;
        begin
            @(negedge clk); target = threshold; start = 1;
            @(negedge clk); start = 0;
            seen = 0; cycles = 0;
            while (!done && cycles < 1000) begin
                @(negedge clk);
                cycles++;
                if (valid) begin
                    seen++;
                    if (nonce !== 32'h1dac2b7c) $fatal(1, "Wrong nonce");
                end
            end
            if (!done) $fatal(1, "Engine timeout");
            if (cycles != (HYBRID ? 527 : 655)) $fatal(1, "Unexpected nonce latency %0d", cycles);
            if (dut.digest_q !== 256'h6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000)
                $fatal(1, "Genesis SHA256d mismatch: %h", dut.digest_q);
            if (seen != int'(expect_result)) $fatal(1, "Bitcoin target comparison: got %0d expected %0d", seen, expect_result);
            $display("Genesis target %h: candidates=%0d cycles=%0d", threshold, seen, cycles);
            repeat (3) @(negedge clk);
        end
    endtask
    task automatic run_batch;
        integer seen, cycles, last_result;
        begin
            @(negedge clk);target='1;nonce_count=4;start=1;
            @(negedge clk);start=0;
            seen=0;cycles=0;last_result=0;
            while(!done && cycles<3000) begin
                @(negedge clk);cycles++;
                if(valid) begin
                    if(nonce !== 32'h1dac2b7c+seen) $fatal(1,"Batch nonce ordering");
                    if(seen>0 && cycles-last_result != (HYBRID ? 527 : 655))
                        $fatal(1,"Incorrect steady-state nonce interval %0d",cycles-last_result);
                    last_result=cycles;seen++;
                end
            end
            if(!done || seen!=4 || cycles!=4*(HYBRID ? 527 : 655))
                $fatal(1,"Batch count/timing seen=%0d cycles=%0d",seen,cycles);
            $display("STEADY STATE PASS: four nonces in %0d cycles",cycles);
            nonce_count=1;
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        repeat (24) @(negedge clk); // Wait past UNISIM global startup reset.
        resetn = 1;
        run_case(GENESIS_HASH, 1);
        run_case(GENESIS_HASH - 256'd1, 0);
        run_case(256'h00000000ffff0000000000000000000000000000000000000000000000000000, 1);
        run_batch();
        // Firmware waits for the old compression to drain before replacing
        // work. No abandoned result may escape or contaminate the next header.
        @(negedge clk);target=GENESIS_HASH;start=1;
        @(negedge clk);start=0;
        repeat (100) @(negedge clk);
        stop=1;@(negedge clk);stop=0;
        repeat (700) begin
            @(negedge clk);
            if(valid)$fatal(1,"Abandoned job produced a result");
        end
        if(busy)$fatal(1,"Stopped engine did not drain");
        run_case(GENESIS_HASH,1);
        $display("GENESIS HASH AND TARGET TESTS PASSED");
        $finish;
    end
endmodule
