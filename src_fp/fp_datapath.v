module fp_datapath(
    input  wire        clk, 
    input  wire        reset,
    input  wire        FlushD, 
    input  wire        FlushE,
    
    // --- FROM INSTRUCTION MEMORY ---
    input  wire [31:0] ImemOut, 
    
    // --- CROSS-REGFILE INTERFACE (Int -> FP) ---
    input  wire [31:0] Int_SrcAE, 
    
    // --- CROSS-REGFILE INTERFACE (FP -> Int) ---
    output wire        FP_ReqIntWriteW, 
    output wire [31:0] FP_IntDataW,
    output wire [4:0]  FP_IntRdW,
    output wire        fp_lwstall, 
    output wire        fp_sys_stall_out, // ---> NEW: Tell the integer core to freeze!
    
    // --- MEMORY INTERFACE ---
    output wire        FP_MemWriteM,
    output wire [31:0] FP_MemWriteDataM,
    input  wire [31:0] MemReadDataW      
);

    // =======================================================================
    // --- WIRE DECLARATIONS (By Pipeline Stage) ---
    // =======================================================================
    wire [31:0] InstrD; 
    wire [4:0]  Rs1D, Rs2D, Rs3D, RdD;
    wire [2:0]  rmD;
    wire        fp_alu_enD, fp_regwriteD, fp_req_int_regwriteD, fp_mem_writeD, fp_mem_readD;
    wire [4:0]  fpucontrolD;
    wire [15:0] FPRD1D, FPRD2D, FPRD3D;

    wire [15:0] FPRD1E, FPRD2E, FPRD3E;
    wire [4:0]  Rs1E, Rs2E, Rs3E, RdE;
    wire [2:0]  rmE;
    wire        fp_alu_enE, fp_regwriteE, fp_req_int_regwriteE, fp_mem_writeE, fp_mem_readE;
    wire [4:0]  fpucontrolE;
    wire [1:0]  ForwardA_FP, ForwardB_FP, ForwardC_FP;
    wire [15:0] SrcA_FP, SrcB_FP, SrcC_FP;
    wire [15:0] FPU_FP_OutE;
    wire [31:0] FPU_Int_OutE;

    wire [15:0] FPRD2M; 
    wire [15:0] FPU_FP_OutM;
    wire [31:0] FPU_Int_OutM;
    wire [4:0]  RdM;
    wire        fp_regwriteM, fp_req_int_regwriteM, fp_mem_readM;

    wire [15:0] FPU_FP_OutW;
    wire [15:0] FP_ResultW; 
    wire [4:0]  RdW_FP;
    wire        fp_regwriteW, fp_mem_readW;

    // =======================================================================
    // 1. DECODE STAGE (FP)
    // =======================================================================
    assign InstrD = ( !reset) ? 32'h00000000 : ImemOut; 

