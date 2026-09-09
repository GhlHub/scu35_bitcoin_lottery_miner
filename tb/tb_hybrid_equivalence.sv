// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
module tb_hybrid_equivalence;
    reg clk=0;
    always #2.5 clk=~clk;
    reg resetn=0, start=0;
    reg [511:0] block_data;
    reg [255:0] state_data;
    wire base_done, hybrid_done, dsp5_done;
    wire [255:0] base_digest, hybrid_digest, dsp5_digest;
    reg [31:0] a,b;
    wire [31:0] sum;
    dsp48e2_add32 adder(.a_i(a),.b_i(b),.sum_o(sum));
    sha256_core_iterative baseline(
        .clk_i(clk),.rst_ni(resetn),.start_i(start),.block_i(block_data),
        .h_i(state_data),.busy_o(),.done_o(base_done),.digest_o(base_digest));
    sha256_core_iterative #(.EXPLICIT_DSP_SCHEDULE(1),.FOUR_PHASE(1)) hybrid(
        .clk_i(clk),.rst_ni(resetn),.start_i(start),.block_i(block_data),
        .h_i(state_data),.busy_o(),.done_o(hybrid_done),.digest_o(hybrid_digest));
    sha256_core_iterative #(.EXPLICIT_DSP_SCHEDULE(1),.FOUR_PHASE(1),.DSP_ROUND_STATE(0)) dsp5(
        .clk_i(clk),.rst_ni(resetn),.start_i(start),.block_i(block_data),
        .h_i(state_data),.busy_o(),.done_o(dsp5_done),.digest_o(dsp5_digest));
    integer base_cycle, hybrid_cycle;
    initial begin
        // UNISIM glbl holds GSR for the first 100 ns.
        #120;
        for(integer i=0;i<1032;i=i+1) begin
            case(i)
                0: begin a=0;b=0;end
                1: begin a=32'hffffffff;b=1;end
                2: begin a=32'hffffffff;b=32'hffffffff;end
                3: begin a=32'h0003ffff;b=1;end // A:B boundary carry
                4: begin a=32'h7fffffff;b=1;end
                5: begin a=32'h80000000;b=32'h80000000;end
                6: begin a=32'haaaaaaaa;b=32'h55555555;end
                7: begin a=32'h00040000;b=32'hffff0000;end
                default: begin a=$urandom;b=$urandom;end
            endcase
            #5;
            if(sum !== (a+b)) $fatal(1,"DSP addition mismatch %h + %h = %h",a,b,sum);
        end
        @(negedge clk);resetn=1;
        for(integer trial=0;trial<32;trial=trial+1) begin
            for(integer j=0;j<16;j=j+1) block_data[j*32+:32]=$urandom;
            for(integer j=0;j<8;j=j+1) state_data[j*32+:32]=$urandom;
            if(trial==0) begin block_data=0;state_data=0;end
            if(trial==1) begin block_data='1;state_data='1;end
            start=1;@(negedge clk);start=0;
            base_cycle=0;hybrid_cycle=0;
            for(integer cycle=1;cycle<=322;cycle=cycle+1) begin
                @(negedge clk);
                if(base_done) base_cycle=cycle;
                if(hybrid_done) hybrid_cycle=cycle;
                if(hybrid_done !== dsp5_done) $fatal(1,"Five/ten-DSP schedules differ");
            end
            if(base_cycle!=320||hybrid_cycle!=256)
                $fatal(1,"Latency baseline=%0d hybrid=%0d",base_cycle,hybrid_cycle);
            if(base_digest !== hybrid_digest)
                $fatal(1,"Compression mismatch trial=%0d base=%h hybrid=%h",trial,base_digest,hybrid_digest);
            if(dsp5_digest !== hybrid_digest) $fatal(1,"Five/ten-DSP digest mismatch trial=%0d",trial);
        end
        $display("HYBRID EQUIVALENCE PASS: 1032 DSP additions; 32 blocks across fabric/five-DSP/ten-DSP; 320 -> 256 cycles");
        $finish;
    end
    initial begin #1000000;$fatal(1,"Timeout");end
endmodule
