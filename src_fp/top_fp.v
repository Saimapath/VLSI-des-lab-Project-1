module riscv_soc(
    input clk,
    input reset
);
    wire [31:0] ImemOut, WriteDataM, ReadDataM;
    wire [29:0] PCF, ALUResultM; 
    wire FlushD, FlushE;
    wire [31:0] Int_SrcAE;
    wire [3:0]  MemWriteM;
    wire        MemEnM, iMemEnF;

    // ---> Bridge Wires (FP Datapath <-> CPU Core) <---
    wire        fp_ReqIntWriteW;
    wire [31:0] fp_IntDataW;
    wire [4:0]  fp_IntRdW;
    wire        fp_MemWriteM;
    wire [31:0] fp_MemWriteDataM;
    wire        fp_lwstall; 
    wire        fp_sys_stall; 

    // Processor Instance
    riscv_pipelined cpu (
        .clk(clk), .reset(reset), .PCF_out(PCF), .ImemOut(ImemOut),
        .MemWriteM(MemWriteM), .iMemEnF(iMemEnF), .MemEnM(MemEnM),
        .ALUResultM_out(ALUResultM), .WriteDataM(WriteDataM), .ReadDataM(ReadDataM),

        // --- FP Interface --- 
        .FlushD_out(FlushD),
        .FlushE_out(FlushE),
        .Int_SrcAE_out(Int_SrcAE),
        .fp_sys_stall(fp_sys_stall),  // <--- CHANGED: CPU Receives stall
        
        .FP_ReqIntWriteW(fp_ReqIntWriteW),  
        .FP_IntDataW(fp_IntDataW),          
        .FP_IntRdW(fp_IntRdW),              
        .FP_MemWriteM(fp_MemWriteM),        
        .FP_MemWriteDataM(fp_MemWriteDataM),
        .fp_lwstall(fp_lwstall) 
    );

    // FLOATING-POINT DATAPATH INSTANCE
    fp_datapath fpu_pipe (
        .clk(clk), .reset(reset), .ImemOut(ImemOut), 
        
        .FlushD(FlushD),
        .FlushE(FlushE),
        .Int_SrcAE(Int_SrcAE),
        .fp_sys_stall_out(fp_sys_stall), // <--- CHANGED: FPU Outputs stall
        
        .FP_ReqIntWriteW(fp_ReqIntWriteW),
        .FP_IntDataW(fp_IntDataW),
        .FP_IntRdW(fp_IntRdW),
        .fp_lwstall(fp_lwstall), 
        .FP_MemWriteM(fp_MemWriteM),
        .FP_MemWriteDataM(fp_MemWriteDataM),
        .MemReadDataW(ReadDataM) 
    );

    bram_imem imem (.clk(clk), .addr(PCF), .dout(ImemOut), .en(iMemEnF));
    bram_dmem dmem (.clk(clk), .en(MemEnM), .we(MemWriteM), .addr(ALUResultM), .din(WriteDataM), .dout(ReadDataM));

endmodule