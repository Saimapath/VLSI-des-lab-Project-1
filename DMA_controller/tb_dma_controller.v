// =============================================================================
// Testbench for dma_controller
// Tests: A = [[1,2,0,0],[3,4,0,0],[0,0,1,0],[0,0,0,2]]
//        B = [[5,6,0,0],[7,8,0,0],[0,0,3,0],[0,0,0,4]]
//        Expected C[0][0] = 1*5+2*7 = 19, C[0][1] = 1*6+2*8 = 22, etc.
// =============================================================================

`timescale 1ns/1ps

module tb_dma_controller;

    parameter DATA_WIDTH = 16;
    parameter MAT_SIZE   = 4;
    parameter ADDR_WIDTH = 32;
    parameter MEM_WIDTH  = 256;
    parameter N          = MAT_SIZE;

    // DUT signals
    reg                   clk, rst_n;
    reg                   cpu_start;
    reg  [ADDR_WIDTH-1:0] cpu_addr_a, cpu_addr_b;
    wire                  dma_done;
    wire                  mem_req;
    wire [ADDR_WIDTH-1:0] mem_addr;
    reg                   mem_ack;
    reg  [MEM_WIDTH-1:0]  mem_data;
    wire                  sa_en;
    wire [63:0]           sa_row_data, sa_col_data;

    // DUT
    dma_controller #(
        .DATA_WIDTH(DATA_WIDTH),
        .MAT_SIZE  (MAT_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MEM_WIDTH (MEM_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .cpu_start   (cpu_start),
        .cpu_addr_a  (cpu_addr_a),
        .cpu_addr_b  (cpu_addr_b),
        .dma_done    (dma_done),
        .mem_req     (mem_req),
        .mem_addr    (mem_addr),
        .mem_ack     (mem_ack),
        .mem_data    (mem_data),
        .sa_en       (sa_en),
        .sa_row_data (sa_row_data),
        .sa_col_data (sa_col_data)
    );

    // Clock: 10ns period
    always #5 clk = ~clk;

    // Matrix A = [[1,2,0,0],[3,4,0,0],[0,0,1,0],[0,0,0,2]] row-major
    // Element order in 256-bit word: [15:0]=A[0][0]=1, [31:16]=A[0][1]=2, ...
    reg [MEM_WIDTH-1:0] mem_a, mem_b;
    integer i;

    task build_matrix_word;
        input [15:0] e0,e1,e2,e3,e4,e5,e6,e7,e8,e9,e10,e11,e12,e13,e14,e15;
        output [MEM_WIDTH-1:0] word;
        begin
            word = {e15,e14,e13,e12, e11,e10,e9,e8, e7,e6,e5,e4, e3,e2,e1,e0};
        end
    endtask

    initial begin
        // Build A word: row-major [1,2,0,0, 3,4,0,0, 0,0,1,0, 0,0,0,2]
        build_matrix_word(16'd1,16'd2,16'd0,16'd0,
                          16'd3,16'd4,16'd0,16'd0,
                          16'd0,16'd0,16'd1,16'd0,
                          16'd0,16'd0,16'd0,16'd2,
                          mem_a);

        // Build B word: [5,6,0,0, 7,8,0,0, 0,0,3,0, 0,0,0,4]
        build_matrix_word(16'd5,16'd6,16'd0,16'd0,
                          16'd7,16'd8,16'd0,16'd0,
                          16'd0,16'd0,16'd3,16'd0,
                          16'd0,16'd0,16'd0,16'd4,
                          mem_b);
    end

    // Simple memory model: 1-cycle latency
    reg pending_ack;
    reg [MEM_WIDTH-1:0] pending_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ack      <= 0;
            mem_data     <= 0;
            pending_ack  <= 0;
        end else begin
            mem_ack <= 0;
            if (mem_req && !mem_ack) begin
                // Return A or B based on address
                if (mem_addr == 32'hAAAA_0000)
                    mem_data <= mem_a;
                else
                    mem_data <= mem_b;
                mem_ack <= 1;
            end
        end
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_dma.vcd");
        $dumpvars(0, tb_dma_controller);
    end

    // Monitor SA inputs
    integer cycle_cnt;
    always @(posedge clk) begin
        if (sa_en) begin
            $display("SA cycle %0d | row_data=%016h  col_data=%016h",
                     cycle_cnt,
                     sa_row_data, sa_col_data);
            $display("         row: [%0d,%0d,%0d,%0d]  col: [%0d,%0d,%0d,%0d]",
                     sa_row_data[15:0],  sa_row_data[31:16],
                     sa_row_data[47:32], sa_row_data[63:48],
                     sa_col_data[15:0],  sa_col_data[31:16],
                     sa_col_data[47:32], sa_col_data[63:48]);
            cycle_cnt = cycle_cnt + 1;
        end
    end

    // Main test
    initial begin
        clk         = 0;
        rst_n       = 0;
        cpu_start   = 0;
        cpu_addr_a  = 32'hAAAA_0000;
        cpu_addr_b  = 32'hBBBB_0000;
        mem_ack     = 0;
        mem_data    = 0;
        cycle_cnt   = 0;

        @(posedge clk); #1;
        rst_n = 1;

        @(posedge clk); #1;
        $display("\n=== DMA Controller Test ===");
        $display("Matrix A: [[1,2,0,0],[3,4,0,0],[0,0,1,0],[0,0,0,2]]");
        $display("Matrix B: [[5,6,0,0],[7,8,0,0],[0,0,3,0],[0,0,0,4]]");
        $display("Expected C[0][0]=19, C[0][1]=22, C[1][0]=43, C[1][1]=50\n");

        // Start DMA
        cpu_start = 1;
        @(posedge clk); #1;
        cpu_start = 0;

        // Wait for done
        @(posedge dma_done);
        $display("\n=== DMA done signal received ===\n");

        #20;
        $finish;
    end

endmodule