`timescale 1ns/1ps

module tb_bitcoin_miner_axi #(parameter bit HYBRID = 0, parameter int unsigned NUM_ENGINES = 3);
    localparam int unsigned CLUSTER_SIZE = 2;
    localparam [255:0] SHA256_IV = {
        32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
        32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
    };

    localparam [11:0] ADDR_CONTROL       = 12'h000;
    localparam [11:0] ADDR_STATUS        = 12'h004;
    localparam [11:0] ADDR_NUM_ENGINES   = 12'h008;
    localparam [11:0] ADDR_MIDSTATE_BASE = 12'h020;
    localparam [11:0] ADDR_TAIL_BASE     = 12'h040;
    localparam [11:0] ADDR_TARGET_BASE   = 12'h060;
    localparam [11:0] ADDR_NONCE_START   = 12'h080;
    localparam [11:0] ADDR_NONCE_COUNT   = 12'h084;
    localparam [11:0] ADDR_RESULT_NONCE  = 12'h090;
    localparam [11:0] ADDR_RESULT_ENGINE = 12'h094;
    localparam [11:0] ADDR_RESULT_STATUS = 12'h098;

    reg         clk;
    reg         rst_n;
    reg [11:0]  awaddr;
    reg         awvalid;
    wire        awready;
    reg [31:0]  wdata;
    reg [3:0]   wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg [11:0]  araddr;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;
    wire        irq;

    integer failures;

    bitcoin_miner_axi #(
        .NUM_ENGINES(NUM_ENGINES),
        .CLUSTER_SIZE(CLUSTER_SIZE),
        .CLUSTER_FIFO_DEPTH(4),
        .EXPLICIT_DSP_SCHEDULE(HYBRID),
        .AXI_ADDR_WIDTH(12)
    ) u_dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .irq_o(irq)
    );

    always #5 clk <= ~clk;

    function automatic [31:0] rotr(input [31:0] x, input integer n);
        rotr = (x >> n) | (x << (32 - n));
    endfunction

    function automatic [31:0] ch(input [31:0] x, input [31:0] y, input [31:0] z);
        ch = (x & y) ^ (~x & z);
    endfunction

    function automatic [31:0] maj(input [31:0] x, input [31:0] y, input [31:0] z);
        maj = (x & y) ^ (x & z) ^ (y & z);
    endfunction

    function automatic [31:0] big_sigma0(input [31:0] x);
        big_sigma0 = rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
    endfunction

    function automatic [31:0] big_sigma1(input [31:0] x);
        big_sigma1 = rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
    endfunction

    function automatic [31:0] small_sigma0(input [31:0] x);
        small_sigma0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
    endfunction

    function automatic [31:0] small_sigma1(input [31:0] x);
        small_sigma1 = rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
    endfunction

    function automatic [31:0] k(input integer idx);
        begin
            case (idx)
                0:  k = 32'h428a2f98; 1:  k = 32'h71374491;
                2:  k = 32'hb5c0fbcf; 3:  k = 32'he9b5dba5;
                4:  k = 32'h3956c25b; 5:  k = 32'h59f111f1;
                6:  k = 32'h923f82a4; 7:  k = 32'hab1c5ed5;
                8:  k = 32'hd807aa98; 9:  k = 32'h12835b01;
                10: k = 32'h243185be; 11: k = 32'h550c7dc3;
                12: k = 32'h72be5d74; 13: k = 32'h80deb1fe;
                14: k = 32'h9bdc06a7; 15: k = 32'hc19bf174;
                16: k = 32'he49b69c1; 17: k = 32'hefbe4786;
                18: k = 32'h0fc19dc6; 19: k = 32'h240ca1cc;
                20: k = 32'h2de92c6f; 21: k = 32'h4a7484aa;
                22: k = 32'h5cb0a9dc; 23: k = 32'h76f988da;
                24: k = 32'h983e5152; 25: k = 32'ha831c66d;
                26: k = 32'hb00327c8; 27: k = 32'hbf597fc7;
                28: k = 32'hc6e00bf3; 29: k = 32'hd5a79147;
                30: k = 32'h06ca6351; 31: k = 32'h14292967;
                32: k = 32'h27b70a85; 33: k = 32'h2e1b2138;
                34: k = 32'h4d2c6dfc; 35: k = 32'h53380d13;
                36: k = 32'h650a7354; 37: k = 32'h766a0abb;
                38: k = 32'h81c2c92e; 39: k = 32'h92722c85;
                40: k = 32'ha2bfe8a1; 41: k = 32'ha81a664b;
                42: k = 32'hc24b8b70; 43: k = 32'hc76c51a3;
                44: k = 32'hd192e819; 45: k = 32'hd6990624;
                46: k = 32'hf40e3585; 47: k = 32'h106aa070;
                48: k = 32'h19a4c116; 49: k = 32'h1e376c08;
                50: k = 32'h2748774c; 51: k = 32'h34b0bcb5;
                52: k = 32'h391c0cb3; 53: k = 32'h4ed8aa4a;
                54: k = 32'h5b9cca4f; 55: k = 32'h682e6ff3;
                56: k = 32'h748f82ee; 57: k = 32'h78a5636f;
                58: k = 32'h84c87814; 59: k = 32'h8cc70208;
                60: k = 32'h90befffa; 61: k = 32'ha4506ceb;
                62: k = 32'hbef9a3f7; 63: k = 32'hc67178f2;
                default: k = 32'h00000000;
            endcase
        end
    endfunction

    function automatic [255:0] compress_ref(input [511:0] msg_block, input [255:0] h_state);
        reg [31:0] w [0:63];
        reg [31:0] a;
        reg [31:0] b;
        reg [31:0] c;
        reg [31:0] d;
        reg [31:0] e;
        reg [31:0] f;
        reg [31:0] g;
        reg [31:0] h;
        reg [31:0] h0;
        reg [31:0] h1;
        reg [31:0] h2;
        reg [31:0] h3;
        reg [31:0] h4;
        reg [31:0] h5;
        reg [31:0] h6;
        reg [31:0] h7;
        reg [31:0] t1;
        reg [31:0] t2;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                w[i] = msg_block[511 - (i * 32) -: 32];
            end
            for (i = 16; i < 64; i = i + 1) begin
                w[i] = small_sigma1(w[i - 2]) + w[i - 7] + small_sigma0(w[i - 15]) + w[i - 16];
            end
            h0 = h_state[255:224];
            h1 = h_state[223:192];
            h2 = h_state[191:160];
            h3 = h_state[159:128];
            h4 = h_state[127:96];
            h5 = h_state[95:64];
            h6 = h_state[63:32];
            h7 = h_state[31:0];
            a = h0; b = h1; c = h2; d = h3;
            e = h4; f = h5; g = h6; h = h7;
            for (i = 0; i < 64; i = i + 1) begin
                t1 = h + big_sigma1(e) + ch(e, f, g) + k(i) + w[i];
                t2 = big_sigma0(a) + maj(a, b, c);
                h = g; g = f; f = e; e = d + t1;
                d = c; c = b; b = a; a = t1 + t2;
            end
            compress_ref = {h0 + a, h1 + b, h2 + c, h3 + d,
                            h4 + e, h5 + f, h6 + g, h7 + h};
        end
    endfunction

    function automatic [511:0] make_first_pass_block(input [127:0] tail, input [31:0] nonce);
        begin
            make_first_pass_block = {tail[127:96], tail[95:64], tail[63:32], nonce | (tail[31:0] & 32'h00000000),
                                     32'h80000000, 320'h0, 32'h00000280};
        end
    endfunction

    function automatic [511:0] make_second_pass_block(input [255:0] digest);
        begin
            make_second_pass_block = {digest, 32'h80000000, 192'h0, 32'h00000100};
        end
    endfunction

    task automatic axi_write(input [11:0] addr, input [31:0] data, input [3:0] strb = 4'hf);
        begin
            @(negedge clk);
            awaddr = addr;
            wdata = data;
            wstrb = strb;
            awvalid = 1'b1;
            wvalid = 1'b1;
            bready = 1'b1;
            while (!(awready && wready)) begin
                @(negedge clk);
            end
            awvalid = 1'b0;
            wvalid = 1'b0;
            while (!bvalid) begin
                @(negedge clk);
            end
            if (bresp != 2'b00) begin
                $display("FAIL AXI write response at %03h", addr);
                failures = failures + 1;
            end
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(input [11:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            araddr = addr;
            arvalid = 1'b1;
            rready = 1'b1;
            while (!arready) begin
                @(negedge clk);
            end
            arvalid = 1'b0;
            while (!rvalid) begin
                @(negedge clk);
            end
            data = rdata;
            if (rresp != 2'b00) begin
                $display("FAIL AXI read response at %03h", addr);
                failures = failures + 1;
            end
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task automatic write_words256(input [11:0] base_addr, input [255:0] value);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                axi_write(base_addr + 12'(i * 4), value[255 - (i * 32) -: 32]);
            end
        end
    endtask

    task automatic write_words128(input [11:0] base_addr, input [127:0] value);
        integer i;
        begin
            for (i = 0; i < 4; i = i + 1) begin
                axi_write(base_addr + 12'(i * 4), value[127 - (i * 32) -: 32]);
            end
        end
    endtask

    // Check exact nonce coverage independently of cluster arbitration order.
    task automatic check_batch(input [31:0] first, input integer count);
        reg [31:0] status_word, nonce, engine, offset, before_count, after_count;
        reg [31:0] seen;
        integer polls;
        begin
            axi_write(ADDR_CONTROL, 4);
            axi_write(ADDR_RESULT_STATUS, 3);
            write_words256(ADDR_TARGET_BASE, {256{1'b1}});
            axi_write(ADDR_NONCE_START, first);
            axi_write(ADDR_NONCE_COUNT, 32'(count));
            axi_read(12'h0ac, before_count);
            axi_write(ADDR_CONTROL, 1);
            seen = 0;
            for(integer n=0; n<count; n=n+1) begin
                status_word=0;polls=0;
                while(!status_word[1] && polls<2400) begin
                    axi_read(ADDR_STATUS,status_word);polls=polls+1;
                end
                if(polls==2400) $fatal(1,"Batch result timeout");
                axi_read(ADDR_RESULT_NONCE,nonce);
                axi_read(ADDR_RESULT_ENGINE,engine);
                offset=nonce-first;
                if(offset>=count || seen[offset]) $fatal(1,"Missing/duplicate nonce %x",nonce);
                if(engine != offset % NUM_ENGINES) $fatal(1,"Wrong lane %d for offset %d",engine,offset);
                seen[offset]=1;
                axi_write(ADDR_RESULT_STATUS,1);
            end
            repeat(100) @(posedge clk);
            axi_read(12'h0ac,after_count);
            if(after_count-before_count != count) $fatal(1,"Batch count mismatch");
            axi_read(ADDR_STATUS,status_word);
            if(status_word[0] || status_word[1] || status_word[3]) $fatal(1,"Batch not drained/overflow");
        end
    endtask

    initial begin
        reg [511:0] header_block0;
        reg [127:0] tail;
        reg [255:0] midstate;
        reg [31:0] word;
        reg [31:0] result_nonce;
        reg [31:0] result_engine;
        integer timeout;
        integer result_idx;

        clk = 1'b0;
        rst_n = 1'b0;
        awaddr = 12'h0;
        awvalid = 1'b0;
        wdata = 32'h0;
        wstrb = 4'h0;
        wvalid = 1'b0;
        bready = 1'b0;
        araddr = 12'h0;
        arvalid = 1'b0;
        rready = 1'b0;
        failures = 0;

        header_block0 = 512'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f;
        tail = 128'h404142434445464748494a4b4c4d4e4f;
        midstate = compress_ref(header_block0, SHA256_IV);
        for (result_idx = 0; result_idx < NUM_ENGINES; result_idx = result_idx + 1) begin
        end

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        axi_read(ADDR_NUM_ENGINES, word);
        if (word != NUM_ENGINES[31:0]) begin
            $display("FAIL NUM_ENGINES got %0d expected %0d", word, NUM_ENGINES);
            failures = failures + 1;
        end

        write_words256(ADDR_MIDSTATE_BASE, midstate);
        axi_read(12'h0b0, word);
        if(word != 32'h01000000) $fatal(1,"Hardware version incorrect");
        axi_write(12'h0b0, 32'hffffffff);
        axi_read(12'h0b0, word);
        if(word != 32'h01000000) $fatal(1,"Hardware version must be read-only");
        axi_read(12'h0b4, word);
        if(word != 0) $fatal(1,"Boot version must reset to unknown");
        axi_write(12'h0b4, 32'h01000000);
        axi_read(12'h0b4, word);
        if(word != 32'h01000000) $fatal(1,"Boot version handoff failed");
        axi_write(12'h0b4, 32'hffffffff, 4'b0010);
        axi_read(12'h0b4, word);
        if(word != 32'h0100ff00) $fatal(1,"Boot version byte strobes failed");
        axi_write(12'h0b4, 32'h01000000);
        write_words128(ADDR_TAIL_BASE, tail);
        write_words256(ADDR_TARGET_BASE, 256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        axi_write(ADDR_NONCE_START, 32'd0);
        axi_write(ADDR_NONCE_COUNT, 32'd4);
        axi_write(ADDR_CONTROL, 32'h00000001);

        for (result_idx = 0; result_idx < NUM_ENGINES; result_idx = result_idx + 1) begin
            timeout = 0;
            word = 32'h0;
            while ((word[1] == 1'b0) && timeout < 2400) begin
                axi_read(ADDR_STATUS, word);
                timeout = timeout + 1;
            end

            if (timeout >= 2400) begin
                $display("FAIL timeout waiting for result %0d", result_idx);
                failures = failures + 1;
            end else begin
                if (!irq) begin
                    $display("FAIL irq not asserted with result %0d available", result_idx);
                    failures = failures + 1;
                end

                axi_read(ADDR_RESULT_NONCE, result_nonce);
                axi_read(ADDR_RESULT_ENGINE, result_engine);

                if (result_nonce != result_idx[31:0]) begin
                    $display("FAIL result %0d nonce got %08h expected %08h",
                             result_idx, result_nonce, result_idx[31:0]);
                    failures = failures + 1;
                end
                if (result_engine != result_idx[31:0]) begin
                    $display("FAIL result %0d engine got %0d expected %0d",
                             result_idx, result_engine, result_idx);
                    failures = failures + 1;
                end
            end

            axi_write(ADDR_RESULT_STATUS, 32'h00000001);
        end

        axi_write(ADDR_RESULT_STATUS, 32'h00000003);
        axi_read(ADDR_RESULT_STATUS, word);
        if (word[0] != 1'b0) begin
            $display("FAIL result valid did not clear");
            failures = failures + 1;
        end

        repeat (1600) @(posedge clk);
        axi_read(12'h0a8, word);
        if(word != 32'h48534831) $fatal(1,"Hash counter capability missing");
        axi_read(12'h0ac, word);
        if(word != 4) $fatal(1,"Expected four completed hashes, got %0d",word);
        // A zero target produces no shares but must still count every hash.
        axi_write(ADDR_CONTROL, 4);
        axi_write(ADDR_RESULT_STATUS, 3);
        write_words256(ADDR_TARGET_BASE, 256'b0);
        axi_write(ADDR_NONCE_COUNT, 5);
        axi_write(ADDR_CONTROL, 1);
        repeat (2600) @(posedge clk);
        axi_read(12'h0ac, word);
        if(word != 9) $fatal(1,"Counter must survive clear and count non-shares: %0d",word);
        axi_read(ADDR_RESULT_STATUS, word);
        if(word[0]) $fatal(1,"Unexpected zero-target share");
        $display("HASH COUNTER TESTS PASSED");
        check_batch(32'hfffffffc, 7);
        check_batch(32'd100, 1);
        check_batch(32'd200, 2);
        check_batch(32'd300, 8);
        check_batch(32'd400, 0);
        // Exercise all divider bits without waiting for billions of hashes.
        if(NUM_ENGINES == 3) begin
            for(integer trial=0;trial<20;trial=trial+1) begin
                word=(trial==0)?32'hffffffff:$urandom;
                axi_write(ADDR_CONTROL,4);
                axi_write(ADDR_NONCE_COUNT,word);
                axi_write(ADDR_CONTROL,1);
                repeat(100) @(posedge clk);
                for(integer lane=0;lane<NUM_ENGINES;lane=lane+1)
                    if(u_dut.engine_nonce_count_q[lane*32 +: 32] != word/3 + ((lane<word%3)?1:0))
                        $fatal(1,"Divider mismatch count=%x lane=%d",word,lane);
                axi_write(ADDR_CONTROL,2);
                repeat(700) @(posedge clk);
            end
            axi_write(ADDR_CONTROL,4);
            axi_write(ADDR_NONCE_COUNT,32'hffffffff);
            axi_write(ADDR_CONTROL,1);
            axi_write(ADDR_CONTROL,2);
            repeat(100) @(posedge clk);
            if(u_dut.load_state_q != 0 || u_dut.engine_busy != 0)
                $fatal(1,"Stop during division launched an engine");
            check_batch(32'd500, 5);
        end
        axi_read(12'h0b4,word);
        if(word != 32'h01000000) $fatal(1,"Job changes cleared boot version");
        @(negedge clk);rst_n=0;
        repeat(4) @(negedge clk);
        rst_n=1;
        axi_read(12'h0b4,word);
        if(word != 0) $fatal(1,"Reset failed to clear boot version");
        $display("NONCE COVERAGE, WRAP, SHORT BATCH AND VERSION TESTS PASSED: lanes=%0d",NUM_ENGINES);
        if (failures == 0) begin
            $display("ALL BITCOIN MINER AXI TESTS PASSED");
            $finish;
        end else begin
            $display("BITCOIN MINER AXI TESTS FAILED: %0d failure(s)", failures);
            $fatal(1);
        end
    end
endmodule
