`timescale 1ns / 1ps

// =====================================================================
// ASYMMETRIC SHARED BRAM MODULE (Vivado & Genus Synthesis Safe)
// True Dual-Port Configuration (Independent CPU and DMA access)
// =====================================================================
module shared_matrix_bram #(
    parameter ROW_DEPTH = 512,
    parameter ROW_ADDR_BITS = 9  // Hardcoded: 2^9 = 512
)(
    input  wire         clk,
    
    // PORT A: RISC-V CPU Interface (32-bit)
    input  wire         cpu_en,
    input  wire [3:0]   cpu_we,       
    input  wire [29:0]  cpu_addr,     
    input  wire [31:0]  cpu_wdata,
    output reg  [31:0]  cpu_rdata,

    // PORT B: DMA Controller Interface (256-bit)
    input  wire         dma_en,
    input  wire         dma_we,       
    input  wire [29:0]  dma_addr,     
    input  wire [255:0] dma_wdata,
    output wire [255:0] dma_rdata
);

    // =========================================================
    // 1. MEMORY BANK DECLARATIONS
    // =========================================================
    (* ram_style = "block" *) reg [31:0] bank0 [0:ROW_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] bank1 [0:ROW_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] bank2 [0:ROW_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] bank3 [0:ROW_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] bank4 [0:ROW_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] bank5 [0:ROW_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] bank6 [0:ROW_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] bank7 [0:ROW_DEPTH-1];

    // =========================================================
    // 2. SAFE HARDWARE INITIALIZATION 
    // =========================================================
    integer i;
    initial begin
        // Only loop from row 3 upwards to prevent Vivado "double-write" errors
        for (i = 3; i < ROW_DEPTH; i = i + 1) begin
            bank0[i] = 0; bank1[i] = 0; bank2[i] = 0; bank3[i] = 0;
            bank4[i] = 0; bank5[i] = 0; bank6[i] = 0; bank7[i] = 0;
        end

        // Row 0: Matrix A -> 2.0s
        bank0[0] = 32'h40004000; bank1[0] = 32'h40004000; bank2[0] = 32'h40004000; bank3[0] = 32'h40004000;
        bank4[0] = 32'h40004000; bank5[0] = 32'h40004000; bank6[0] = 32'h40004000; bank7[0] = 32'h40004000;

        // Row 1: Matrix B -> 1.0s
        bank0[1] = 32'h3C003C00; bank1[1] = 32'h3C003C00; bank2[1] = 32'h3C003C00; bank3[1] = 32'h3C003C00;
        bank4[1] = 32'h3C003C00; bank5[1] = 32'h3C003C00; bank6[1] = 32'h3C003C00; bank7[1] = 32'h3C003C00;

        // Row 2: Matrix C -> -1.0s (Sabotage Data)
        bank0[2] = 32'hBC00BC00; bank1[2] = 32'hBC00BC00; bank2[2] = 32'hBC00BC00; bank3[2] = 32'hBC00BC00;
        bank4[2] = 32'hBC00BC00; bank5[2] = 32'hBC00BC00; bank6[2] = 32'hBC00BC00; bank7[2] = 32'hBC00BC00;
    end

    // =========================================================
    // 3. ADDRESS DECODING & PIPELINE REGISTERS
    // =========================================================
    wire [2:0] bank_sel_cpu = cpu_addr[2:0];
    wire [ROW_ADDR_BITS-1:0] row_addr_cpu = cpu_addr[(ROW_ADDR_BITS + 2) : 3];
    wire [ROW_ADDR_BITS-1:0] row_addr_dma = dma_addr[(ROW_ADDR_BITS + 2) : 3];

    wire cpu_addr_valid = (cpu_addr < (ROW_DEPTH * 8));
    wire dma_addr_valid = (dma_addr < (ROW_DEPTH * 8));

    // Dedicated Read Pipelines for True Dual-Port Inference
    reg [31:0] cpu_out0, cpu_out1, cpu_out2, cpu_out3, cpu_out4, cpu_out5, cpu_out6, cpu_out7;
    reg [31:0] dma_out0, dma_out1, dma_out2, dma_out3, dma_out4, dma_out5, dma_out6, dma_out7;
    
    // Control Signal Pipelines
    reg [2:0]  bank_sel_reg;
    reg        cpu_valid_reg;
    reg        dma_valid_reg;

    // =========================================================
    // 4. TRUE DUAL-PORT MEMORY ACCESS (One block per bank)
    // =========================================================

    // --- BANK 0 ---
    always @(posedge clk) begin
        // PORT A: CPU Write
        if (cpu_en && cpu_addr_valid && (bank_sel_cpu == 3'd0)) begin
            if (cpu_we[0]) bank0[row_addr_cpu][7:0]   <= cpu_wdata[7:0];
            if (cpu_we[1]) bank0[row_addr_cpu][15:8]  <= cpu_wdata[15:8];
            if (cpu_we[2]) bank0[row_addr_cpu][23:16] <= cpu_wdata[23:16];
            if (cpu_we[3]) bank0[row_addr_cpu][31:24] <= cpu_wdata[31:24];
        end

        // PORT B: DMA Write
        if (dma_en && dma_we && dma_addr_valid) begin
            bank0[row_addr_dma] <= dma_wdata[31:0];
        end

        // Independent Read Ports
        cpu_out0 <= bank0[row_addr_cpu];
        dma_out0 <= bank0[row_addr_dma];
    end

    // --- BANK 1 ---
    always @(posedge clk) begin
        // PORT A: CPU Write
        if (cpu_en && cpu_addr_valid && (bank_sel_cpu == 3'd1)) begin
            if (cpu_we[0]) bank1[row_addr_cpu][7:0]   <= cpu_wdata[7:0];
            if (cpu_we[1]) bank1[row_addr_cpu][15:8]  <= cpu_wdata[15:8];
            if (cpu_we[2]) bank1[row_addr_cpu][23:16] <= cpu_wdata[23:16];
            if (cpu_we[3]) bank1[row_addr_cpu][31:24] <= cpu_wdata[31:24];
        end

        // PORT B: DMA Write
        if (dma_en && dma_we && dma_addr_valid) begin
            bank1[row_addr_dma] <= dma_wdata[63:32];
        end

        // Independent Read Ports
        cpu_out1 <= bank1[row_addr_cpu];
        dma_out1 <= bank1[row_addr_dma];
    end

    // --- BANK 2 ---
    always @(posedge clk) begin
        // PORT A: CPU Write
        if (cpu_en && cpu_addr_valid && (bank_sel_cpu == 3'd2)) begin
            if (cpu_we[0]) bank2[row_addr_cpu][7:0]   <= cpu_wdata[7:0];
            if (cpu_we[1]) bank2[row_addr_cpu][15:8]  <= cpu_wdata[15:8];
            if (cpu_we[2]) bank2[row_addr_cpu][23:16] <= cpu_wdata[23:16];
            if (cpu_we[3]) bank2[row_addr_cpu][31:24] <= cpu_wdata[31:24];
        end

        // PORT B: DMA Write
        if (dma_en && dma_we && dma_addr_valid) begin
            bank2[row_addr_dma] <= dma_wdata[95:64];
        end

        // Independent Read Ports
        cpu_out2 <= bank2[row_addr_cpu];
        dma_out2 <= bank2[row_addr_dma];
    end

    // --- BANK 3 ---
    always @(posedge clk) begin
        // PORT A: CPU Write
        if (cpu_en && cpu_addr_valid && (bank_sel_cpu == 3'd3)) begin
            if (cpu_we[0]) bank3[row_addr_cpu][7:0]   <= cpu_wdata[7:0];
            if (cpu_we[1]) bank3[row_addr_cpu][15:8]  <= cpu_wdata[15:8];
            if (cpu_we[2]) bank3[row_addr_cpu][23:16] <= cpu_wdata[23:16];
            if (cpu_we[3]) bank3[row_addr_cpu][31:24] <= cpu_wdata[31:24];
        end

        // PORT B: DMA Write
        if (dma_en && dma_we && dma_addr_valid) begin
            bank3[row_addr_dma] <= dma_wdata[127:96];
        end

        // Independent Read Ports
        cpu_out3 <= bank3[row_addr_cpu];
        dma_out3 <= bank3[row_addr_dma];
    end

    // --- BANK 4 ---
    always @(posedge clk) begin
        // PORT A: CPU Write
        if (cpu_en && cpu_addr_valid && (bank_sel_cpu == 3'd4)) begin
            if (cpu_we[0]) bank4[row_addr_cpu][7:0]   <= cpu_wdata[7:0];
            if (cpu_we[1]) bank4[row_addr_cpu][15:8]  <= cpu_wdata[15:8];
            if (cpu_we[2]) bank4[row_addr_cpu][23:16] <= cpu_wdata[23:16];
            if (cpu_we[3]) bank4[row_addr_cpu][31:24] <= cpu_wdata[31:24];
        end

        // PORT B: DMA Write
        if (dma_en && dma_we && dma_addr_valid) begin
            bank4[row_addr_dma] <= dma_wdata[159:128];
        end

        // Independent Read Ports
        cpu_out4 <= bank4[row_addr_cpu];
        dma_out4 <= bank4[row_addr_dma];
    end

    // --- BANK 5 ---
    always @(posedge clk) begin
        // PORT A: CPU Write
        if (cpu_en && cpu_addr_valid && (bank_sel_cpu == 3'd5)) begin
            if (cpu_we[0]) bank5[row_addr_cpu][7:0]   <= cpu_wdata[7:0];
            if (cpu_we[1]) bank5[row_addr_cpu][15:8]  <= cpu_wdata[15:8];
            if (cpu_we[2]) bank5[row_addr_cpu][23:16] <= cpu_wdata[23:16];
            if (cpu_we[3]) bank5[row_addr_cpu][31:24] <= cpu_wdata[31:24];
        end

        // PORT B: DMA Write
        if (dma_en && dma_we && dma_addr_valid) begin
            bank5[row_addr_dma] <= dma_wdata[191:160];
        end

        // Independent Read Ports
        cpu_out5 <= bank5[row_addr_cpu];
        dma_out5 <= bank5[row_addr_dma];
    end

    // --- BANK 6 ---
    always @(posedge clk) begin
        // PORT A: CPU Write
        if (cpu_en && cpu_addr_valid && (bank_sel_cpu == 3'd6)) begin
            if (cpu_we[0]) bank6[row_addr_cpu][7:0]   <= cpu_wdata[7:0];
            if (cpu_we[1]) bank6[row_addr_cpu][15:8]  <= cpu_wdata[15:8];
            if (cpu_we[2]) bank6[row_addr_cpu][23:16] <= cpu_wdata[23:16];
            if (cpu_we[3]) bank6[row_addr_cpu][31:24] <= cpu_wdata[31:24];
        end

        // PORT B: DMA Write
        if (dma_en && dma_we && dma_addr_valid) begin
            bank6[row_addr_dma] <= dma_wdata[223:192];
        end

        // Independent Read Ports
        cpu_out6 <= bank6[row_addr_cpu];
        dma_out6 <= bank6[row_addr_dma];
    end

    // --- BANK 7 ---
    always @(posedge clk) begin
        // PORT A: CPU Write
        if (cpu_en && cpu_addr_valid && (bank_sel_cpu == 3'd7)) begin
            if (cpu_we[0]) bank7[row_addr_cpu][7:0]   <= cpu_wdata[7:0];
            if (cpu_we[1]) bank7[row_addr_cpu][15:8]  <= cpu_wdata[15:8];
            if (cpu_we[2]) bank7[row_addr_cpu][23:16] <= cpu_wdata[23:16];
            if (cpu_we[3]) bank7[row_addr_cpu][31:24] <= cpu_wdata[31:24];
        end

        // PORT B: DMA Write
        if (dma_en && dma_we && dma_addr_valid) begin
            bank7[row_addr_dma] <= dma_wdata[255:224];
        end

        // Independent Read Ports
        cpu_out7 <= bank7[row_addr_cpu];
        dma_out7 <= bank7[row_addr_dma];
    end

    // =========================================================
    // 5. OUTPUT ROUTING & PIPELINE CONTROL
    // =========================================================
    
    // Register the control signals to align with the 1-cycle BRAM read latency
    always @(posedge clk) begin
        bank_sel_reg <= bank_sel_cpu;
        
        if (cpu_en) begin
            cpu_valid_reg <= cpu_addr_valid;
        end else begin
            cpu_valid_reg <= 1'b0;
        end

        if (dma_en) begin
            dma_valid_reg <= dma_addr_valid;
        end else begin
            dma_valid_reg <= 1'b0;
        end
    end

    // CPU Data Out Multiplexer (Routes the specific bank's CPU port to the output)
    always @(*) begin
        if (cpu_valid_reg) begin
            case (bank_sel_reg)
                3'd0: cpu_rdata = cpu_out0;
                3'd1: cpu_rdata = cpu_out1;
                3'd2: cpu_rdata = cpu_out2;
                3'd3: cpu_rdata = cpu_out3;
                3'd4: cpu_rdata = cpu_out4;
                3'd5: cpu_rdata = cpu_out5;
                3'd6: cpu_rdata = cpu_out6;
                3'd7: cpu_rdata = cpu_out7;
                default: cpu_rdata = 32'h0;
            endcase
        end else begin
            cpu_rdata = 32'hFFFFFFFF; // Safety Trap
        end
    end

    // DMA Data Out Aggregation (Combines all DMA read ports into 256 bits)
    assign dma_rdata = dma_valid_reg ? 
        {dma_out7, dma_out6, dma_out5, dma_out4, dma_out3, dma_out2, dma_out1, dma_out0} : 
        256'h0;

endmodule