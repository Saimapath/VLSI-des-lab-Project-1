module riscv_soc(
    input clk,
    input reset
);
    // Interconnect wires
    wire [31:0] PCF, ImemOut, ALUResultM, WriteDataM, ReadDataM;
    wire FlushD, FlushE;
    wire [31:0] Int_SrcAE;
    wire [3:0]  MemWriteM;
    wire        MemEnM;
    wire       iMemEnF;


  

    // ---> ADDED: Bridge Wires (FP Datapath -> CPU Core) <---
    wire        fp_ReqIntWriteW;
    wire [31:0] fp_IntDataW;
    wire [4:0]  fp_IntRdW;
    wire        fp_MemWriteM;
    wire [31:0] fp_MemWriteDataM;
    wire       fp_lwstall; // Tells main CPU to freeze if there's a load-use hazard in the FP pipeline

    // Processor Instance
    riscv_pipelined cpu (
        .clk(clk),
        .reset(reset),
        .PCF(PCF),
        .ImemOut(ImemOut),
        .MemWriteM(MemWriteM),
        .iMemEnF(iMemEnF),
        .MemEnM(MemEnM),
        .ALUResultM(ALUResultM),
        .WriteDataM(WriteDataM),
        .ReadDataM(ReadDataM),

     // --- FP Interface --- 
        .FlushD_out(FlushD),
        .FlushE_out(FlushE),
        .Int_SrcAE_out(Int_SrcAE),
        
        // ---> CHANGED: Replaced placeholders with actual bridge wires
        .FP_ReqIntWriteW(fp_ReqIntWriteW),  
        .FP_IntDataW(fp_IntDataW),          
        .FP_IntRdW(fp_IntRdW),              
        .FP_MemWriteM(fp_MemWriteM),        
        .FP_MemWriteDataM(fp_MemWriteDataM),
        .fp_lwstall(fp_lwstall) // Connect the FP load-use stall signal to the CPU

    );

    // =====================================================
    // 2. FLOATING-POINT DATAPATH INSTANCE (ADDED)
    // =====================================================
    fp_datapath fpu_pipe (
        .clk(clk),
        .reset(reset),
        
        // --- Direct from Instruction Memory ---
        .ImemOut(ImemOut), 
        
        // --- Bridge from Main Core ---
        .FlushD(FlushD),
        .FlushE(FlushE),
        .Int_SrcAE(Int_SrcAE),
        
        // --- Bridge to Main Core ---
        .FP_ReqIntWriteW(fp_ReqIntWriteW),
        .FP_IntDataW(fp_IntDataW),
        .FP_IntRdW(fp_IntRdW),
        .fp_lwstall(fp_lwstall), // Connect the load-use stall signal to the CPU
        .FP_MemWriteM(fp_MemWriteM),
        .FP_MemWriteDataM(fp_MemWriteDataM),
        
        // --- Direct from Data Memory ---
        .MemReadDataW(ReadDataM) // FP loads tap directly from Data RAM output
    );



    // Instruction Memory (BRAM Style)
    bram_imem imem (
        .clk(clk),
        .addr(PCF),
        .dout(ImemOut),
        .en(iMemEnF) // Enable signal from CPU
    );

    // Data Memory (BRAM Style)
    bram_dmem dmem (
        .clk(clk),
        .en(MemEnM),
        .we(MemWriteM),
        .addr(ALUResultM),
        .din(WriteDataM),
        .dout(ReadDataM)
    );

endmodule