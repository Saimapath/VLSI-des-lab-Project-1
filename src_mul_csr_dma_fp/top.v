`timescale 1ns / 1ps

// =====================================================================
// MASTER TOP LEVEL SOC (CPU + FP + DMA/SA + PERIPHERALS + MULT/CSR)
// =====================================================================
module riscv_soc(
    input        clk,
    input        reset,      // Active-LOW Reset
    
    // --- External Physical Pins ---
    input  [7:0] gpio_in,
    output [7:0] gpio_out,
    input        miso,
    output       mosi,
    output       sclk,
    output       cs_n
    
    // input ext_irq
);

    // =========================================================
    // 1. CPU <-> DECODER/MEMORY WIRES
    // =========================================================
    wire [31:0] ImemOut, WriteDataM, ReadDataM;
    wire [29:0] PCF, ALUResultM; 
    wire [3:0]  MemWriteM;
    wire        MemEnM, iMemEnF;

    wire ext_irq;

    // =========================================================
    // 2. PERIPHERAL DECODER WIRES
    // =========================================================
    wire [31:0] bram_read_data, gpio_read_data, spi_read_data;
    wire [3:0]  bram_we;
    wire [12:0] bram_addr;
    wire [31:0] data_addr_full;
    wire        gpio_sel, spi_sel;
    wire        mem_write_gpio, mem_write_spi;

    // =========================================================
    // 3. FP DATAPATH <-> CPU WIRES
    // =========================================================
    wire        FlushD, FlushE;
    wire [31:0] Int_SrcAE;
    wire        fp_ReqIntWriteW;
    wire [31:0] fp_IntDataW;
    wire [4:0]  fp_IntRdW;
    wire        fp_MemWriteM;
    wire [31:0] fp_MemWriteDataM;
    wire        fp_lwstall; 
    wire        fp_sys_stall; 

    // =========================================================
    // 4. DMA ACCELERATOR <-> CPU & MEMORY WIRES
    // =========================================================
    wire        dma_enable, dma_busy, dma_done, dma_source_safe;
    wire [31:0] dma_addr_A, dma_addr_B;
    wire        dma_mem_req, dma_mem_we;
    
    // FIXED WARNING: Resized to 30 bits to match what the DMA module expects
    wire [29:0] dma_mem_addr; 
    wire [255:0] dma_mem_wdata, dma_mem_rdata;

    // =========================================================
    // 5. DMA <-> SYSTOLIC ARRAY WIRES
    // =========================================================
    wire [15:0] A0, A1, A2, A3, B0, B1, B2, B3;
    wire [15:0] C00, C01, C02, C03, C10, C11, C12, C13;
    wire [15:0] C20, C21, C22, C23, C30, C31, C32, C33;
    wire        sa_start, sa_done;

    // =========================================================
    // MODULE INSTANTIATIONS
    // =========================================================

    // --- CORE RISC-V PROCESSOR ---
    riscv_pipelined cpu (
        .clk(clk), .reset(reset), 
        .PCF_out(PCF), .ImemOut(ImemOut),
        .MemWriteM(MemWriteM), .iMemEnF(iMemEnF), .MemEnM(MemEnM),
        .ALUResultM_out(ALUResultM), .WriteDataM(WriteDataM), .ReadDataM(ReadDataM),
        .ext_irq(ext_irq),

        .FlushD_out(FlushD), .FlushE_out(FlushE), .Int_SrcAE_out(Int_SrcAE),
        .fp_sys_stall(fp_sys_stall),        
        .FP_ReqIntWriteW(fp_ReqIntWriteW),  
        .FP_IntDataW(fp_IntDataW),          
        .FP_IntRdW(fp_IntRdW),              
        .FP_MemWriteM(fp_MemWriteM),        
        .FP_MemWriteDataM(fp_MemWriteDataM),
        .fp_lwstall(fp_lwstall),
        
        .dma_enable(dma_enable), .dma_addr_A(dma_addr_A), .dma_addr_B(dma_addr_B),
        .dma_busy(dma_busy), .dma_done(dma_done), .dma_source_safe(dma_source_safe)
    );

    // --- FLOATING-POINT DATAPATH ---
    fp_datapath fpu_pipe (
        .clk(clk), .reset(reset), .ImemOut(ImemOut), 
        .FlushD(FlushD), .FlushE(FlushE), .Int_SrcAE(Int_SrcAE),
        .fp_sys_stall_out(fp_sys_stall),    
        .FP_ReqIntWriteW(fp_ReqIntWriteW), .FP_IntDataW(fp_IntDataW), .FP_IntRdW(fp_IntRdW),
        .fp_lwstall(fp_lwstall), 
        .FP_MemWriteM(fp_MemWriteM), .FP_MemWriteDataM(fp_MemWriteDataM),
        .MemReadDataW(ReadDataM) 
    );

    // --- DMA CONTROLLER ---
    DMA dma_ctrl (
        .clk(clk), .reset(reset),
        .enable(dma_enable), .addr_A(dma_addr_A), .addr_B(dma_addr_B),
        .dma_busy(dma_busy), .dma_done(dma_done), .dma_source_safe(dma_source_safe), 
        
        .mem_req(dma_mem_req), .mem_we(dma_mem_we), 
        .mem_addr(dma_mem_addr), .mem_wdata(dma_mem_wdata), .mem_data(dma_mem_rdata),
        
        .A0(A0), .A1(A1), .A2(A2), .A3(A3),
        .B0(B0), .B1(B1), .B2(B2), .B3(B3),
        .sa_start(sa_start), .sa_done(sa_done),
        
        .C00(C00), .C01(C01), .C02(C02), .C03(C03),
        .C10(C10), .C11(C11), .C12(C12), .C13(C13),
        .C20(C20), .C21(C21), .C22(C22), .C23(C23),
        .C30(C30), .C31(C31), .C32(C32), .C33(C33)
    );

    // --- 4x4 SYSTOLIC ARRAY CORE ---
    SA_Matmul sa_core (
        .clk(clk), .reset(reset), 
        .sa_start(sa_start),
        .A0(A0), .A1(A1), .A2(A2), .A3(A3),
        .B0(B0), .B1(B1), .B2(B2), .B3(B3),
        .C00(C00), .C01(C01), .C02(C02), .C03(C03),
        .C10(C10), .C11(C11), .C12(C12), .C13(C13),
        .C20(C20), .C21(C21), .C22(C22), .C23(C23),
        .C30(C30), .C31(C31), .C32(C32), .C33(C33),
        .valid(sa_done)
    );

    // --- PERIPHERAL DECODER ---
    peripheral_decoder decoder (
        .ALUResultM_out(ALUResultM),
        .MemWriteM(MemWriteM),
        .MemEnM(MemEnM),
        .bram_read_data(bram_read_data),
        .gpio_read_data(gpio_read_data),
        .spi_read_data(spi_read_data),
        .ReadDataM(ReadDataM),
        
        .bram_we(bram_we),
        .bram_addr(bram_addr),
        .data_addr_full(data_addr_full),
        .gpio_sel(gpio_sel),
        .spi_sel(spi_sel),
        .mem_write_gpio(mem_write_gpio),
        .mem_write_spi(mem_write_spi)
    );

    // --- GPIO PERIPHERAL ---
    gpio_int gpio (
        .clk(clk),
        .reset(reset),
        .addr(data_addr_full),
        .write_data(WriteDataM),
        .mem_write(mem_write_gpio),
        .gpio_sel(gpio_sel),
        .read_data(gpio_read_data),
        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .gpio_oe(), // Left Unconnected
        .intr(ext_irq)     // Left Unconnected
    );

    // --- SPI PERIPHERAL ---
    spi_module spi (
        .clk(clk),
        .reset(reset),
        .addr(data_addr_full),
        .write_data(WriteDataM),
        .mem_write(mem_write_spi),
        .spi_sel(spi_sel),
        .read_data(spi_read_data),
        .miso(miso),
        .mosi(mosi),
        .sclk(sclk),
        .cs_n(cs_n),
        .intr()     // Left Unconnected
    );

    // --- INSTRUCTION MEMORY (BRAM) ---
    bram_imem imem (
        .clk(clk), 
        .addr(PCF), 
        .dout(ImemOut), 
        .en(iMemEnF)
    );

    // --- DATA MEMORY (SHARED MATRIX BRAM) ---
    shared_matrix_bram dmem(
        .clk(clk),
        // CPU Port (Routed through decoder)
        .cpu_en(MemEnM),
        .cpu_we(bram_we),         
        .cpu_addr({17'b0, bram_addr}), // Pad the 13-bit decoder address to 30-bit      
        .cpu_wdata(WriteDataM),
        .cpu_rdata(bram_read_data),

        // DMA Port (Directly wired to Accelerator)
        .dma_en(dma_mem_req | dma_mem_we),
        .dma_we(dma_mem_we),
        .dma_addr(dma_mem_addr[12:0]), // Down-cast to match BRAM depth
        .dma_wdata(dma_mem_wdata),
        .dma_rdata(dma_mem_rdata)
    );

endmodule