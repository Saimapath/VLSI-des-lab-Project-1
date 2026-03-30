`timescale 1ns / 1ps
`include "../src_fp/fp_mac.v"
`include "../src_fp/fp_mult.v"
`include "../src_fp/fp_adder.v"
`include "../src_fp/fp_sign_inj.v"
`include "../src_fp/fp_convert.v"
`include "../src_fp/fp_compare.v"
`include "../src_fp/fpu.v"


module fpu_tb();

    // --- Inputs ---
    reg        clk;
    reg        rst_n;
    reg        fp_alu_en;
    reg [4:0]  fpucontrol;
    reg [2:0]  rm;
    reg [15:0] rs1_fp, rs2_fp, rs3_fp;
    reg [31:0] rs1_int;

    // --- Outputs ---
    wire [15:0] fp_wb_data;
    wire [31:0] int_wb_data;

    // --- Error Tracking ---
    integer errors = 0;
    integer tests_run = 0;

    // --- FPU Control Codes ---
    localparam FPU_FMADD=5'd1, FPU_FMSUB=5'd2, FPU_FNMSUB=5'd3, FPU_FNMADD=5'd4;
    localparam FPU_FADD=5'd5,  FPU_FSUB=5'd6,  FPU_FMUL=5'd7;
    localparam FPU_FSGNJ=5'd10,FPU_FSGNJN=5'd11,FPU_FSGNJX=5'd12;
    localparam FPU_FMIN=5'd13, FPU_FMAX=5'd14;
    localparam FPU_FEQ=5'd15,  FPU_FLT=5'd16,  FPU_FLE=5'd17;
    localparam FPU_FCLASS=5'd18;
    localparam FPU_FCVT_W_S=5'd19, FPU_FCVT_WU_S=5'd20, FPU_FCVT_S_W=5'd21;

    // --- FP16 Hex Constants ---
    localparam FP16_0_0     = 16'h0000;
    localparam FP16_NEG_0_0 = 16'h8000;
    localparam FP16_0_5     = 16'h3800;
    localparam FP16_NEG_0_5 = 16'hB800;
    localparam FP16_1_0     = 16'h3C00;
    localparam FP16_1_5     = 16'h3E00;
    localparam FP16_2_0     = 16'h4000;
    localparam FP16_NEG_2_0 = 16'hC000;
    localparam FP16_3_0     = 16'h4200;
    localparam FP16_NEG_3_0 = 16'hC200;
    localparam FP16_4_0     = 16'h4400;
    localparam FP16_5_0     = 16'h4500;
    localparam FP16_NEG_5_0 = 16'hC500;
    localparam FP16_6_0     = 16'h4600;
    localparam FP16_10_0    = 16'h4900;
    localparam FP16_NEG_10_0= 16'hC900;
    
    localparam FP16_INF     = 16'h7C00;
    localparam FP16_NEG_INF = 16'hFC00;
    localparam FP16_QNAN    = 16'h7E00; // Canonical NaN

    // --- Instantiate DUT ---
    fpu dut (
        .clk(clk), .rst_n(rst_n),
        .fp_alu_en(fp_alu_en), .fpucontrol(fpucontrol), .rm(rm),
        .rs1_fp(rs1_fp), .rs2_fp(rs2_fp), .rs3_fp(rs3_fp), .rs1_int(rs1_int),
        .fp_wb_data(fp_wb_data), .int_wb_data(int_wb_data)
    );

    // --- Clock Generation ---
    always #4 clk = ~clk;

    // =======================================================================
    // VERIFICATION TASKS (Same as before, hidden for brevity in explanation)
    // =======================================================================
    task check_mac_op;
        input [80*8:1] test_name; input [4:0] ctrl; input [15:0] in_r1, in_r2, in_r3, expected_fp;
        begin
            @(negedge clk);
            fp_alu_en = 1; fpucontrol = ctrl; rm = 3'b000;
            rs1_fp = in_r1; rs2_fp = in_r2; rs3_fp = in_r3;
            @(posedge clk); @(posedge clk); #1; 
            tests_run = tests_run + 1;
            if (fp_wb_data !== expected_fp) begin
                $display("[FAIL] %s | Exp: %h, Got: %h", test_name, expected_fp, fp_wb_data);
                errors = errors + 1;
            end else $display("[PASS] %s | Res: %h", test_name, fp_wb_data);
        end
    endtask

    task check_comb_op;
        input [80*8:1] test_name; input [4:0] ctrl; input [2:0] rm_val; input [15:0] in_r1, in_r2; input [31:0] in_r1_int; input [15:0] expected_fp; input [31:0] expected_int; input check_int;
        begin
            @(negedge clk);
            fp_alu_en = 1; fpucontrol = ctrl; rm = rm_val;
            rs1_fp = in_r1; rs2_fp = in_r2; rs1_int = in_r1_int;
            #1; tests_run = tests_run + 1;
            if (check_int) begin
                if (int_wb_data !== expected_int) begin
                    $display("[FAIL] %s | Exp: %h, Got: %h", test_name, expected_int, int_wb_data);
                    errors = errors + 1;
                end else $display("[PASS] %s | Res: %h", test_name, int_wb_data);
            end else begin
                if (fp_wb_data !== expected_fp) begin
                    $display("[FAIL] %s | Exp: %h, Got: %h", test_name, expected_fp, fp_wb_data);
                    errors = errors + 1;
                end else $display("[PASS] %s | Res: %h", test_name, fp_wb_data);
            end
        end
    endtask

    // =======================================================================
    // TEST SEQUENCE
    // =======================================================================
    initial begin
        clk = 0; rst_n = 0; #15 rst_n = 1;
        $display("\n==========================================================");
        $display(" RUNNING COMPREHENSIVE FPU TEST SUITE");
        $display("==========================================================\n");

        $display("--- 1. MAC / PIPELINED MATH (Normal & Edge Cases) ---");
        // Standard Math
        check_mac_op("FADD: 1.5 + 2.0 = 3.5      ", FPU_FADD,  FP16_1_5,     FP16_2_0, 16'd0, 16'h4300);
        check_mac_op("FSUB: 1.5 - 2.0 = -0.5     ", FPU_FSUB,  FP16_1_5,     FP16_2_0, 16'd0, FP16_NEG_0_5);
        check_mac_op("FMUL: -2.0 * 3.0 = -6.0    ", FPU_FMUL,  FP16_NEG_2_0, FP16_3_0, 16'd0, 16'hC600);
        
        // FMA Variants (Testing the hardware sign flips)
        check_mac_op("FMADD : +(2*3) + 4 = 10.0  ", FPU_FMADD, FP16_2_0, FP16_3_0, FP16_4_0, FP16_10_0);
        check_mac_op("FMSUB : +(2*3) - 4 = 2.0   ", FPU_FMSUB, FP16_2_0, FP16_3_0, FP16_4_0, FP16_2_0);
        check_mac_op("FNMSUB: -(2*3) + 4 = -2.0  ", FPU_FNMSUB,FP16_2_0, FP16_3_0, FP16_4_0, FP16_NEG_2_0);
        check_mac_op("FNMADD: -(2*3) - 4 = -10.0 ", FPU_FNMADD,FP16_2_0, FP16_3_0, FP16_4_0, FP16_NEG_10_0);
        
        // Zero Math
        check_mac_op("FADD: 2.0 + 0.0 = 2.0      ", FPU_FADD,  FP16_2_0, FP16_0_0, 16'd0, FP16_2_0);
        check_mac_op("FMUL: 5.0 * 0.0 = 0.0      ", FPU_FMUL,  FP16_5_0, FP16_0_0, 16'd0, FP16_0_0);

        $display("\n--- 2. SIGN INJECTION ---");
        check_comb_op("FSGNJ:  Inject - to +2.0   ", FPU_FSGNJ,  3'b000, FP16_2_0,     FP16_NEG_3_0, 32'd0, FP16_NEG_2_0, 32'd0, 0);
        check_comb_op("FSGNJN: Inject inverted -  ", FPU_FSGNJN, 3'b000, FP16_NEG_2_0, FP16_NEG_3_0, 32'd0, FP16_2_0,     32'd0, 0);
        check_comb_op("FSGNJX: XOR Signs (- & -)  ", FPU_FSGNJX, 3'b000, FP16_NEG_2_0, FP16_NEG_3_0, 32'd0, FP16_2_0,     32'd0, 0);

        $display("\n--- 3. MIN / MAX & NaN PROPAGATION ---");
        check_comb_op("FMIN: min(-2.0, 3.0) = -2  ", FPU_FMIN, 3'b000, FP16_NEG_2_0, FP16_3_0, 32'd0, FP16_NEG_2_0, 32'd0, 0);
        check_comb_op("FMAX: max(-2.0, 3.0) =  3  ", FPU_FMAX, 3'b001, FP16_NEG_2_0, FP16_3_0, 32'd0, FP16_3_0,     32'd0, 0);
        check_comb_op("FMIN: -0.0 < +0.0 (IEEE)   ", FPU_FMIN, 3'b000, FP16_NEG_0_0, FP16_0_0, 32'd0, FP16_NEG_0_0, 32'd0, 0);
        check_comb_op("FMAX: NaN & 5.0 -> 5.0     ", FPU_FMAX, 3'b001, FP16_QNAN,    FP16_5_0, 32'd0, FP16_5_0,     32'd0, 0);

        $display("\n--- 4. COMPARISONS ---");
        check_comb_op("FEQ: 2.0 == 2.0 -> True    ", FPU_FEQ, 3'b010, FP16_2_0,     FP16_2_0, 32'd0, 16'd0, 32'd1, 1);
        check_comb_op("FEQ: -0.0 == +0.0 -> True  ", FPU_FEQ, 3'b010, FP16_NEG_0_0, FP16_0_0, 32'd0, 16'd0, 32'd1, 1);
        check_comb_op("FLT: -3.0 < -2.0 -> True   ", FPU_FLT, 3'b011, FP16_NEG_3_0, FP16_NEG_2_0, 32'd0, 16'd0, 32'd1, 1);
        check_comb_op("FLT: 5.0 < NaN -> False    ", FPU_FLT, 3'b011, FP16_5_0,     FP16_QNAN,32'd0, 16'd0, 32'd0, 1);

        $display("\n--- 5. CONVERSIONS (Float <-> Int) ---");
        check_comb_op("FCVT.W.S:  1.5 -> Int 1    ", FPU_FCVT_W_S,  3'b000, FP16_1_5,     16'd0, 32'd0, 16'd0, 32'd1, 1); // Truncates decimal
        check_comb_op("FCVT.W.S: -2.0 -> Int -2   ", FPU_FCVT_W_S,  3'b000, FP16_NEG_2_0, 16'd0, 32'd0, 16'd0, 32'hFFFFFFFE, 1); // Two's complement -2
        check_comb_op("FCVT.WU.S: -2.0 -> Int 0   ", FPU_FCVT_WU_S, 3'b000, FP16_NEG_2_0, 16'd0, 32'd0, 16'd0, 32'd0, 1); // Neg to Unsigned clamps to 0
        check_comb_op("FCVT.S.W:  Int 5 -> 5.0    ", FPU_FCVT_S_W,  3'b000, 16'd0, 16'd0, 32'd5, FP16_5_0, 32'd0, 0);
        check_comb_op("FCVT.S.W:  Int -5 -> -5.0  ", FPU_FCVT_S_W,  3'b000, 16'd0, 16'd0, 32'hFFFFFFFB, FP16_NEG_5_0, 32'd0, 0);

        $display("\n--- 6. CLASSIFICATION (FCLASS) ---");
        // Output is a 10-bit mask. 
        check_comb_op("FCLASS: -Inf -> Bit 0      ", FPU_FCLASS, 3'b001, FP16_NEG_INF, 16'd0, 32'd0, 16'd0, 32'h001, 1);
        check_comb_op("FCLASS: -0.0 -> Bit 3      ", FPU_FCLASS, 3'b001, FP16_NEG_0_0, 16'd0, 32'd0, 16'd0, 32'h008, 1);
        check_comb_op("FCLASS: +Norm-> Bit 6      ", FPU_FCLASS, 3'b001, FP16_2_0,     16'd0, 32'd0, 16'd0, 32'h040, 1);
        check_comb_op("FCLASS: QNaN -> Bit 9      ", FPU_FCLASS, 3'b001, FP16_QNAN,    16'd0, 32'd0, 16'd0, 32'h200, 1);

        // --- Final Summary ---
        $display("\n==========================================================");
        if (errors == 0) begin
            $display(" [SUCCESS] ALL %0d TESTS PASSED! YOUR FPU IS FLAWLESS.", tests_run);
        end else begin
            $display(" [WARNING] %0d OUT OF %0d TESTS FAILED. CHECK LOGS ABOVE.", errors, tests_run);
        end
        $display("==========================================================\n");
        
        #20;
        $finish;
    end
endmodule