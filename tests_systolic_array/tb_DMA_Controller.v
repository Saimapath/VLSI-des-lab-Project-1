
// ============================================================
//  Testbench
// ============================================================
module tb_DMA;

    reg         clk, reset;
    reg         enable, enaW, sa_done;
    reg  [31:0] addr_A, addr_B, addr_C;
    reg  [255:0] mem_data;

    // SA result ports (fixed values to verify write-back packing)
    reg [15:0] C00,C01,C02,C03;
    reg [15:0] C10,C11,C12,C13;
    reg [15:0] C20,C21,C22,C23;
    reg [15:0] C30,C31,C32,C33;

    wire         mem_req, mem_we, sa_start, dma_done;
    wire [31:0]  mem_addr;
    wire [255:0] mem_wdata;
    wire [15:0]  A0,A1,A2,A3,B0,B1,B2,B3;

    DMA dut (
        .clk(clk), .reset(reset),
        .enable(enable), .addr_A(addr_A), .addr_B(addr_B),
        .enaW(enaW), .addr_C(addr_C),
        .dma_done(dma_done),
        .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_data(mem_data),
        .A0(A0),.A1(A1),.A2(A2),.A3(A3),
        .B0(B0),.B1(B1),.B2(B2),.B3(B3),
        .sa_start(sa_start), .sa_done(sa_done),
        .C00(C00),.C01(C01),.C02(C02),.C03(C03),
        .C10(C10),.C11(C11),.C12(C12),.C13(C13),
        .C20(C20),.C21(C21),.C22(C22),.C23(C23),
        .C30(C30),.C31(C31),.C32(C32),.C33(C33)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ── Fake memory ──────────────────────────────────────────
    localparam [255:0] MAT_A = {
        16'd16,16'd15,16'd14,16'd13,
        16'd12,16'd11,16'd10,16'd9,
        16'd8, 16'd7, 16'd6, 16'd5,
        16'd4, 16'd3, 16'd2, 16'd1
    };
    localparam [255:0] MAT_B = {
        16'd16,16'd15,16'd14,16'd13,
        16'd12,16'd11,16'd10,16'd9,
        16'd8, 16'd7, 16'd6, 16'd5,
        16'd4, 16'd3, 16'd2, 16'd1
    };

    always @(posedge clk) begin
        if (mem_req) begin
            case (mem_addr)
                32'hAAAA_0000: mem_data <= MAT_A;
                32'hBBBB_0000: mem_data <= MAT_B;
                default:       mem_data <= 256'd0;
            endcase
        end
    end

    // Monitor write-back
    always @(posedge clk) begin
        if (mem_we) begin
            $display("WRITEBACK: addr=%h data=%h", mem_addr, mem_wdata);
        end
    end

    // ── Fake SA result (constant for testbench) ───────────────
    initial begin
        // C = A*B result placeholder values 1..16
        C00=16'd1;  C01=16'd2;  C02=16'd3;  C03=16'd4;
        C10=16'd5;  C11=16'd6;  C12=16'd7;  C13=16'd8;
        C20=16'd9;  C21=16'd10; C22=16'd11; C23=16'd12;
        C30=16'd13; C31=16'd14; C32=16'd15; C33=16'd16;
    end

    // ── Fake SA done: fires 12 cycles after sa_start ─────────
    reg [4:0] sa_cnt;
    always @(posedge clk) begin
        if (!reset) begin sa_done <= 0; sa_cnt <= 0; end
        else begin
            if (sa_start && sa_cnt < 5'd12) sa_cnt <= sa_cnt + 1;
            if (sa_cnt == 5'd12)            sa_done <= 1;
            if (!sa_start) begin sa_done <= 0; sa_cnt <= 0; end
        end
    end

    // ── Stimulus ─────────────────────────────────────────────
    initial begin
        $dumpfile("dma_wb_tb.vcd");
        $dumpvars(0, tb_DMA);

        reset = 0; enable = 0; enaW = 0;
        addr_A = 32'hAAAA_0000;
        addr_B = 32'hBBBB_0000;
        addr_C = 32'hCCCC_0000;
        mem_data = 256'd0;

        @(posedge clk); #1; reset = 1;
        @(posedge clk); #1;

        // Start transfer
        enable = 1; @(posedge clk); #1; enable = 0;

        // Wait for dma_done, then assert enaW after 3 cycles (controller delay)
        wait (dma_done == 1);
        repeat (3) @(posedge clk);
        #1; enaW = 1;
        @(posedge clk); #1; enaW = 0;

        // Wait for write-back to complete
        @(posedge clk); #1;
        $display("=== Transfer + Write-back complete ===");
        #20; $finish;
    end

    // ── Monitor ──────────────────────────────────────────────
    always @(posedge clk) begin
        $display("t=%0t | state_implicit | mem_req=%b mem_we=%b mem_addr=%h | sa_start=%b sa_done=%b dma_done=%b enaW=%b | A=%0d,%0d,%0d,%0d B=%0d,%0d,%0d,%0d",
            $time, mem_req, mem_we, mem_addr,
            sa_start, sa_done, dma_done, enaW,
            A0,A1,A2,A3, B0,B1,B2,B3);
    end

endmodule