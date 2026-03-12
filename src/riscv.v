module riscv_pipelined(
    input clk, reset,
    output [31:0] PCF,
    input  [31:0] InstrF,
    output [3:0]       MemWriteM,
    output [31:0] ALUResultM, WriteDataM,
    output        MemEnM,
    input  [31:0] ReadDataM
);
    // --- SIGNALS ---
    // Fetch
    wire [31:0] PCNext, PCPlus4F;
    wire StallF, StallD, FlushD, FlushE;
    
    // Decode
    wire [31:0] InstrD, PCD, PCPlus4D, RD1D, RD2D, ImmExtD;
    wire [4:0]  Rs1D, Rs2D, RdD;
    wire RegWriteD, JumpD,JalrD, BranchD, ALUSrcD;
    wire MemEnD;
    wire [1:0] ResultSrcD;
    wire [2:0] ImmSrcD,LoadBitsD;
    wire [3:0] ALUControlD, MemWriteD;
    wire upimmD;

    // Execute
    wire [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlus4E, PCTargetE, UpimmE, AdderOut;
    wire [31:0] SrcAE, SrcBE, WriteDataE, ALUResultE;
    wire [4:0]  Rs1E, Rs2E, RdE;
    wire [3:0]  ALUControlE, MemWriteE;
    wire [1:0]  ResultSrcE, ForwardAE, ForwardBE;
    wire [2:0]  LoadBitsE;
    wire RegWriteE, JumpE, JalrE, BranchE, ALUSrcE, ZeroE, PCSrcE;
    wire MemEnE;
    wire upimmE;

    // Memory
    wire [31:0] ALUResultM, WriteDataM, PCPlus4M, UpimmM;
    wire [4:0]  RdM;
    wire [1:0]  ResultSrcM;
    wire [2:0]  LoadBitsM;
    wire [3:0]  MemWriteM;
    wire RegWriteM, MemEnM;

    // Writeback
    wire [31:0] ALUResultW, ReadDataW,ReadDataW_ext, PCPlus4W, ResultW, UpimmW;
    wire [4:0]  RdW;
    wire [1:0]  ResultSrcW;
    wire [2:0]      LoadBitsW;
    wire RegWriteW;

    // --- FETCH STAGE ---
    assign PCNext = PCSrcE ? PCTargetE : PCPlus4F;
    assign PCPlus4F = PCF + 4;
    
    pipe_reg #(32) pcreg(clk, reset, !StallF, 1'b0, PCNext, PCF);

    // --- F/D REGISTER ---
    pipe_reg #(32) f_d_instr(clk, reset, !StallD, FlushD, InstrF, InstrD);
    pipe_reg #(32) f_d_pc(clk, reset, !StallD, FlushD, PCF, PCD);
    pipe_reg #(32) f_d_pc4(clk, reset, !StallD, FlushD, PCPlus4F, PCPlus4D);

    // --- DECODE STAGE ---
    assign Rs1D = InstrD[19:15];
    assign Rs2D = InstrD[24:20];
    assign RdD  = InstrD[11:7];

    controller ctrl(
        .op(InstrD[6:0]), 
        .funct3(InstrD[14:12]), 
        .funct7b5(InstrD[30]), 
        .regwrite(RegWriteD), 
        .memwrite(MemWriteD), 
        .jump(JumpD), 
        .branch(BranchD), 
        .alusrc(ALUSrcD), 
        .resultsrc(ResultSrcD), 
        .immsrc(ImmSrcD), 
        .alucontrol(ALUControlD),
        .jalr(JalrD),
        .upimm(upimmD), 
        .loadbits(LoadBitsD),
        .MemEn(MemEnD)
    );
    
    regfile rf(clk, RegWriteW, Rs1D, Rs2D, RdW, ResultW, RD1D, RD2D);
    extend ext(InstrD[31:7], ImmSrcD, ImmExtD);

    // --- D/E REGISTER ---
    pipe_reg #(160) d_e_data(clk, reset, 1'b1, FlushE, {RD1D, RD2D, PCD, ImmExtD, PCPlus4D}, {RD1E, RD2E, PCE, ImmExtE, PCPlus4E});
    pipe_reg #(15)  d_e_addr(clk, reset, 1'b1, FlushE, {Rs1D, Rs2D, RdD}, {Rs1E, Rs2E, RdE});
    pipe_reg #(19)  d_e_ctrl(clk, reset, 1'b1, FlushE, 
        {RegWriteD, ResultSrcD, MemWriteD, JumpD, JalrD, BranchD, ALUControlD, ALUSrcD, upimmD, LoadBitsD}, 
        {RegWriteE, ResultSrcE, MemWriteE, JumpE, JalrE, BranchE, ALUControlE, ALUSrcE, upimmE, LoadBitsE}
    );

    pipe_reg #(1) d_e_en(clk, reset, 1'b1, FlushE, MemEnD, MemEnE);

    // --- EXECUTE STAGE ---
    assign SrcAE = (ForwardAE == 2'b10) ? ALUResultM : (ForwardAE == 2'b01) ? ResultW : RD1E;
    assign WriteDataE = (ForwardBE == 2'b10) ? ALUResultM : (ForwardBE == 2'b01) ? ResultW : RD2E;
    assign SrcBE = ALUSrcE ? ImmExtE : WriteDataE;
    
    rv32i_alu alu_unit(SrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);
    assign AdderOut = PCE + ImmExtE;
    assign PCTargetE =  JalrE ? AdderOut : ALUResultE;
    assign PCSrcE = (BranchE & ZeroE) | JumpE;
    assign UpimmE = upimmE ?  ImmExtE: AdderOut;
