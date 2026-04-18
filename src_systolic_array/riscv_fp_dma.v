module riscv_pipelined(
    input         clk, reset,
    output [29:0] PCF_out,
    input  [31:0] ImemOut,
    output [3:0]  MemWriteM,
    output [29:0] ALUResultM_out, 
    output [31:0] WriteDataM,
    output        MemEnM, iMemEnF,
    input  [31:0] ReadDataM,

    // ===================================================================
    // ---> FP DATAPATH: Outputs TO the FP module
    // ===================================================================
    output        FlushD_out,     
    output        FlushE_out,     
    output [31:0] Int_SrcAE_out,  
    
    // ===================================================================
    // ---> FP DATAPATH: Inputs FROM the FP module
    // ===================================================================
    input         FP_ReqIntWriteW,  
    input  [31:0] FP_IntDataW,      
    input  [4:0]  FP_IntRdW,        
    input         FP_MemWriteM,     
    input  [31:0] FP_MemWriteDataM,
    input         fp_lwstall,
    input         fp_sys_stall,  

    // ===================================================================
    // ---> DMA Accelerator Interface
    // ===================================================================
    output        dma_enable,
    output [31:0] dma_addr_A,
    output [31:0] dma_addr_B,
    input         dma_busy,
    input         dma_done,
    input         dma_source_safe // ---> NEW: Input from DMA
);

    // =========================================================================
    //                              WIRE DECLARATIONS
    // =========================================================================
// fetch
    wire [31:0] PCF, PCNext, PCPlus4F;
    wire        StallF, validF;
    wire        StallD_pc, StallD_pc4, FlushD;
// decode
    wire [31:0] InstrD, PCD, PCPlus4D, RD1D, RD2D, ImmExtD;
    wire [31:0] SrcAD, WriteDataD;
    wire [4:0]  Rs1D, Rs2D, RdD;
    wire [3:0]  ALUControlD, MemWriteD;
    wire [2:0]  ImmSrcD, LoadBitsD;
    wire [1:0]  ResultSrcD, ForwardAD, ForwardBD;
    wire        RegWriteD, JumpD, JalrD, BranchD, zero_for_takenD, ALUSrcD;
    wire        MemEnD, upimmD, validD, validD_1;

    wire dma_mac_en_D; 

