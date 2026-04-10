module fpu (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control Signals from fp_controller
    input  wire        fp_alu_en,
    input  wire [4:0]  fpucontrol,
    input  wire [2:0]  rm,         // Rounding mode
    
    // Data Inputs
    input  wire [15:0] rs1_fp,     // Floating-point Register 1
    input  wire [15:0] rs2_fp,     // Floating-point Register 2
    input  wire [15:0] rs3_fp,     // Floating-point Register 3 (for FMA)
    input  wire [31:0] rs1_int,    // Integer Register 1 (for Conversions/Moves)
    
    // Data Outputs
    output wire [15:0] fp_wb_data, // Data to write to Floating-Point Register File (fd)
    output wire [31:0] int_wb_data // Data to write to Integer Register File (rd)
);

    // --- FPU Control Command Dictionary (Must match fp_controller) ---
    localparam FPU_NOP      = 5'd0;
    localparam FPU_FMADD    = 5'd1;  localparam FPU_FMSUB    = 5'd2;
    localparam FPU_FNMSUB   = 5'd3;  localparam FPU_FNMADD   = 5'd4;
    localparam FPU_FADD     = 5'd5;  localparam FPU_FSUB     = 5'd6;
    localparam FPU_FMUL     = 5'd7;  localparam FPU_FDIV     = 5'd8;
    localparam FPU_FSQRT    = 5'd9;  localparam FPU_FSGNJ    = 5'd10;
    localparam FPU_FSGNJN   = 5'd11; localparam FPU_FSGNJX   = 5'd12;
    localparam FPU_FMIN     = 5'd13; localparam FPU_FMAX     = 5'd14;
    localparam FPU_FEQ      = 5'd15; localparam FPU_FLT      = 5'd16;
    localparam FPU_FLE      = 5'd17; localparam FPU_FCLASS   = 5'd18;
    localparam FPU_FCVT_W_S = 5'd19; localparam FPU_FCVT_WU_S= 5'd20;
    localparam FPU_FCVT_S_W = 5'd21; localparam FPU_FCVT_S_WU= 5'd22;
    localparam FPU_FMV_X_W  = 5'd23; localparam FPU_FMV_W_X  = 5'd24;

    // ==========================================
    // 1. MAC UNIT (Handles FMA, FADD, FSUB, FMUL)
    // ==========================================
    wire [15:0] mac_result, mac_mul_result;
    
    // For FNMADD and FNMSUB, we mathematically negate A: -(A * B) == (-A * B)
    wire negate_a = (fpucontrol == FPU_FNMSUB) || (fpucontrol == FPU_FNMADD);
    wire [15:0] a_val = negate_a ? {~rs1_fp[15], rs1_fp[14:0]} : rs1_fp;

    // Route Inputs to the MAC equation: Result = (A * B) +/- C
    wire [15:0] mac_a = a_val;
    
    wire [15:0] mac_b = (fpucontrol == FPU_FADD || fpucontrol == FPU_FSUB) ? 16'h3C00 : rs2_fp; // 1.0 for Add/Sub
    
    wire [15:0] mac_c = (fpucontrol == FPU_FMUL) ? 16'h0000 : // 0.0 for FMUL
                        (fpucontrol == FPU_FADD || fpucontrol == FPU_FSUB) ? rs2_fp :
                        rs3_fp; // Standard FMA uses rs3
                        
    // Subtract C if instruction is FMSUB, FNMADD, or FSUB
    wire mac_add_sub  = (fpucontrol == FPU_FMSUB || fpucontrol == FPU_FNMADD || fpucontrol == FPU_FSUB) ? 1'b1 : 1'b0;

    fp_mac_pipelined u_mac (
        .clk(clk), .rst_n(rst_n),
        .a(mac_a), .b(mac_b), .c(mac_c),
        .add_sub(mac_add_sub), 
        .rm(rm),

        .mul_result(mac_mul_result),
        .result(mac_result)
    );

    // ==========================================
    // 2. COMPARATOR & CLASSIFIER 
    // ==========================================
    wire cmp_feq, cmp_flt, cmp_fle;
    wire [15:0] cmp_fmin, cmp_fmax;
    wire [9:0]  class_mask;

    fp_compare u_cmp (
        .a(rs1_fp), .b(rs2_fp),
        .feq(cmp_feq), .flt(cmp_flt), .fle(cmp_fle),
        .fmin(cmp_fmin), .fmax(cmp_fmax),
        .a_class(class_mask)
    );

    // ==========================================
    // 3. SIGN INJECTOR
    // ==========================================
    wire [15:0] sgnj_result;
    
    // Convert 5-bit FPU control back to the 3-bit code the injector expects
    wire [2:0] sgnj_cmd = (fpucontrol == FPU_FSGNJN) ? 3'b001 :
                          (fpucontrol == FPU_FSGNJX) ? 3'b010 : 3'b000;

    fp_sign_inject u_sgnj (
        .rs1(rs1_fp), .rs2(rs2_fp),
        .funct3(sgnj_cmd),
        .result(sgnj_result)
    );

    // ==========================================
    // 4. CONVERTER UNIT
    // ==========================================
    wire [31:0] cvt_int_out;
    wire [15:0] cvt_fp_out;
    
    // Signed casts are W_S and S_W. Unsigned are WU_S and S_WU.
    wire is_signed_cast = (fpucontrol == FPU_FCVT_W_S) || (fpucontrol == FPU_FCVT_S_W);

    fp_convert u_cvt (
        .f_in(rs1_fp),
        .i_in(rs1_int),
        .is_signed(is_signed_cast),
        .i_out(cvt_int_out),
        .f_out(cvt_fp_out)
    );

    // ==========================================
    // 5. OUTPUT SWITCHBOARD (Routing to Writeback)
    // ==========================================
    
    // --- Data bound for Floating-Point Register File (fd) ---
    assign fp_wb_data = 
        (fpucontrol == FPU_FMIN)      ? cmp_fmin :
        (fpucontrol == FPU_FMAX)      ? cmp_fmax :
        (fpucontrol == FPU_FSGNJ  || 
         fpucontrol == FPU_FSGNJN || 
         fpucontrol == FPU_FSGNJX)    ? sgnj_result :
        (fpucontrol == FPU_FCVT_S_W || 
         fpucontrol == FPU_FCVT_S_WU) ? cvt_fp_out :
        (fpucontrol == FPU_FMV_W_X)   ? rs1_int[15:0] :
        (fpucontrol == FPU_FDIV || 
         fpucontrol == FPU_FSQRT)     ? 16'hFFFF : // TBD: Div/Sqrt Not Implemented Yet
         (fpucontrol == FPU_FMADD || 
          fpucontrol == FPU_FMSUB || 
          fpucontrol == FPU_FNMSUB || 
          fpucontrol == FPU_FNMADD || 
          fpucontrol == FPU_FADD || 
          fpucontrol == FPU_FSUB)    ? mac_result :
          (fpucontrol == FPU_FMUL)    ? mac_result :
         16'h0; // Default case

    // --- Data bound for Integer Register File (rd) ---
    // RISC-V Zfh Extension standard: fmv.x.h sign-extends the 16-bit float into the 32-bit register
    wire [31:0] fmv_x_w_extended = {{16{rs1_fp[15]}}, rs1_fp};

    assign int_wb_data = 
        (fpucontrol == FPU_FEQ)       ? {31'd0, cmp_feq} :
        (fpucontrol == FPU_FLT)       ? {31'd0, cmp_flt} :
        (fpucontrol == FPU_FLE)       ? {31'd0, cmp_fle} :
        (fpucontrol == FPU_FCLASS)    ? {22'd0, class_mask} :
        (fpucontrol == FPU_FCVT_W_S || 
         fpucontrol == FPU_FCVT_WU_S) ? cvt_int_out :
        (fpucontrol == FPU_FMV_X_W)   ? fmv_x_w_extended :
        32'd0;

endmodule