// ---> NEW: FAST DECODE FOR LOAD-USE HAZARDS (Saves 4ns of logic depth!)
    wire [6:0] opD = InstrD[6:0];
    wire fast_fp_req_d = (opD == 7'b1010011) || // FP Math/Casts
                         (opD == 7'b0100111) || // FSW
                         (opD == 7'b1000011) || // FMADD
                         (opD == 7'b1000111) || // FMSUB
                         (opD == 7'b1001011) || // FNMSUB
                         (opD == 7'b1001111);   // FNMADD
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
        .a1(Rs1D), .a2(Rs2D), .a3(Rs3D), .a4(RdW_FP), 
        .wd4(FP_ResultW), 
        .rd1(FPRD1D), .rd2(FPRD2D), .rd3(FPRD3D)
    );

    // =======================================================================
    // MULTI-CYCLE FPU STALL CONTROLLER (MOVED HERE!)
    // =======================================================================
    wire is_fp_mac_e = (fpucontrolE >= 5'd1 && fpucontrolE <= 5'd7); 
    
    reg [2:0] fp_wait_cycles; 
    reg       fp_mac_done;
    
    always @(posedge clk) begin
        if (!reset) begin
            fp_wait_cycles <= 3'd0;
            fp_mac_done    <= 1'b0;
        end else begin
            if (is_fp_mac_e && fp_wait_cycles == 0 && !fp_mac_done) begin
                fp_wait_cycles <= 3'd4; 
            end 
            else if (fp_wait_cycles > 0) begin
                fp_wait_cycles <= fp_wait_cycles - 1;
                if (fp_wait_cycles == 3'd1) fp_mac_done <= 1'b1; 
            end 
            else if (!fp_sys_stall) begin
                fp_mac_done <= 1'b0; 
            end
        end
    end
    
    wire fp_sys_stall = (fp_wait_cycles > 0) || (is_fp_mac_e && fp_wait_cycles == 0 && !fp_mac_done);
    assign fp_sys_stall_out = fp_sys_stall;
    
    // =======================================================================
    // DECODE STAGE FORWARDING MUXES
    // =======================================================================
    wire [15:0] SrcA_FPD = (ForwardA_FP == 2'b11) ? FPU_FP_OutE : 
                           (ForwardA_FP == 2'b10) ? FPU_FP_OutM : 
                           (ForwardA_FP == 2'b01) ? FP_ResultW  : FPRD1D;

    wire [15:0] SrcB_FPD = (ForwardB_FP == 2'b11) ? FPU_FP_OutE : 
                           (ForwardB_FP == 2'b10) ? FPU_FP_OutM : 
                           (ForwardB_FP == 2'b01) ? FP_ResultW  : FPRD2D;

    wire [15:0] SrcC_FPD = (ForwardC_FP == 2'b11) ? FPU_FP_OutE : 
                           (ForwardC_FP == 2'b10) ? FPU_FP_OutM : 
                           (ForwardC_FP == 2'b01) ? FP_ResultW  : FPRD3D;

    // =======================================================================
    // 2. D/E PIPELINE REGISTERS
    // =======================================================================
    // ---> Latch the FORWARDED data (SrcA_FPD), not the raw RegFile data!
    pipe_reg #(48) d_e_fp_data(clk, reset, !fp_sys_stall, FlushE, 
        {SrcA_FPD, SrcB_FPD, SrcC_FPD}, 
        {FPRD1E, FPRD2E, FPRD3E} // These now hold the fully forwarded values
    );

//    // =======================================================================
//    // 2. D/E PIPELINE REGISTERS
//    // =======================================================================
//    pipe_reg #(48) d_e_fp_data(clk, reset, !fp_sys_stall, FlushE, 
//        {FPRD1D, FPRD2D, FPRD3D}, 
//        {FPRD1E, FPRD2E, FPRD3E}
//    );
    pipe_reg #(23) d_e_fp_addr(clk, reset, !fp_sys_stall, FlushE, 
        {Rs1D, Rs2D, Rs3D, RdD, rmD}, 
        {Rs1E, Rs2E, Rs3E, RdE, rmE}
    );
    pipe_reg #(10) d_e_fp_ctrl(clk, reset, !fp_sys_stall, FlushE,
        {fp_alu_enD, fp_regwriteD, fp_req_int_regwriteD, fp_mem_writeD, fp_mem_readD, fpucontrolD},
        {fp_alu_enE, fp_regwriteE, fp_req_int_regwriteE, fp_mem_writeE, fp_mem_readE, fpucontrolE}
    );

    // =======================================================================
    // 3. EXECUTE STAGE (FP)
    // =======================================================================
//    wire fp_requires_d = fp_alu_enD | fp_mem_writeD;

    fp_hazard_unit fp_hu(
        .rs1d(Rs1D), .rs2d(Rs2D), .rs3d(Rs3D),
        .rs1e(Rs1E), .rs2e(Rs2E), .rs3e(Rs3E), .rde(RdE),
        .rdm(RdM), .rdw(RdW_FP), 
        .fp_regwritee(fp_regwriteE),  // ---> ADDED Execute Write Enable
        .fp_regwritem(fp_regwriteM), .fp_regwritew(fp_regwriteW), .fp_mem_read_e(fp_mem_readE),
//         .fp_requires_d(fp_requires_d),
         .fp_requires_d(fast_fp_req_d),

         
        .forwarda_fp(ForwardA_FP), .forwardb_fp(ForwardB_FP), .forwardc_fp(ForwardC_FP), .fp_lwstall(fp_lwstall)
    );

//    assign SrcA_FP = (ForwardA_FP == 2'b10) ? FPU_FP_OutM : (ForwardA_FP == 2'b01) ? FP_ResultW  : FPRD1E;
//    assign SrcB_FP = (ForwardB_FP == 2'b10) ? FPU_FP_OutM : (ForwardB_FP == 2'b01) ? FP_ResultW  : FPRD2E;
//    assign SrcC_FP = (ForwardC_FP == 2'b10) ? FPU_FP_OutM : (ForwardC_FP == 2'b01) ? FP_ResultW  : FPRD3E;
// ---> NO MUXES! The data was already forwarded in Decode.
    assign SrcA_FP = FPRD1E;
    assign SrcB_FP = FPRD2E;
    assign SrcC_FP = FPRD3E;
    fpu fpu_inst(
        .clk(clk), .rst_n(reset), 
        .fp_alu_en(fp_alu_enE), .fpucontrol(fpucontrolE), .rm(rmE),
        .rs1_fp(SrcA_FP), .rs2_fp(SrcB_FP), .rs3_fp(SrcC_FP), .rs1_int(Int_SrcAE), 
        .fp_wb_data(FPU_FP_OutE), .int_wb_data(FPU_Int_OutE)
    );

    // =======================================================================
    // 4. E/M PIPELINE REGISTERS
    // =======================================================================
    pipe_reg #(16) e_m_fsw_data(clk, reset, !fp_sys_stall, 1'b0, SrcB_FP, FPRD2M);
    pipe_reg #(48) e_m_fpu_res(clk, reset, !fp_sys_stall, 1'b0, {FPU_FP_OutE, FPU_Int_OutE}, {FPU_FP_OutM, FPU_Int_OutM});
    pipe_reg #(5)  e_m_rd(clk, reset, !fp_sys_stall, 1'b0, RdE, RdM);
    pipe_reg #(4)  e_m_fp_ctrl(clk, reset, !fp_sys_stall, 1'b0, 
        {fp_regwriteE, fp_req_int_regwriteE, fp_mem_writeE, fp_mem_readE}, 
        {fp_regwriteM, fp_req_int_regwriteM, FP_MemWriteM,  fp_mem_readM}
    );

    // =======================================================================
    // 5. MEMORY STAGE (FP)
    // =======================================================================
    assign FP_MemWriteDataM = {16'd0, FPRD2M};

    // =======================================================================
    // 6. M/W PIPELINE REGISTERS
    // =======================================================================
    pipe_reg #(48) m_w_fpu_res(clk, reset, !fp_sys_stall, 1'b0, {FPU_FP_OutM, FPU_Int_OutM}, {FPU_FP_OutW, FP_IntDataW});
    pipe_reg #(10) m_w_rd(clk, reset, !fp_sys_stall, 1'b0, {RdM, RdM}, {RdW_FP, FP_IntRdW});
    pipe_reg #(3)  m_w_fp_ctrl(clk, reset, !fp_sys_stall, 1'b0, 
        {fp_regwriteM, fp_req_int_regwriteM, fp_mem_readM}, 
        {fp_regwriteW, FP_ReqIntWriteW,      fp_mem_readW}
    );

    // =======================================================================
    // 7. WRITEBACK STAGE (FP)
    // =======================================================================
    assign FP_ResultW = fp_mem_readW ? MemReadDataW[15:0] : FPU_FP_OutW;

endmodule