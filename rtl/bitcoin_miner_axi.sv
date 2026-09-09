`timescale 1ns/1ps

module bitcoin_miner_axi #(
    parameter int unsigned NUM_ENGINES = 2,
    parameter int unsigned CLUSTER_SIZE = 2,
    parameter int unsigned CLUSTER_FIFO_DEPTH = 2,
    parameter int unsigned AXI_ADDR_WIDTH = 12,
    parameter bit EXPLICIT_DSP_SCHEDULE = 1'b0
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn" *)
    input  wire                       s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                       s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, ADDR_WIDTH 12, DATA_WIDTH 32, HAS_BURST 0, HAS_LOCK 0, HAS_PROT 0, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                       s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output reg                        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]                s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                 s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                       s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg                        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg  [1:0]                 s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg                        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                       s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                       s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg                        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg  [31:0]                s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg  [1:0]                 s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg                        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                       s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq_o INTERRUPT",
       X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire                       irq_o
);
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
    localparam [11:0] ADDR_IRQ_CONTROL   = 12'h0a0;
    localparam int unsigned NUM_CLUSTERS = (NUM_ENGINES + CLUSTER_SIZE - 1) / CLUSTER_SIZE;
    localparam int unsigned ENGINE_INDEX_WIDTH = (NUM_ENGINES <= 1) ? 1 : $clog2(NUM_ENGINES);
    localparam [1:0] LOAD_IDLE   = 2'd0;
    localparam [1:0] LOAD_PREP   = 2'd1;
    localparam [1:0] LOAD_DECODE = 2'd2;
    localparam [1:0] LOAD_START  = 2'd3;

    reg [255:0] midstate_q;
    reg [127:0] header_tail_q;
    reg [255:0] target_q;
    reg [31:0]  nonce_start_q;
    reg [31:0]  nonce_count_q;
    reg         running_q;
    reg         nonce_done_q;
    reg         overflow_q;
    reg         result_valid_q;
    reg         irq_mask_q;
    reg         irq_force_q;
    reg [31:0]  result_nonce_q;
    reg [31:0]  result_engine_q;

    reg start_pulse_q;
    reg stop_pulse_q;
    reg clear_results_q;
    reg [NUM_ENGINES-1:0]    engine_start_q;
    reg [NUM_ENGINES-1:0]    engine_stop_q;
    reg [NUM_ENGINES*32-1:0] engine_nonce_start_q;
    reg [NUM_ENGINES*32-1:0] engine_nonce_count_q;
    reg [1:0] load_state_q;
    reg [ENGINE_INDEX_WIDTH-1:0] load_engine_idx_q;
    reg [ENGINE_INDEX_WIDTH-1:0] load_start_idx_q;
    reg [31:0] load_start_count_q;
    reg load_start_last_q;
    reg [NUM_ENGINES-1:0] load_start_onehot_q;
    reg rd_stage1_valid_q;
    reg [11:0] rd_stage1_addr_q;
    reg rd_stage2_valid_q;
    reg [31:0] rd_stage2_data_q;
    reg wr_stage1_valid_q;
    reg [11:0] wr_stage1_addr_q;
    reg [31:0] wr_stage1_data_q;
    reg [3:0] wr_stage1_strb_q;
    reg wr_stage2_valid_q;
    reg [31:0] wr_stage2_data_q;
    reg [3:0] wr_stage2_strb_q;
    reg [7:0] wr_stage2_midstate_we_q;
    reg [3:0] wr_stage2_tail_we_q;
    reg [7:0] wr_stage2_target_we_q;
    reg wr_stage2_control_we_q;
    reg wr_stage2_nonce_start_we_q;
    reg wr_stage2_nonce_count_we_q;
    reg wr_stage2_result_status_we_q;
    reg wr_stage2_irq_control_we_q;

    wire [NUM_ENGINES-1:0] engine_busy;
    wire [NUM_ENGINES-1:0] engine_done;
    wire [NUM_ENGINES-1:0] engine_result_valid;
    wire [NUM_ENGINES*32-1:0] engine_result_nonce;
    wire [NUM_CLUSTERS-1:0] cluster_valid;
    wire [NUM_CLUSTERS-1:0] cluster_overflow;
    wire [NUM_CLUSTERS-1:0] cluster_pop;
    wire [NUM_CLUSTERS*32-1:0] cluster_engine_id;
    wire [NUM_CLUSTERS*32-1:0] cluster_nonce;

    integer i;
    integer cluster_hit_idx_next;
    reg write_fire;
    reg write_apply;
    reg read_fire;
    reg [11:0] wr_addr;
    reg [NUM_CLUSTERS-1:0] cluster_pop_q;

    assign irq_o = !irq_mask_q &&
                   (irq_force_q || result_valid_q || overflow_q || nonce_done_q);
    assign cluster_pop = cluster_pop_q;

    function automatic [31:0] apply_wstrb(
        input [31:0] old_data,
        input [31:0] new_data,
        input [3:0]  strobe
    );
        integer byte_idx;
        begin
            apply_wstrb = old_data;
            for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
                if (strobe[byte_idx]) begin
                    apply_wstrb[byte_idx*8 +: 8] = new_data[byte_idx*8 +: 8];
                end
            end
        end
    endfunction

    function automatic [31:0] read_reg(input [11:0] addr);
        integer idx;
        begin
            read_reg = 32'h00000000;
            if ((addr >= ADDR_MIDSTATE_BASE) && (addr < ADDR_MIDSTATE_BASE + 12'h020)) begin
                idx = ({20'h0, addr} - {20'h0, ADDR_MIDSTATE_BASE}) >> 2;
                read_reg = midstate_q[255 - (idx * 32) -: 32];
            end else if ((addr >= ADDR_TAIL_BASE) && (addr < ADDR_TAIL_BASE + 12'h010)) begin
                idx = ({20'h0, addr} - {20'h0, ADDR_TAIL_BASE}) >> 2;
                read_reg = header_tail_q[127 - (idx * 32) -: 32];
            end else if ((addr >= ADDR_TARGET_BASE) && (addr < ADDR_TARGET_BASE + 12'h020)) begin
                idx = ({20'h0, addr} - {20'h0, ADDR_TARGET_BASE}) >> 2;
                read_reg = target_q[255 - (idx * 32) -: 32];
            end else begin
                case (addr)
                    ADDR_CONTROL:       read_reg = 32'h00000000;
                    ADDR_STATUS:        read_reg = {28'h0, overflow_q, nonce_done_q, result_valid_q, running_q};
                    ADDR_NUM_ENGINES:   read_reg = NUM_ENGINES[31:0];
                    ADDR_NONCE_START:   read_reg = nonce_start_q;
                    ADDR_NONCE_COUNT:   read_reg = nonce_count_q;
                    ADDR_RESULT_NONCE:  read_reg = result_nonce_q;
                    ADDR_RESULT_ENGINE: read_reg = result_engine_q;
                    ADDR_RESULT_STATUS: read_reg = {30'h0, overflow_q, result_valid_q};
                    ADDR_IRQ_CONTROL:   read_reg = {30'h0, irq_force_q, irq_mask_q};
                    default:            read_reg = 32'h00000000;
                endcase
            end
        end
    endfunction

    function automatic [31:0] engine_work_count(
        input [31:0] count,
        input [31:0] engine_index
    );
        begin
            engine_work_count = (count > engine_index) ?
                                (((count - 32'd1 - engine_index) / NUM_ENGINES) + 32'd1) :
                                32'd0;
        end
    endfunction

    function automatic [NUM_ENGINES-1:0] engine_onehot(
        input [ENGINE_INDEX_WIDTH-1:0] engine_index
    );
        integer engine_idx;
        begin
            engine_onehot = {NUM_ENGINES{1'b0}};
            for (engine_idx = 0; engine_idx < NUM_ENGINES; engine_idx = engine_idx + 1) begin
                if (engine_index == engine_idx[ENGINE_INDEX_WIDTH-1:0]) begin
                    engine_onehot[engine_idx] = 1'b1;
                end
            end
        end
    endfunction

    genvar gen_idx;
    generate
        for (gen_idx = 0; gen_idx < NUM_ENGINES; gen_idx = gen_idx + 1) begin : g_engines
            bitcoin_hash_engine #(
                .NONCE_STRIDE(NUM_ENGINES),
                .EXPLICIT_DSP_SCHEDULE(EXPLICIT_DSP_SCHEDULE)
            ) u_engine (
                .clk_i(s_axi_aclk),
                .rst_ni(s_axi_aresetn),
                .start_i(engine_start_q[gen_idx]),
                .stop_i(engine_stop_q[gen_idx]),
                .midstate_i(midstate_q),
                .header_tail_i(header_tail_q),
                .target_i(target_q),
                .nonce_start_i(engine_nonce_start_q[gen_idx*32 +: 32]),
                .nonce_count_i(engine_nonce_count_q[gen_idx*32 +: 32]),
                .busy_o(engine_busy[gen_idx]),
                .done_o(engine_done[gen_idx]),
                .result_valid_o(engine_result_valid[gen_idx]),
                .result_nonce_o(engine_result_nonce[gen_idx*32 +: 32])
            );
        end
    endgenerate

    genvar cluster_idx;
    genvar local_idx;
    generate
        for (cluster_idx = 0; cluster_idx < NUM_CLUSTERS; cluster_idx = cluster_idx + 1) begin : g_clusters
            wire [CLUSTER_SIZE-1:0] local_valid;
            wire [CLUSTER_SIZE*32-1:0] local_nonce;

            for (local_idx = 0; local_idx < CLUSTER_SIZE; local_idx = local_idx + 1) begin : g_cluster_inputs
                localparam int unsigned ENGINE_INDEX = (cluster_idx * CLUSTER_SIZE) + local_idx;
                if (ENGINE_INDEX < NUM_ENGINES) begin : g_active_engine
                    assign local_valid[local_idx] = engine_result_valid[ENGINE_INDEX];
                    assign local_nonce[local_idx*32 +: 32] = engine_result_nonce[ENGINE_INDEX*32 +: 32];
                end else begin : g_inactive_engine
                    assign local_valid[local_idx] = 1'b0;
                    assign local_nonce[local_idx*32 +: 32] = 32'h0;
                end
            end

            bitcoin_result_cluster_fifo #(
                .CLUSTER_INDEX(cluster_idx),
                .CLUSTER_SIZE(CLUSTER_SIZE),
                .FIFO_DEPTH(CLUSTER_FIFO_DEPTH)
            ) u_result_fifo (
                .clk_i(s_axi_aclk),
                .rst_ni(s_axi_aresetn),
                .clear_i(stop_pulse_q || start_pulse_q || clear_results_q),
                .pop_i(cluster_pop[cluster_idx]),
                .engine_valid_i(local_valid),
                .engine_nonce_i(local_nonce),
                .valid_o(cluster_valid[cluster_idx]),
                .engine_id_o(cluster_engine_id[cluster_idx*32 +: 32]),
                .nonce_o(cluster_nonce[cluster_idx*32 +: 32]),
                .overflow_o(cluster_overflow[cluster_idx])
            );
        end
    endgenerate

    always @(*) begin
        write_fire = s_axi_awvalid && s_axi_wvalid && !wr_stage1_valid_q && !wr_stage2_valid_q && !s_axi_bvalid;
        write_apply = wr_stage2_valid_q && !s_axi_bvalid;
        read_fire = s_axi_arvalid && !rd_stage1_valid_q && !rd_stage2_valid_q && !s_axi_rvalid;
        wr_addr = wr_stage1_addr_q;
        cluster_hit_idx_next = -1;
        for (i = 0; i < NUM_CLUSTERS; i = i + 1) begin
            if ((cluster_hit_idx_next < 0) && cluster_valid[i]) begin
                cluster_hit_idx_next = i;
            end
        end
    end

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata <= 32'h0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            midstate_q <= 256'h0;
            header_tail_q <= 128'h0;
            target_q <= 256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            nonce_start_q <= 32'h0;
            nonce_count_q <= 32'h0;
            running_q <= 1'b0;
            nonce_done_q <= 1'b0;
            overflow_q <= 1'b0;
            result_valid_q <= 1'b0;
            irq_mask_q <= 1'b0;
            irq_force_q <= 1'b0;
            result_nonce_q <= 32'h0;
            result_engine_q <= 32'h0;
            start_pulse_q <= 1'b0;
            stop_pulse_q <= 1'b0;
            clear_results_q <= 1'b0;
            engine_start_q <= {NUM_ENGINES{1'b0}};
            engine_stop_q <= {NUM_ENGINES{1'b0}};
            engine_nonce_start_q <= {NUM_ENGINES*32{1'b0}};
            engine_nonce_count_q <= {NUM_ENGINES*32{1'b0}};
            load_state_q <= LOAD_IDLE;
            load_engine_idx_q <= {ENGINE_INDEX_WIDTH{1'b0}};
            load_start_idx_q <= {ENGINE_INDEX_WIDTH{1'b0}};
            load_start_count_q <= 32'h0;
            load_start_last_q <= 1'b0;
            load_start_onehot_q <= {NUM_ENGINES{1'b0}};
            rd_stage1_valid_q <= 1'b0;
            rd_stage1_addr_q <= 12'h000;
            rd_stage2_valid_q <= 1'b0;
            rd_stage2_data_q <= 32'h0;
            wr_stage1_valid_q <= 1'b0;
            wr_stage1_addr_q <= 12'h000;
            wr_stage1_data_q <= 32'h0;
            wr_stage1_strb_q <= 4'h0;
            wr_stage2_valid_q <= 1'b0;
            wr_stage2_data_q <= 32'h0;
            wr_stage2_strb_q <= 4'h0;
            wr_stage2_midstate_we_q <= 8'h00;
            wr_stage2_tail_we_q <= 4'h0;
            wr_stage2_target_we_q <= 8'h00;
            wr_stage2_control_we_q <= 1'b0;
            wr_stage2_nonce_start_we_q <= 1'b0;
            wr_stage2_nonce_count_we_q <= 1'b0;
            wr_stage2_result_status_we_q <= 1'b0;
            wr_stage2_irq_control_we_q <= 1'b0;
            cluster_pop_q <= {NUM_CLUSTERS{1'b0}};
        end else begin
            s_axi_awready <= write_fire;
            s_axi_wready <= write_fire;
            s_axi_arready <= read_fire;
            start_pulse_q <= 1'b0;
            stop_pulse_q <= 1'b0;
            clear_results_q <= 1'b0;
            engine_start_q <= {NUM_ENGINES{1'b0}};
            engine_stop_q <= {NUM_ENGINES{1'b0}};
            cluster_pop_q <= {NUM_CLUSTERS{1'b0}};

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            if (write_fire) begin
                wr_stage1_valid_q <= 1'b1;
                wr_stage1_addr_q <= {s_axi_awaddr[11:2], s_axi_awaddr[1:0] & 2'b00};
                wr_stage1_data_q <= s_axi_wdata;
                wr_stage1_strb_q <= s_axi_wstrb;
            end

            if (wr_stage1_valid_q && !wr_stage2_valid_q && !s_axi_bvalid) begin
                wr_stage2_valid_q <= 1'b1;
                wr_stage2_data_q <= wr_stage1_data_q;
                wr_stage2_strb_q <= wr_stage1_strb_q;
                wr_stage2_midstate_we_q <= 8'h00;
                wr_stage2_tail_we_q <= 4'h0;
                wr_stage2_target_we_q <= 8'h00;
                wr_stage2_control_we_q <= 1'b0;
                wr_stage2_nonce_start_we_q <= 1'b0;
                wr_stage2_nonce_count_we_q <= 1'b0;
                wr_stage2_result_status_we_q <= 1'b0;
                wr_stage2_irq_control_we_q <= 1'b0;
                wr_stage1_valid_q <= 1'b0;

                if ((wr_addr >= ADDR_MIDSTATE_BASE) && (wr_addr < ADDR_MIDSTATE_BASE + 12'h020)) begin
                    i = ({20'h0, wr_addr} - {20'h0, ADDR_MIDSTATE_BASE}) >> 2;
                    wr_stage2_midstate_we_q[i] <= 1'b1;
                end else if ((wr_addr >= ADDR_TAIL_BASE) && (wr_addr < ADDR_TAIL_BASE + 12'h010)) begin
                    i = ({20'h0, wr_addr} - {20'h0, ADDR_TAIL_BASE}) >> 2;
                    wr_stage2_tail_we_q[i] <= 1'b1;
                end else if ((wr_addr >= ADDR_TARGET_BASE) && (wr_addr < ADDR_TARGET_BASE + 12'h020)) begin
                    i = ({20'h0, wr_addr} - {20'h0, ADDR_TARGET_BASE}) >> 2;
                    wr_stage2_target_we_q[i] <= 1'b1;
                end else begin
                    case (wr_addr)
                        ADDR_CONTROL: begin
                            wr_stage2_control_we_q <= 1'b1;
                        end
                        ADDR_NONCE_START: begin
                            wr_stage2_nonce_start_we_q <= 1'b1;
                        end
                        ADDR_NONCE_COUNT: begin
                            wr_stage2_nonce_count_we_q <= 1'b1;
                        end
                        ADDR_RESULT_STATUS: begin
                            wr_stage2_result_status_we_q <= 1'b1;
                        end
                        ADDR_IRQ_CONTROL: begin
                            wr_stage2_irq_control_we_q <= 1'b1;
                        end
                        default: begin
                        end
                    endcase
                end
            end

            if (read_fire) begin
                rd_stage1_valid_q <= 1'b1;
                rd_stage1_addr_q <= {s_axi_araddr[11:2], s_axi_araddr[1:0] & 2'b00};
            end

            if (rd_stage1_valid_q) begin
                rd_stage2_valid_q <= 1'b1;
                rd_stage2_data_q <= read_reg(rd_stage1_addr_q);
                rd_stage1_valid_q <= 1'b0;
            end

            if (rd_stage2_valid_q && !s_axi_rvalid) begin
                s_axi_rdata <= rd_stage2_data_q;
                s_axi_rresp <= 2'b00;
                s_axi_rvalid <= 1'b1;
                rd_stage2_valid_q <= 1'b0;
            end

            if (write_apply) begin
                s_axi_bresp <= 2'b00;
                s_axi_bvalid <= 1'b1;
                wr_stage2_valid_q <= 1'b0;

                for (i = 0; i < 8; i = i + 1) begin
                    if (wr_stage2_midstate_we_q[i]) begin
                        midstate_q[255 - (i * 32) -: 32] <= apply_wstrb(midstate_q[255 - (i * 32) -: 32], wr_stage2_data_q, wr_stage2_strb_q);
                    end
                    if (wr_stage2_target_we_q[i]) begin
                        target_q[255 - (i * 32) -: 32] <= apply_wstrb(target_q[255 - (i * 32) -: 32], wr_stage2_data_q, wr_stage2_strb_q);
                    end
                end

                for (i = 0; i < 4; i = i + 1) begin
                    if (wr_stage2_tail_we_q[i]) begin
                        header_tail_q[127 - (i * 32) -: 32] <= apply_wstrb(header_tail_q[127 - (i * 32) -: 32], wr_stage2_data_q, wr_stage2_strb_q);
                    end
                end

                if (wr_stage2_control_we_q) begin
                    if (wr_stage2_data_q[0] && (load_state_q == LOAD_IDLE)) begin
                        start_pulse_q <= 1'b1;
                        running_q <= 1'b1;
                        nonce_done_q <= 1'b0;
                        overflow_q <= 1'b0;
                        result_valid_q <= 1'b0;
                        load_state_q <= LOAD_PREP;
                        load_engine_idx_q <= {ENGINE_INDEX_WIDTH{1'b0}};
                    end
                    if (wr_stage2_data_q[1]) begin
                        stop_pulse_q <= 1'b1;
                        engine_stop_q <= {NUM_ENGINES{1'b1}};
                        load_state_q <= LOAD_IDLE;
                        running_q <= 1'b0;
                        nonce_done_q <= 1'b1;
                    end
                    if (wr_stage2_data_q[2]) begin
                        clear_results_q <= 1'b1;
                        result_valid_q <= 1'b0;
                        overflow_q <= 1'b0;
                        nonce_done_q <= 1'b0;
                    end
                end

                if (wr_stage2_nonce_start_we_q) begin
                    nonce_start_q <= apply_wstrb(nonce_start_q, wr_stage2_data_q, wr_stage2_strb_q);
                end
                if (wr_stage2_nonce_count_we_q) begin
                    nonce_count_q <= apply_wstrb(nonce_count_q, wr_stage2_data_q, wr_stage2_strb_q);
                end
                if (wr_stage2_result_status_we_q) begin
                    if (wr_stage2_data_q[0]) begin
                        result_valid_q <= 1'b0;
                    end
                    if (wr_stage2_data_q[1]) begin
                        overflow_q <= 1'b0;
                    end
                end
                if (wr_stage2_irq_control_we_q && wr_stage2_strb_q[0]) begin
                    irq_mask_q <= wr_stage2_data_q[0];
                    irq_force_q <= wr_stage2_data_q[1];
                end
            end

            case (load_state_q)
                LOAD_IDLE: begin
                end

                LOAD_PREP: begin
                    load_start_idx_q <= load_engine_idx_q;
                    load_start_count_q <= engine_work_count(
                        nonce_count_q,
                        {{(32-ENGINE_INDEX_WIDTH){1'b0}}, load_engine_idx_q}
                    );
                    load_start_last_q <= (load_engine_idx_q == NUM_ENGINES[ENGINE_INDEX_WIDTH-1:0] - {{(ENGINE_INDEX_WIDTH-1){1'b0}}, 1'b1});
                    engine_nonce_start_q[load_engine_idx_q*32 +: 32] <= nonce_start_q + {{(32-ENGINE_INDEX_WIDTH){1'b0}}, load_engine_idx_q};
                    engine_nonce_count_q[load_engine_idx_q*32 +: 32] <= engine_work_count(
                        nonce_count_q,
                        {{(32-ENGINE_INDEX_WIDTH){1'b0}}, load_engine_idx_q}
                    );
                    load_state_q <= LOAD_DECODE;
                end

                LOAD_DECODE: begin
                    load_start_onehot_q <= (load_start_count_q != 32'd0) ?
                                           engine_onehot(load_start_idx_q) :
                                           {NUM_ENGINES{1'b0}};
                    load_state_q <= LOAD_START;
                end

                LOAD_START: begin
                    engine_start_q <= load_start_onehot_q;

                    if (load_start_last_q) begin
                        load_state_q <= LOAD_IDLE;
                    end else begin
                        load_engine_idx_q <= load_engine_idx_q + {{(ENGINE_INDEX_WIDTH-1){1'b0}}, 1'b1};
                        load_state_q <= LOAD_PREP;
                    end
                end

                default: begin
                    load_state_q <= LOAD_IDLE;
                end
            endcase

            if (|cluster_overflow) begin
                overflow_q <= 1'b1;
            end

            if (!result_valid_q && (cluster_hit_idx_next >= 0)) begin
                result_valid_q <= 1'b1;
                result_engine_q <= cluster_engine_id[cluster_hit_idx_next*32 +: 32];
                result_nonce_q <= cluster_nonce[cluster_hit_idx_next*32 +: 32];
                cluster_pop_q[cluster_hit_idx_next] <= 1'b1;
            end

            if (running_q && (load_state_q == LOAD_IDLE) &&
                ((engine_busy == {NUM_ENGINES{1'b0}}) || (engine_done == {NUM_ENGINES{1'b1}})) &&
                !start_pulse_q) begin
                running_q <= 1'b0;
                nonce_done_q <= 1'b1;
            end
        end
    end
endmodule
