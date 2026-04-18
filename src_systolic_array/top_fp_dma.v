 `timescale 1ns / 1ps

// =====================================================================
// TOP LEVEL SOC
// =====================================================================
module riscv_soc(
    input clk,
    input reset
);
    // =========================================================
    // STANDARD CPU MEMORY WIRES
    // =========================================================
    wire [31:0] ImemOut, WriteDataM, ReadDataM;
    wire [29:0] PCF, ALUResultM; 
    wire [3:0]  MemWriteM;
    wire        MemEnM, iMemEnF;
    
    // =========================================================
    // FP DATAPATH <-> CPU WIRES
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
    // DMA ACCELERATOR <-> CPU WIRES
    // =========================================================
    wire        dma_enable, dma_busy, dma_done;
    wire        dma_source_safe; // ---> NEW WIRE
    wire [31:0] dma_addr_A, dma_addr_B;
    
    // =========================================================
    // DMA ACCELERATOR <-> SYSTOLIC ARRAY WIRES
    // =========================================================
    wire [15:0] A0, A1, A2, A3, B0, B1, B2, B3;
    wire [15:0] C00, C01, C02, C03, C10, C11, C12, C13;
    wire [15:0] C20, C21, C22, C23, C30, C31, C32, C33;
    wire        sa_start, sa_done;
    
    // =========================================================
    // DMA ACCELERATOR <-> SHARED MATRIX BRAM WIRES
    // =========================================================
    wire        dma_mem_req, dma_mem_we;
    wire [31:0] dma_mem_addr;
    wire [255:0] dma_mem_wdata, dma_mem_rdata;

    // =========================================================
    // 1. CORE RISC-V PROCESSOR
    // =========================================================
    riscv_pipelined cpu (
        .clk(clk), .reset(reset), .PCF_out(PCF), .ImemOut(ImemOut),
        .MemWriteM(MemWriteM), .iMemEnF(iMemEnF), .MemEnM(MemEnM),
        .ALUResultM_out(ALUResultM), .WriteDataM(WriteDataM), .ReadDataM(ReadDataM),

        .FlushD_out(FlushD),
        .FlushE_out(FlushE),
        .Int_SrcAE_out(Int_SrcAE),
        .fp_sys_stall(fp_sys_stall),        
        .FP_ReqIntWriteW(fp_ReqIntWriteW),  
        .FP_IntDataW(fp_IntDataW),          
        .FP_IntRdW(fp_IntRdW),              
        .FP_MemWriteM(fp_MemWriteM),        
        .FP_MemWriteDataM(fp_MemWriteDataM),
        .fp_lwstall(fp_lwstall),
        
        .dma_enable(dma_enable),
        .dma_addr_A(dma_addr_A),
        .dma_addr_B(dma_addr_B),
        .dma_busy(dma_busy),
        .dma_done(dma_done),
        .dma_source_safe(dma_source_safe) // ---> CONNECT NEW WIRE
    );

    // =========================================================
    // 2. FLOATING-POINT DATAPATH
    // =========================================================
    fp_datapath fpu_pipe (
        .clk(clk), .reset(reset), .ImemOut(ImemOut), 
        
        .FlushD(FlushD),
        .FlushE(FlushE),
        .Int_SrcAE(Int_SrcAE),
        .fp_sys_stall_out(fp_sys_stall),    
        .FP_ReqIntWriteW(fp_ReqIntWriteW),
        .FP_IntDataW(fp_IntDataW),
        .FP_IntRdW(fp_IntRdW),
        .fp_lwstall(fp_lwstall), 
        .FP_MemWriteM(fp_MemWriteM),
        .FP_MemWriteDataM(fp_MemWriteDataM),
        .MemReadDataW(ReadDataM) 
    );

    // =========================================================
    // 3. DMA CONTROLLER (Fire-and-Forget Master)
    // =========================================================
    DMA dma_ctrl (
        .clk(clk), .reset(reset),
        
        .enable(dma_enable), 
        .addr_A(dma_addr_A), 
        .addr_B(dma_addr_B),
        .dma_busy(dma_busy), 
        .dma_done(dma_done),
        .dma_source_safe(dma_source_safe), // ---> CONNECT NEW WIRE
        
        .mem_req(dma_mem_req), 
        .mem_we(dma_mem_we), 
        .mem_addr(dma_mem_addr),
        .mem_wdata(dma_mem_wdata), 
        .mem_data(dma_mem_rdata),
        
        .A0(A0), .A1(A1), .A2(A2), .A3(A3),
        .B0(B0), .B1(B1), .B2(B2), .B3(B3),
        .sa_start(sa_start), 
        .sa_done(sa_done),
        .C00(C00), .C01(C01), .C02(C02), .C03(C03),
        .C10(C10), .C11(C11), .C12(C12), .C13(C13),
        .C20(C20), .C21(C21), .C22(C22), .C23(C23),
        .C30(C30), .C31(C31), .C32(C32), .C33(C33)
    );

    // =========================================================
    // 4. 4x4 SYSTOLIC ARRAY CORE
    // =========================================================
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

    // =========================================================
    // MEMORY ARCHITECTURE
    // =========================================================
    bram_imem imem (.clk(clk), .addr(PCF), .dout(ImemOut), .en(iMemEnF));
    
    // Asymmetric Shared Matrix BRAM
    shared_matrix_bram 
    //  #(
    //     .ROW_DEPTH(512)
    //     .ROW_ADDR_BITS(9)
    // )
             dmem(
        .clk(clk),
        
        .cpu_en(MemEnM),
        .cpu_we(MemWriteM),         
        .cpu_addr(ALUResultM),      
        .cpu_wdata(WriteDataM),
        .cpu_rdata(ReadDataM),

        .dma_en(dma_mem_req | dma_mem_we),
        .dma_we(dma_mem_we),
        .dma_addr(dma_mem_addr[31:2]),
        .dma_wdata(dma_mem_wdata),
        .dma_rdata(dma_mem_rdata)
    );

endmodule