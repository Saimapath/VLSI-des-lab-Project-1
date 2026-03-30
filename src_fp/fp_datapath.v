module fp_datapath(
    input  wire        clk, 
    input  wire        reset,
    input  wire        FlushD, // Squashes ImemOut on a branch/jump
    input  wire        FlushE,
    
    // --- FROM INSTRUCTION MEMORY ---
    input  wire [31:0] ImemOut, // Takes ImemOut directly from BRAM
    
    // --- CROSS-REGFILE INTERFACE (Int -> FP) ---
    input  wire [31:0] Int_SrcAE, 
    
    // --- CROSS-REGFILE INTERFACE (FP -> Int) ---
    output wire        FP_ReqIntWriteW, 
    output wire [31:0] FP_IntDataW,
    output wire [4:0]  FP_IntRdW,
    output wire fp_lwstall, // Tells main CPU to freeze if there's a load-use hazard in the FP pipeline
    // --- MEMORY INTERFACE ---
    output wire        FP_MemWriteM,
    output wire [31:0] FP_MemWriteDataM,
    input  wire [31:0] MemReadDataW      
);

    // =======================================================================
    // --- WIRE DECLARATIONS (By Pipeline Stage) ---
    // =======================================================================

    // 1. Decode Stage Wires
    wire [31:0] InstrD; 
    wire [4:0]  Rs1D, Rs2D, Rs3D, RdD;
    wire [2:0]  rmD;
    wire        fp_alu_enD, fp_regwriteD, fp_req_int_regwriteD, fp_mem_writeD, fp_mem_readD;
    wire [4:0]  fpucontrolD;
    wire [15:0] FPRD1D, FPRD2D, FPRD3D;

    // 2. Execute Stage Wires
    wire [15:0] FPRD1E, FPRD2E, FPRD3E;
    wire [4:0]  Rs1E, Rs2E, Rs3E, RdE;
    wire [2:0]  rmE;
    wire        fp_alu_enE, fp_regwriteE, fp_req_int_regwriteE, fp_mem_writeE, fp_mem_readE;
    wire [4:0]  fpucontrolE;
    wire [1:0]  ForwardA_FP, ForwardB_FP, ForwardC_FP;
    wire [15:0] SrcA_FP, SrcB_FP, SrcC_FP;
    wire [15:0] FPU_FP_OutE;
    wire [31:0] FPU_Int_OutE;

    // 3. Memory Stage Wires
    wire [15:0] FPRD2M; 
    wire [15:0] FPU_FP_OutM;
    wire [31:0] FPU_Int_OutM;
    wire [4:0]  RdM;
    wire        fp_regwriteM, fp_req_int_regwriteM, fp_mem_readM;
    // Note: FP_MemWriteM is a module output, already declared above.

    // 4. Writeback Stage Wires
    wire [15:0] FPU_FP_OutW;
    wire [15:0] FP_ResultW; 
    wire [4:0]  RdW_FP;
    wire        fp_regwriteW, fp_mem_readW;
    // Note: FP_ReqIntWriteW, FP_IntDataW, FP_IntRdW are module outputs.


    // =======================================================================
    // 1. DECODE STAGE (FP)
    // =======================================================================
    assign InstrD = (FlushD || reset) ? 32'h00000000 : ImemOut; 

    assign Rs1D = InstrD[19:15];
    assign Rs2D = InstrD[24:20];
    assign Rs3D = InstrD[31:27];
    assign RdD  = InstrD[11:7];
    assign rmD  = InstrD[14:12];

    fp_controller fp_ctrl(
        .instr(InstrD),
        .fp_alu_en(fp_alu_enD), 
        .fp_regwrite(fp_regwriteD),
        .fp_int_regwrite(fp_req_int_regwriteD), 
        .fp_mem_write(fp_mem_writeD),
        .fp_mem_read(fp_mem_readD), 
        .fpucontrol(fpucontrolD)
    );


    fp_regfile fprf(
        .clk(clk), 
        .we4(fp_regwriteW), 
        .a1(Rs1D), .a2(Rs2D), .a3(Rs3D), .a4(RdW_FP), // Write back address is RdW_FP
        .wd4(FP_ResultW), 
        .rd1(FPRD1D), .rd2(FPRD2D), .rd3(FPRD3D)
    );

    // =======================================================================
    // 2. D/E PIPELINE REGISTERS
    // =======================================================================
    
    // Pass FP Register Data
    pipe_reg #(48) d_e_fp_data(clk, reset, 1'b1, FlushE, 
        {FPRD1D, FPRD2D, FPRD3D}, 
        {FPRD1E, FPRD2E, FPRD3E}
    );
    
    // Pass Address and Routing Fields (Fixed to include Source Registers for Hazard Unit)
    pipe_reg #(23) d_e_fp_addr(clk, reset, 1'b1, FlushE, 
        {Rs1D, Rs2D, Rs3D, RdD, rmD}, 
        {Rs1E, Rs2E, Rs3E, RdE, rmE}
    );
    
    // Pass Control Signals
    pipe_reg #(10) d_e_fp_ctrl(clk, reset, 1'b1, FlushE,
        {fp_alu_enD, fp_regwriteD, fp_req_int_regwriteD, fp_mem_writeD, fp_mem_readD, fpucontrolD},
        {fp_alu_enE, fp_regwriteE, fp_req_int_regwriteE, fp_mem_writeE, fp_mem_readE, fpucontrolE}
    );

    // =======================================================================
    // 3. EXECUTE STAGE (FP)
    // =======================================================================

    wire fp_requires_d = fp_alu_enD | fp_mem_writeD;

    // 3A. FP Hazard Unit

    
    fp_hazard_unit fp_hu(
        .rs1d(Rs1D), .rs2d(Rs2D), .rs3d(Rs3D),
        .rs1e(Rs1E), .rs2e(Rs2E), .rs3e(Rs3E), .rde(RdE),
        .rdm(RdM), .rdw(RdW_FP), 
        .fp_regwritem(fp_regwriteM), .fp_regwritew(fp_regwriteW), .fp_mem_read_e(fp_mem_readE), .fp_requires_d(fp_requires_d),
        .forwarda_fp(ForwardA_FP), .forwardb_fp(ForwardB_FP), .forwardc_fp(ForwardC_FP), .fp_lwstall(fp_lwstall)
    );

    // 3B. Forwarding Multiplexers
    assign SrcA_FP = (ForwardA_FP == 2'b10) ? FPU_FP_OutM :
                     (ForwardA_FP == 2'b01) ? FP_ResultW  : FPRD1E;
                     
    assign SrcB_FP = (ForwardB_FP == 2'b10) ? FPU_FP_OutM :
                     (ForwardB_FP == 2'b01) ? FP_ResultW  : FPRD2E;
                     
    assign SrcC_FP = (ForwardC_FP == 2'b10) ? FPU_FP_OutM :
                     (ForwardC_FP == 2'b01) ? FP_ResultW  : FPRD3E;

    // 3C. FPU Top Wrapper
    fpu fpu_inst(
        .clk(clk), .rst_n(!reset), 
        .fp_alu_en(fp_alu_enE), .fpucontrol(fpucontrolE), .rm(rmE),
        .rs1_fp(SrcA_FP), 
        .rs2_fp(SrcB_FP), 
        .rs3_fp(SrcC_FP), 
        .rs1_int(Int_SrcAE), 
        .fp_wb_data(FPU_FP_OutE), .int_wb_data(FPU_Int_OutE)
    );

    // =======================================================================
    // 4. E/M PIPELINE REGISTERS
    // =======================================================================
    
    // CRITICAL FIX: Pass the HAZARD RESOLVED SrcB_FP into Memory for the Store instruction, not raw FPRD2E!
    pipe_reg #(16) e_m_fsw_data(clk, reset, 1'b1, 1'b0, SrcB_FP, FPRD2M);
    
    // Pass FPU Arithmetic Results
    pipe_reg #(48) e_m_fpu_res(clk, reset, 1'b1, 1'b0, 
        {FPU_FP_OutE, FPU_Int_OutE}, 
        {FPU_FP_OutM, FPU_Int_OutM}
    );
    
    // Pass Destination Address
    pipe_reg #(5)  e_m_rd(clk, reset, 1'b1, 1'b0, RdE, RdM);
    
    // Pass Control Signals (MemWrite exits here to Main CPU)
    pipe_reg #(4)  e_m_fp_ctrl(clk, reset, 1'b1, 1'b0, 
        {fp_regwriteE, fp_req_int_regwriteE, fp_mem_writeE, fp_mem_readE}, 
        {fp_regwriteM, fp_req_int_regwriteM, FP_MemWriteM,  fp_mem_readM}
    );

    // =======================================================================
    // 5. MEMORY STAGE (FP)
    // =======================================================================
    // Format the 16-bit float into a 32-bit word for the main data memory
    assign FP_MemWriteDataM = {16'd0, FPRD2M};

    // =======================================================================
    // 6. M/W PIPELINE REGISTERS
    // =======================================================================
    
    // Pass FPU Arithmetic Results (Int Data exits here to Main CPU)
    pipe_reg #(48) m_w_fpu_res(clk, reset, 1'b1, 1'b0, 
        {FPU_FP_OutM, FPU_Int_OutM}, 
        {FPU_FP_OutW, FP_IntDataW}
    );

    // Split the Destination Register: One for FP Regfile, One for Int Regfile
    pipe_reg #(10) m_w_rd(clk, reset, 1'b1, 1'b0, 
        {RdM, RdM}, 
        {RdW_FP, FP_IntRdW}
    );
    
    // Pass Control Signals (ReqIntWrite exits here to Main CPU)
    pipe_reg #(3)  m_w_fp_ctrl(clk, reset, 1'b1, 1'b0, 
        {fp_regwriteM, fp_req_int_regwriteM, fp_mem_readM}, 
        {fp_regwriteW, FP_ReqIntWriteW,      fp_mem_readW}
    );

    // =======================================================================
    // 7. WRITEBACK STAGE (FP)
    // =======================================================================
    
    // If instruction was FLW, write the memory data to the FP Regfile. Otherwise, write the FPU math result.
    assign FP_ResultW = fp_mem_readW ? MemReadDataW[15:0] : FPU_FP_OutW;

endmodule