// upimm is 1 for lui and 0 for auipc, so UpimmE is either ImmExtE (for lui) or PC+ImmExtE (for auipc)
    // --- E/M REGISTER ---
    pipe_reg #(32) e_m_alu(clk, reset, 1'b1, 1'b0, ALUResultE, ALUResultM);
    pipe_reg #(32) e_m_wd(clk, reset, 1'b1, 1'b0, WriteDataE, WriteDataM);
    pipe_reg #(5)  e_m_rd(clk, reset, 1'b1, 1'b0, RdE, RdM);
    pipe_reg #(32) e_m_upimm(clk, reset, 1'b1, 1'b0, UpimmE, UpimmM );
    pipe_reg #(32) e_m_pc4(clk, reset, 1'b1, 1'b0, PCPlus4E, PCPlus4M);
    pipe_reg #(7)  e_m_ctrl(clk, reset, 1'b1, 1'b0, {RegWriteE, ResultSrcE, MemWriteE}, {RegWriteM, ResultSrcM, MemWriteM});
    pipe_reg #(1) e_m_en(clk, reset, 1'b1, 1'b0, MemEnE, MemEnM);
    // --- MEMORY STAGE ---
    //  instance of data memory is not needed since it's provided as an input (ReadDataM) and output (MemWriteM, ALUResultM, WriteDataM)
    // make instnces of memory (dummy) for verification and connect in top-level testbench if needed

    // --- M/W REGISTER ---
    pipe_reg #(32) m_w_alu(clk, reset, 1'b1, 1'b0, ALUResultM, ALUResultW);
    pipe_reg #(32) m_w_rdt(clk, reset, 1'b1, 1'b0, ReadDataM, ReadDataW);
    pipe_reg #(5)  m_w_rd(clk, reset, 1'b1, 1'b0, RdM, RdW);
    pipe_reg #(32) m_w_pc4(clk, reset, 1'b1, 1'b0, PCPlus4M, PCPlus4W);
    pipe_reg #(3)  m_w_ctrl(clk, reset, 1'b1, 1'b0, {RegWriteM, ResultSrcM}, {RegWriteW, ResultSrcW});



    // --- WRITEBACK STAGE ---
    mem_extend mem_ext(ReadDataW, LoadBitsW, ReadDataW_ext);

 
    
   assign ResultW = (ResultSrcW == 2'b00) ? ALUResultW :
                  (ResultSrcW == 2'b01) ? ReadDataW_ext :
                  (ResultSrcW == 2'b10) ? PCPlus4W :
                  UpimmW; // For ResultSrcW == 2'b11

    // --- HAZARD UNIT ---
    hazard_unit hu( 
        .rs1d(Rs1D), .rs2d(Rs2D), .rs1e(Rs1E), .rs2e(Rs2E), 
        .rde(RdE), .rdm(RdM), .rdw(RdW), 
        .regwritem(RegWriteM), .regwritew(RegWriteW), 
        .resultsrce0(ResultSrcE[0]), .pcsrc_e(PCSrcE), 
        .forwardae(ForwardAE), .forwardbe(ForwardBE), 
        .stallf(StallF), .stalld(StallD), .flushe(FlushE), .flushd(FlushD)
    );

    // make additions for remaing instructuoms as illustrated im the diagram.
endmodule