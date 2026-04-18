
// ============================================================
//  Testbench for top_sa_mul
// ============================================================
module tb_top_sa_mul;

    reg         clk, reset;
    reg         enable, enaW;
    reg  [31:0] addr_A, addr_B, addr_C;

    wire        dma_done;
    wire        mem_req, mem_we;
    wire [31:0] mem_addr;
    wire [255:0] mem_wdata;
    reg  [255:0] mem_data;

    // ── DUT ──────────────────────────────────────────────
    top_sa_mul dut (
        .clk      (clk),    .reset  (reset),
        .enable   (enable), .addr_A (addr_A),
        .addr_B   (addr_B), .enaW   (enaW),
        .addr_C   (addr_C), .dma_done(dma_done),
        .mem_req  (mem_req),.mem_we  (mem_we),
        .mem_addr (mem_addr),.mem_wdata(mem_wdata),
        .mem_data (mem_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ── Simple SRAM model (256-bit wide, 1-cycle read latency) ──
    //
    //  Matrix A (row-major, integer values 1..16):
    //    A = | 1  2  3  4 |
    //        | 5  6  7  8 |
    //        | 9  10 11 12|
    //        |13  14 15 16|
    //
    //  Matrix B (column-major in memory, same values):
    //    B = | 1  5  9  13|
    //        | 2  6  10 14|
    //        | 3  7  11 15|
    //        | 4  8  12 16|
    //  Stored col-major so B[0..3][col] is contiguous.
    //
    //  Expected C = A*B:
    //    C[0][0] = 1*1 + 2*2 + 3*3 + 4*4   = 30
    //    C[0][1] = 1*5 + 2*6 + 3*7 + 4*8   = 70
    //    ... etc.

    localparam [255:0] MAT_A = {
        16'd16, 16'd15, 16'd14, 16'd13,   // A[3][3..0]  MSB end
        16'd12, 16'd11, 16'd10, 16'd9,    // A[2][3..0]
        16'd8,  16'd7,  16'd6,  16'd5,    // A[1][3..0]
        16'd4,  16'd3,  16'd2,  16'd1     // A[0][3..0]  LSB end
    };

    // B column-major: col0=1,2,3,4 col1=5,6,7,8 col2=9,10,11,12 col3=13,14,15,16
    localparam [255:0] MAT_B = {
        16'd16, 16'd15, 16'd14, 16'd13,   // col3: B[3..0][3]  MSB end
        16'd12, 16'd11, 16'd10, 16'd9,    // col2: B[3..0][2]
        16'd8,  16'd7,  16'd6,  16'd5,    // col1: B[3..0][1]
        16'd4,  16'd3,  16'd2,  16'd1     // col0: B[3..0][0]  LSB end
    };

    // Synchronous SRAM: respond on the cycle AFTER mem_req
    always @(posedge clk) begin
        mem_data <= 256'd0;
        if (mem_req) begin
            case (mem_addr)
                32'hAAAA_0000 : mem_data <= MAT_A;
                32'hBBBB_0000 : mem_data <= MAT_B;
                default       : mem_data <= 256'd0;
            endcase
        end
    end

    // Monitor write-back: decode mat_C from mem_wdata
    always @(posedge clk) begin
        if (mem_we) begin
            $display("─────────────────────────────────────────────");
            $display("WRITEBACK to addr %h", mem_addr);
            $display("C[0][0..3] = %0d %0d %0d %0d",
                mem_wdata[15:0],  mem_wdata[31:16],
                mem_wdata[47:32], mem_wdata[63:48]);
            $display("C[1][0..3] = %0d %0d %0d %0d",
                mem_wdata[79:64],  mem_wdata[95:80],
                mem_wdata[111:96], mem_wdata[127:112]);
            $display("C[2][0..3] = %0d %0d %0d %0d",
                mem_wdata[143:128], mem_wdata[159:144],
                mem_wdata[175:160], mem_wdata[191:176]);
            $display("C[3][0..3] = %0d %0d %0d %0d",
                mem_wdata[207:192], mem_wdata[223:208],
                mem_wdata[239:224], mem_wdata[255:240]);
            $display("─────────────────────────────────────────────");
        end
    end

    // ── Stimulus ─────────────────────────────────────────
    initial begin
        $dumpfile("top_matmul_tb.vcd");
        $dumpvars(0, tb_top_sa_mul);

        // Initialise
        reset  = 0; enable = 0; enaW = 0;
        addr_A = 32'hAAAA_0000;
        addr_B = 32'hBBBB_0000;
        addr_C = 32'hCCCC_0000;
        mem_data = 256'd0;

        // Release reset after 2 cycles
        repeat(2) @(posedge clk); #1;
        reset = 1;
        repeat(2) @(posedge clk); #1;

        // ── Transfer 1: start computation ────────────────
        $display("=== Starting matmul transfer ===");
        enable = 1;
        @(posedge clk); #1;
        enable = 0;

        // Wait for DMA to finish SA computation
        wait (dma_done == 1);
        $display("t=%0t : dma_done asserted — SA result ready", $time);

        // Simulate controller taking 3 cycles before authorising write-back
        repeat(3) @(posedge clk); #1;
        $display("t=%0t : controller asserting enaW", $time);
        enaW = 1;
        @(posedge clk); #1;
        enaW = 0;

        // Wait for write-back to complete, then go idle
        repeat(3) @(posedge clk); #1;

        // ── Transfer 2: back-to-back second matmul ───────
        $display("=== Starting second matmul transfer ===");
        enable = 1;
        @(posedge clk); #1;
        enable = 0;

        wait (dma_done == 1);
        $display("t=%0t : second dma_done", $time);
        @(posedge clk); #1;
        enaW = 1;
        @(posedge clk); #1;
        enaW = 0;

        repeat(3) @(posedge clk); #1;
        $display("=== All transfers complete ===");
        #20; $finish;
    end

    // ── Cycle-by-cycle monitor ───────────────────────────
    always @(posedge clk) begin
        $display("t=%0t | enable=%b enaW=%b | mem_req=%b mem_we=%b mem_addr=%h | dma_done=%b | sa_start=%b sa_done=%b",
            $time, enable, enaW,
            mem_req, mem_we, mem_addr,
            dma_done,
            dut.sa_start, dut.sa_done);
    end

endmodule