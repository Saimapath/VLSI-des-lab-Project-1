    module riscv_pipelined(
        input clk, reset,
        output [31:0] PCF,
        input  [31:0] ImemOut,
        output [3:0]       MemWriteM,
        output [31:0] ALUResultM, WriteDataM,
        output        MemEnM,iMemEnF,
        input  [31:0] ReadDataM,

        // ===================================================================
        // ---> ALTERED FOR FP DATAPATH: Outputs TO the FP module
        // ===================================================================
        output        FlushD_out,     // ---> ADDED: Tell FP to flush Decode stage
        output        FlushE_out,     // Tell FP to flush Execute stage
        output [31:0] Int_SrcAE_out,  // Pass resolved integer RS1 to FP Execute
        
        // ===================================================================
        // ---> ALTERED FOR FP DATAPATH: Inputs FROM the FP module
        // ===================================================================
        input         FP_ReqIntWriteW,  
        input  [31:0] FP_IntDataW,      
        input  [4:0]  FP_IntRdW,        
        input         FP_MemWriteM,     
        input  [31:0] FP_MemWriteDataM,
        input         fp_lwstall       // Input from FP Hazard Unit to stall the CPU on FP load-use hazards
    );
        // --- SIGNALS ---
        // Fetch
        wire [31:0] PCNext, PCPlus4F;
        wire StallF, StallD, FlushD, FlushE;
        wire validF;
        
        // Decode
        wire [31:0] InstrD, PCD, PCPlus4D, RD1D, RD2D, ImmExtD;
        wire [4:0]  Rs1D, Rs2D, RdD;
        wire RegWriteD, JumpD,JalrD, BranchD,zero_for_takenD, ALUSrcD;
        wire MemEnD;
        wire [1:0] ResultSrcD;
        wire [2:0] ImmSrcD,LoadBitsD;
        wire [3:0] ALUControlD, MemWriteD;
        wire upimmD;
        wire validD;

        // Execute
        wire [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlus4E, PCTargetE, UpimmE, AdderOut;
        wire [31:0] SrcAE, SrcBE, WriteDataE, ALUResultE, ForwardResultM;
        wire [4:0]  Rs1E, Rs2E, RdE;
        wire [3:0]  ALUControlE, MemWriteE;
        wire [1:0]  ResultSrcE, ForwardAE, ForwardBE;
        wire [2:0]  LoadBitsE;
        wire RegWriteE, JumpE, JalrE, BranchE,zero_for_takenE, ALUSrcE, ZeroE, PCSrcE;
        wire MemEnE;
        wire upimmE;
        wire validE;

        // Memory
        wire [31:0] PCM;
        wire [31:0] IntWriteDataM; // ---> ADDED: Separated Integer Write Data from Final Write Data
        wire [31:0] ALUResultM, WriteDataM, PCPlus4M, UpimmM;
        wire [4:0]  RdM;
        wire [1:0]  ResultSrcM;
        wire [2:0]  LoadBitsM;
        wire [3:0]  MemWriteM;
        wire RegWriteM, MemEnM;
        wire validM;

        // Writeback
        wire [31:0] PCW;
        wire [31:0] ALUResultW, ReadDataW,ReadDataW_ext, PCPlus4W, ResultW, UpimmW, IntResultW;
        wire [4:0]  RdW;
        wire [1:0]  ResultSrcW;
        wire [2:0]      LoadBitsW;
        wire RegWriteW;
        wire validW;

        assign FlushD_out    = FlushD; // ---> ADDED: Routes the internal Hazard Unit flush signal out
        assign FlushE_out    = FlushE;
        assign Int_SrcAE_out = SrcAE;

        // --- FETCH STAGE ---
        assign PCNext = PCSrcE ? PCTargetE : PCPlus4F;
        assign PCPlus4F = PCF + 4;
        assign validF=!StallF;
        assign iMemEnF = !StallF; // Instruction memory enable is active when not stalled

        // --- F/D REGISTER ---
        // pipe_reg #(32) f_d_instr(clk, reset, !StallD, FlushD, ImemOut, InstrD);
        
        pipe_reg #(32) pcreg(clk, reset, !StallF, 1'b0, PCNext, PCF);

        assign InstrD = (FlushD || reset) ? 32'h00000000 : ImemOut;

        pipe_reg #(32) f_d_pc(clk, reset, !StallD, FlushD, PCF, PCD);
        pipe_reg #(32) f_d_pc4(clk, reset, !StallD, FlushD, PCPlus4F, PCPlus4D);
        pipe_reg #(1) f_d_valid(clk, reset, !StallD, FlushD, validF, validD_1);

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
            .zero_for_taken(zero_for_takenD),
            .alusrc(ALUSrcD), 
            .resultsrc(ResultSrcD), 
            .immsrc(ImmSrcD), 
            .alucontrol(ALUControlD),
            .jalr(JalrD),
            .upimm(upimmD), 
            .loadbits(LoadBitsD),
            .MemEn(MemEnD)
        );

        // ---> ADDED: OVERRIDE REGFILE WRITEBACK WITH FP DATA IF NEEDED
        wire        Final_RegWriteW = RegWriteW | FP_ReqIntWriteW; // Force write if FP needs it
        wire [4:0]  Final_RdW       = FP_ReqIntWriteW ? FP_IntRdW   : RdW;
        wire [31:0] Final_ResultW   = FP_ReqIntWriteW ? FP_IntDataW : IntResultW;

        regfile rf(clk, Final_RegWriteW, Rs1D, Rs2D, Final_RdW, Final_ResultW, RD1D, RD2D);
        // <--- END ADDITION
        
        // regfile rf(clk,RegWriteW, Rs1D, Rs2D, RdW, ResultW, RD1D, RD2D);
        extend ext(InstrD[31:7], ImmSrcD, ImmExtD);

        assign validD=FlushE ? 1'b0 : validD_1;

        // --- D/E REGISTER ---
        pipe_reg #(160) d_e_data(clk, reset, 1'b1, FlushE, {RD1D, RD2D, PCD, ImmExtD, PCPlus4D}, {RD1E, RD2E, PCE, ImmExtE, PCPlus4E});
        pipe_reg #(15)  d_e_addr(clk, reset, 1'b1, FlushE, {Rs1D, Rs2D, RdD}, {Rs1E, Rs2E, RdE});
        pipe_reg #(20)  d_e_ctrl(clk, reset, 1'b1, FlushE, 
            {RegWriteD, ResultSrcD, MemWriteD, JumpD, JalrD, BranchD, zero_for_takenD,ALUControlD, ALUSrcD, upimmD, LoadBitsD}, 
            {RegWriteE, ResultSrcE, MemWriteE, JumpE, JalrE, BranchE,zero_for_takenE, ALUControlE, ALUSrcE, upimmE, LoadBitsE}
        );

        pipe_reg #(1) d_e_en(clk, reset, 1'b1, FlushE, MemEnD, MemEnE);
        pipe_reg #(1) d_e_valid(clk, reset, 1'b1, FlushE, validD, validE);

        // --- EXECUTE STAGE ---

        assign ForwardResultM=(ResultSrcM==2'b00)?ALUResultM:(ResultSrcM==2'b10)?PCPlus4M:UpimmM;

        assign SrcAE = (ForwardAE == 2'b10) ? ForwardResultM : (ForwardAE == 2'b01) ? Final_ResultW : RD1E;
        assign WriteDataE = (ForwardBE == 2'b10) ? ForwardResultM : (ForwardBE == 2'b01) ? Final_ResultW : RD2E;
        assign SrcBE = ALUSrcE ? ImmExtE : WriteDataE;

        // assign validE=FlushE ? 1'b0 : validE_1;
        
        rv32i_alu alu_unit(SrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);
        assign AdderOut = PCE + ImmExtE;
        assign PCTargetE = JalrE ? ALUResultE : AdderOut;


        assign PCSrcE = (BranchE & (ZeroE==zero_for_takenE)) | JumpE;
        assign UpimmE = upimmE ?  ImmExtE: AdderOut;
    // upimm is 1 for lui and 0 for auipc, so UpimmE is either ImmExtE (for lui) or PC+ImmExtE (for auipc)
        // --- E/M REGISTER ---
        pipe_reg #(32) e_m_pc(clk, reset, 1'b1, 1'b0, PCE, PCM);

        pipe_reg #(32) e_m_alu(clk, reset, 1'b1, 1'b0, ALUResultE, ALUResultM);
        // pipe_reg #(32) e_m_wd(clk, reset, 1'b1, 1'b0, WriteDataE, WriteDataM);
        // ---> CHANGED: WriteDataE is stored in IntWriteDataM now.
        pipe_reg #(32) e_m_wd(clk, reset, 1'b1, 1'b0, WriteDataE, IntWriteDataM);
        pipe_reg #(5)  e_m_rd(clk, reset, 1'b1, 1'b0, RdE, RdM);
        pipe_reg #(32) e_m_upimm(clk, reset, 1'b1, 1'b0, UpimmE, UpimmM );
        pipe_reg #(32) e_m_pc4(clk, reset, 1'b1, 1'b0, PCPlus4E, PCPlus4M);
        pipe_reg #(7)  e_m_ctrl(clk, reset, 1'b1, 1'b0, {RegWriteE, ResultSrcE, MemWriteE}, {RegWriteM, ResultSrcM, MemWriteM});
        pipe_reg #(1) e_m_en(clk, reset, 1'b1, 1'b0, MemEnE, MemEnM);

        pipe_reg #(3)  e_m_load(clk, reset, 1'b1, 1'b0, LoadBitsE, LoadBitsM);
        pipe_reg #(1) e_m_valid(clk, reset, 1'b1, 1'b0, validE, validM);
        // --- MEMORY STAGE ---
        //  instance of data memory is not needed since it's provided as an input (ReadDataM) and output (MemWriteM, ALUResultM, WriteDataM)
        // make instnces of memory (dummy) for verification and connect in top-level testbench if needed
        // ---> ADDED: MULTIPLEX THE DATA GOING TO RAM (Integer vs Float)
        assign WriteDataM = FP_MemWriteM ? FP_MemWriteDataM : IntWriteDataM;

        // --- M/W REGISTER ---
        pipe_reg #(32) m_w_pc(clk, reset, 1'b1, 1'b0, PCM, PCW);

        pipe_reg #(32) m_w_alu(clk, reset, 1'b1, 1'b0, ALUResultM, ALUResultW);
        // pipe_reg #(32) m_w_rdt(clk, reset, 1'b1, 1'b0, ReadDataM, ReadDataW);
        pipe_reg #(5)  m_w_rd(clk, reset, 1'b1, 1'b0, RdM, RdW);
        pipe_reg #(32) m_w_pc4(clk, reset, 1'b1, 1'b0, PCPlus4M, PCPlus4W);
        pipe_reg #(3)  m_w_ctrl(clk, reset, 1'b1, 1'b0, {RegWriteM, ResultSrcM}, {RegWriteW_1, ResultSrcW});

        pipe_reg #(3)  m_w_load(clk, reset, 1'b1, 1'b0, LoadBitsM, LoadBitsW);
        pipe_reg #(32) m_w_upimm(clk, reset, 1'b1, 1'b0, UpimmM, UpimmW);
        pipe_reg #(1) m_w_valid(clk, reset, 1'b1, 1'b0, validM, validW);

        // --- WRITEBACK STAGE ---
        mem_extend mem_ext(ReadDataM, LoadBitsW, ReadDataW_ext);
        assign RegWriteW = RegWriteW_1 && validW; // Ensure we only write back when the instruction is valid
        // name changed from ResultW to IntResultW to avoid confusion with the FP ResultW
    assign IntResultW = (ResultSrcW == 2'b00) ? ALUResultW :
                    (ResultSrcW == 2'b01) ? ReadDataW_ext :
                    (ResultSrcW == 2'b10) ? PCPlus4W :
                    UpimmW; // For ResultSrcW == 2'b11

    // --- HAZARD UNIT ---
        hazard_unit hu( 
            .rs1d(Rs1D), .rs2d(Rs2D), .rs1e(Rs1E), .rs2e(Rs2E), 
            .rde(RdE), .rdm(RdM), .rdw(Final_RdW), // Use Final_RdW which accounts for FP writes
            .regwritem(RegWriteM), .regwritew(Final_RegWriteW), // Use Final_RegWriteW which accounts for FP writes
            .resultsrce(ResultSrcE),   
            .pcsrc_e(PCSrcE), 
            .valide(validE), .validm(validM), .validw(validW), // <--- CONNECT VALID BITS
            .fp_lwstall(fp_lwstall), // Connect the FP hazard unit's load-use stall signal
            .forwardae(ForwardAE), .forwardbe(ForwardBE), 
            .stallf(StallF), .stalld(StallD), .flushe(FlushE), .flushd(FlushD)
        );

        // make additions for remaing instructuoms as illustrated im the diagram.
    endmodule 