// execute
    wire [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlus4E, PCTargetE, UpimmE, AdderOut;
    wire [31:0] SrcAE, SrcBE, WriteDataE, ALUResultE;
    wire [31:0] ForwardResultE, ForwardResultM;
    wire [4:0]  Rs1E, Rs2E, RdE;
    wire [3:0]  ALUControlE, MemWriteE;
    wire [2:0]  LoadBitsE;
    wire [1:0]  ResultSrcE;
    wire        RegWriteE, JumpE, JalrE, BranchE, zero_for_takenE, ALUSrcE;
    wire        ZeroE, PCSrcE, MemEnE, upimmE, validE;
    wire        FlushE;
(* keep = "true" *) wire ActualFlushE;
    wire        is_eq, is_lt, is_ltu;
    wire        StallE; 
    reg         FastZeroE, BranchFlushDelay;

// memory
    wire [31:0] PCM, ALUResultM, PCPlus4M, UpimmM;
    wire [31:0] IntWriteDataM; 
    wire [4:0]  RdM;
    wire [2:0]  LoadBitsM;
    wire [1:0]  ResultSrcM;
    wire        RegWriteM, validM;
    wire        StallM; 

// writeback
    wire [31:0] PCW, ALUResultW, ReadDataW, ReadDataW_ext, PCPlus4W, UpimmW;
    wire [31:0] IntResultW, Final_ResultW;
    wire [4:0]  RdW, Final_RdW;
    wire [2:0]  LoadBitsW;
    wire [1:0]  ResultSrcW;
    wire        RegWriteW, RegWriteW_1, validW, Final_RegWriteW;
    wire        StallW; 

    // =========================================================================
    //                    FP INTERFACE ASSIGNMENTS
    // =========================================================================
    assign FlushD_out    = FlushD; 
    assign FlushE_out    = ActualFlushE; 
    assign Int_SrcAE_out = SrcAE;

    assign PCF_out        = PCF[31:2];
    assign ALUResultM_out = ALUResultM[31:2];

    // =========================================================================
    //                              FETCH STAGE
    // =========================================================================
        (* keep = "true" *) wire PCSrcE_pc = PCSrcE;
    assign PCNext   = PCSrcE_pc ? PCTargetE : PCPlus4F;
    assign PCPlus4F = PCF + 4;
    assign validF   = !StallF;
    assign iMemEnF  = !StallF; 

    pipe_reg #(32) pcreg(clk, reset, !StallF, 1'b0, PCNext, PCF);
    assign InstrD = ImemOut; 
    pipe_reg #(32) f_d_pc(clk, reset, !StallD_pc, 1'b0, PCF, PCD);
    pipe_reg #(32) f_d_pc4(clk, reset, !StallD_pc4, 1'b0, PCPlus4F, PCPlus4D);
    pipe_reg #(1)  f_d_valid(clk, reset, !StallD_pc, 1'b0, validF, validD_1);

    // =========================================================================
    //                              DECODE STAGE
    // =========================================================================
    assign Rs1D = ImemOut[19:15];
    assign Rs2D = ImemOut[24:20];
    assign RdD  = InstrD[11:7];

    controller ctrl(
        .op(InstrD[6:0]), .funct3(InstrD[14:12]), 
        .funct7(InstrD[31:25]), 
        .regwrite(RegWriteD), .memwrite(MemWriteD), .jump(JumpD), .branch(BranchD), 
        .zero_for_taken(zero_for_takenD), .alusrc(ALUSrcD), .resultsrc(ResultSrcD), 
        .immsrc(ImmSrcD), .alucontrol(ALUControlD), .jalr(JalrD), .upimm(upimmD), 
        .loadbits(LoadBitsD), .MemEn(MemEnD), .dma_mac_en(dma_mac_en_D) 
    );
    
    assign Final_RdW       = FP_ReqIntWriteW ? FP_IntRdW   : RdW;
        assign Final_RegWriteW = RegWriteW | FP_ReqIntWriteW;

    assign Final_ResultW   = FP_ReqIntWriteW ? FP_IntDataW : IntResultW;

    regfile rf(clk, Final_RegWriteW, Rs1D, Rs2D, Final_RdW, Final_ResultW, RD1D, RD2D);
    extend ext(InstrD[31:7], ImmSrcD, ImmExtD);

    assign validD = FlushE ? 1'b0 : validD_1;

    assign ForwardResultE = (ResultSrcE == 2'b00) ? ALUResultE : (ResultSrcE == 2'b10) ? PCPlus4E : UpimmE;
    assign ForwardResultM = (ResultSrcM == 2'b00) ? ALUResultM : (ResultSrcM == 2'b10) ? PCPlus4M : UpimmM;

    assign SrcAD = (ForwardAD == 2'b11) ? ForwardResultE : (ForwardAD == 2'b10) ? ForwardResultM : (ForwardAD == 2'b01) ? Final_ResultW : RD1D;
    assign WriteDataD = (ForwardBD == 2'b11) ? ForwardResultE : (ForwardBD == 2'b10) ? ForwardResultM : (ForwardBD == 2'b01) ? Final_ResultW : RD2D;

    // =========================================================================
    // DMA TRIGGER LOGIC
    // =========================================================================
    assign dma_enable = dma_mac_en_D && validD && !dma_busy;
    assign dma_addr_A = SrcAD;      
    assign dma_addr_B = WriteDataD; 

    // =========================================================================
    //  OPTIMIZED MEMORY INTERLOCK (Dual-Matrix Protection & Early Release)
    // =========================================================================
    reg        matrix_locked;
    reg [31:5] locked_page_A; 
    reg [31:5] locked_page_B; 

    always @(posedge clk) begin
        if (!reset) begin
            matrix_locked <= 1'b0;
            locked_page_A <= 27'd0;
            locked_page_B <= 27'd0;
        end else if (dma_enable) begin
            matrix_locked <= 1'b1;
            locked_page_A <= SrcAD[31:5];      
            locked_page_B <= WriteDataD[31:5]; 
        end else if (dma_done) begin
            matrix_locked <= 1'b0;
        end
    end

//    wire collision_A = (ALUResultE[31:5] == locked_page_A);
//    wire collision_B = (ALUResultE[31:5] == locked_page_B);

// TIMING CLOSURE OPTIMIZATION: Bypass the ALU!
    // Because matrices are 64-byte aligned, the base pointer (SrcAE) 
    // identifies the locked page instantly without waiting for the ALU addition.
    wire collision_A = (SrcAE[31:5] == locked_page_A); 
    wire collision_B = (SrcAE[31:5] == locked_page_B);
    // ---> NEW: Unstall writes to B immediately once `dma_source_safe` is high!
    wire danger_A = collision_A && MemEnE;
    wire danger_B = collision_B && (|MemWriteE) && !dma_source_safe; 

    wire dma_mem_collision_stall = matrix_locked && (danger_A | danger_B);
    wire dma_structural_stall    = dma_mac_en_D && validD && dma_busy;

    wire combined_sys_stall = fp_sys_stall | dma_mem_collision_stall | dma_structural_stall;

    // --- D/E Pipeline Registers ---
    pipe_reg #(160) d_e_data(clk, reset, !StallE, 1'b0, {SrcAD, WriteDataD, PCD, ImmExtD, PCPlus4D}, {RD1E, RD2E, PCE, ImmExtE, PCPlus4E});  
    pipe_reg #(15) d_e_addr(clk, reset, !StallE, 1'b0, {Rs1D, Rs2D, RdD}, {Rs1E, Rs2E, RdE});
    pipe_reg #(20) d_e_ctrl(clk, reset, !StallE, ActualFlushE, 
        {RegWriteD, ResultSrcD, MemWriteD, JumpD, JalrD, BranchD, zero_for_takenD, ALUControlD, ALUSrcD, upimmD, LoadBitsD}, 
        {RegWriteE, ResultSrcE, MemWriteE, JumpE, JalrE, BranchE, zero_for_takenE, ALUControlE, ALUSrcE, upimmE, LoadBitsE}
    );
    pipe_reg #(1) d_e_en(clk, reset, !StallE, ActualFlushE, MemEnD, MemEnE);
    pipe_reg #(1) d_e_valid(clk, reset, !StallE, ActualFlushE, validD, validE);


    // =========================================================================
    //                              EXECUTE STAGE
    // =========================================================================
    always @(posedge clk) begin
        if (!reset) BranchFlushDelay <= 1'b0;
        else       BranchFlushDelay <= PCSrcE;
    end
    
    wire base_ActualFlushE = FlushE || BranchFlushDelay;
    assign ActualFlushE    = base_ActualFlushE; 
    (* keep = "true" *) wire ActualFlushE_fp = base_ActualFlushE; 

    assign SrcAE      = RD1E;
    assign WriteDataE = RD2E;
    assign SrcBE      = ALUSrcE ? ImmExtE : WriteDataE;

    rv32i_alu alu_unit(SrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);
    
    assign AdderOut  = PCE + ImmExtE;
    assign PCTargetE = JalrE ? ALUResultE : AdderOut;
    assign UpimmE    = upimmE ? ImmExtE : AdderOut;

    assign is_eq  = (SrcAE == SrcBE);
    assign is_lt  = ($signed(SrcAE) < $signed(SrcBE));
    assign is_ltu = (SrcAE < SrcBE);

    always @(*) begin
        if      (ALUControlE == 4'b0001) FastZeroE = is_eq;
        else if (ALUControlE == 4'b1000) FastZeroE = !is_lt;  
        else if (ALUControlE == 4'b1001) FastZeroE = !is_ltu;
        else                             FastZeroE = 1'b0;   
    end

    assign PCSrcE = (BranchE & (FastZeroE == zero_for_takenE)) | JumpE;

    // --- E/M Pipeline Registers ---
    pipe_reg #(32) e_m_pc(clk, reset, !StallM, 1'b0, PCE, PCM);
    pipe_reg #(32) e_m_alu(clk, reset, !StallM, 1'b0, ALUResultE, ALUResultM);
    pipe_reg #(32) e_m_wd(clk, reset, !StallM, 1'b0, WriteDataE, IntWriteDataM);
    pipe_reg #(5)  e_m_rd(clk, reset, !StallM, 1'b0, RdE, RdM);
    pipe_reg #(32) e_m_upimm(clk, reset, !StallM, 1'b0, UpimmE, UpimmM);
    pipe_reg #(32) e_m_pc4(clk, reset, !StallM, 1'b0, PCPlus4E, PCPlus4M);
    pipe_reg #(7)  e_m_ctrl(clk, reset, !StallM, 1'b0, {RegWriteE, ResultSrcE, MemWriteE}, {RegWriteM, ResultSrcM, MemWriteM});
    pipe_reg #(1)  e_m_en(clk, reset, !StallM, 1'b0, MemEnE, MemEnM);
    pipe_reg #(3)  e_m_load(clk, reset, !StallM, 1'b0, LoadBitsE, LoadBitsM);
    pipe_reg #(1)  e_m_valid(clk, reset, !StallM, 1'b0, validE, validM);

    // =========================================================================
    //                              MEMORY STAGE
    // =========================================================================
    assign WriteDataM = FP_MemWriteM ? FP_MemWriteDataM : IntWriteDataM;

    // --- M/W Pipeline Registers ---
    pipe_reg #(32) m_w_pc(clk, reset, !StallW, 1'b0, PCM, PCW);
    pipe_reg #(32) m_w_alu(clk, reset, !StallW, 1'b0, ALUResultM, ALUResultW);
    pipe_reg #(5)  m_w_rd(clk, reset, !StallW, 1'b0, RdM, RdW);
    pipe_reg #(32) m_w_pc4(clk, reset, !StallW, 1'b0, PCPlus4M, PCPlus4W);
    pipe_reg #(3)  m_w_ctrl(clk, reset, !StallW, 1'b0, {RegWriteM, ResultSrcM}, {RegWriteW_1, ResultSrcW});
    pipe_reg #(3)  m_w_load(clk, reset, !StallW, 1'b0, LoadBitsM, LoadBitsW);
    pipe_reg #(32) m_w_upimm(clk, reset, !StallW, 1'b0, UpimmM, UpimmW);
    pipe_reg #(1)  m_w_valid(clk, reset, !StallW, 1'b0, validM, validW);

    // =========================================================================
    //                              WRITEBACK STAGE
    // =========================================================================
    mem_extend mem_ext(ReadDataM, LoadBitsW, ReadDataW_ext);
    
    assign RegWriteW = RegWriteW_1 && validW; 
    assign IntResultW = (ResultSrcW == 2'b00) ? ALUResultW : (ResultSrcW == 2'b01) ? ReadDataW_ext : (ResultSrcW == 2'b10) ? PCPlus4W : UpimmW; 

    // =========================================================================
    //                              HAZARD UNIT
    // =========================================================================
    hazard_unit hu( 
        .rs1d(Rs1D), .rs2d(Rs2D), 
        .rs1e(Rs1E), .rs2e(Rs2E), 
        .rde(RdE),   .rdm(RdM),   
        .rdw(Final_RdW),                               
        .regwritee(RegWriteE), .regwritem(RegWriteM), 
        .regwritew(Final_RegWriteW),                   
        .resultsrce(ResultSrcE), .resultsrcm(ResultSrcM),
        .pcsrc_e(PCSrcE), 
        .valide(validE), .validm(validM), .validw(validW), 
        .forwardad(ForwardAD), .forwardbd(ForwardBD), 
        .stallf(StallF), .stalld_pc(StallD_pc), .stalld_pc4(StallD_pc4), 
        .flushe(FlushE), .flushd(FlushD),
        .fp_lwstall(fp_lwstall),                       
        .fp_sys_stall(combined_sys_stall), 
        .stallm(StallM), .stallw(StallW), .stalle(StallE)
    );

endmodule