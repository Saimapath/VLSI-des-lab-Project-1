`timescale 1ns / 1ps
`include "../src_systolic_array/SA_Matmul.v"
`include "../src_systolic_array/MAC.v"
module matmul_tb();
    reg clk;
    reg reset;

    // Inputs to Systolic Array
    reg [15:0] A0, A1, A2, A3;
    reg [15:0] B0, B1, B2, B3;

    // Outputs from Systolic Array
    wire [15:0] C00, C01, C02, C03;
    wire [15:0] C10, C11, C12, C13;
    wire [15:0] C20, C21, C22, C23;
    wire [15:0] C30, C31, C32, C33;
    wire valid;

    // --- CYCLE COUNTER LOGIC ---
    integer global_cycle_count = 0;
    always @(posedge clk) begin
        global_cycle_count = global_cycle_count + 1;
    end

    // --- GOLDEN MODEL DATA STRUCTURES ---
    reg [15:0] matrix_A [0:3][0:3];
    reg [15:0] matrix_B [0:3][0:3];
    real expected_C_real [0:3][0:3];
    reg [15:0] expected_C_bin [0:3][0:3];

    // Helper: 16-bit FP to Real
    function real fp16_to_real(input [15:0] hex);
        reg sign;
        reg [4:0] exp;
        reg [9:0] mant;
        integer exp_int; 
        begin
            sign = hex[15];
            exp  = hex[14:10];
            mant = hex[9:0];
            exp_int = exp; 
            if (exp == 0) fp16_to_real = 0.0;
            else fp16_to_real = (sign ? -1.0 : 1.0) * (1.0 + (mant / 1024.0)) * (2.0**(exp_int - 15));
        end
    endfunction

    // Helper: Real to 16-bit FP Binary
    function [15:0] real_to_fp16(input real val);
        integer i;
        reg sign;
        reg [4:0] exp;
        reg [9:0] mant;
        real norm_val;
        begin
            if (val == 0.0 || val == -0.0) real_to_fp16 = 16'b0;
            else begin
                sign = (val < 0);
                norm_val = (val < 0) ? -val : val;
                exp = 15;
                if (norm_val >= 2.0) begin
                    while (norm_val >= 2.0 && exp < 30) begin
                        norm_val = norm_val / 2.0;
                        exp = exp + 1;
                    end
                end else if (norm_val < 1.0) begin
                    while (norm_val < 1.0 && exp > 0) begin
                        norm_val = norm_val * 2.0;
                        exp = exp - 1;
                    end
                end
                mant = (norm_val - 1.0) * 1024.0;
                real_to_fp16 = {sign, exp, mant};
            end
        end
    endfunction

    // Instantiate Unit Under Test
    SA_Matmul uut (
        .clk(clk), .reset(reset),
        .A0(A0), .A1(A1), .A2(A2), .A3(A3),
        .B0(B0), .B1(B1), .B2(B2), .B3(B3),
        .C00(C00), .C01(C01), .C02(C02), .C03(C03),
        .C10(C10), .C11(C11), .C12(C12), .C13(C13),
        .C20(C20), .C21(C21), .C22(C22), .C23(C23),
        .C30(C30), .C31(C31), .C32(C32), .C33(C33),
        .valid(valid)
    );

    always #20 clk = ~clk;

    // --- REUSABLE TEST TASK WITH CYCLE TRACKING ---
    task run_test(input [400:0] test_name);
        integer r, c, k;
        integer start_cycle, end_cycle, total_latency;
        begin
            $display("\n===============================================================");
            $display("RUNNING TEST: %0s", test_name);
            $display("===============================================================");

            // Calculate Expected Golden Model
            for(r=0; r<4; r=r+1) begin
                for(c=0; c<4; c=c+1) begin
                    expected_C_real[r][c] = 0;
                    for(k=0; k<4; k=k+1) begin
                        expected_C_real[r][c] = expected_C_real[r][c] + (fp16_to_real(matrix_A[r][k]) * fp16_to_real(matrix_B[k][c]));
                    end
                    expected_C_bin[r][c] = real_to_fp16(expected_C_real[r][c]);
                end
            end

            // Hard Reset the Array
            @(negedge clk);
            reset = 0;
            A0=0; A1=0; A2=0; A3=0; B0=0; B1=0; B2=0; B3=0;
            #60; 
            @(negedge clk);
            reset = 1;

// --- START STOPWATCH ---
            start_cycle = global_cycle_count;

            // Feed Data (4 Cycles)
            for(k=0; k<4; k=k+1) begin
                @(negedge clk);
                A0=matrix_A[0][k]; A1=matrix_A[1][k]; A2=matrix_A[2][k]; A3=matrix_A[3][k];
                B0=matrix_B[k][0]; B1=matrix_B[k][1]; B2=matrix_B[k][2]; B3=matrix_B[k][3];
            end

            // Flush Pipeline DYNAMICALLY (Wait for hardware valid signal!)
            while (valid == 0) begin
                @(negedge clk);
                A0=0; A1=0; A2=0; A3=0; B0=0; B1=0; B2=0; B3=0;
            end

            @(posedge clk); // Final Sync Edge
            
            // --- STOP STOPWATCH ---
            end_cycle = global_cycle_count;
            total_latency = end_cycle - start_cycle;

            
            // Verify All 16 Outputs
            if (C00 == expected_C_bin[0][0] && C01 == expected_C_bin[0][1] && C02 == expected_C_bin[0][2] && C03 == expected_C_bin[0][3] &&
                C10 == expected_C_bin[1][0] && C11 == expected_C_bin[1][1] && C12 == expected_C_bin[1][2] && C13 == expected_C_bin[1][3] &&
                C20 == expected_C_bin[2][0] && C21 == expected_C_bin[2][1] && C22 == expected_C_bin[2][2] && C23 == expected_C_bin[2][3] &&
                C30 == expected_C_bin[3][0] && C31 == expected_C_bin[3][1] && C32 == expected_C_bin[3][2] && C33 == expected_C_bin[3][3]) begin
                
                $display("---> STATUS:  [ %0s ] PASSED", test_name);
                $display("---> LATENCY: %0d Clock Cycles (Feed + Matrix Processing Time)", total_latency);
            end else begin
                $display("---> STATUS:  [ %0s ] FAILED", test_name);
                $display("---> LATENCY: %0d Clock Cycles", total_latency);
                
                $display("\n--- EXPECTED MATRIX (Hex) ---");
                $display("%h %h %h %h", expected_C_bin[0][0], expected_C_bin[0][1], expected_C_bin[0][2], expected_C_bin[0][3]);
                $display("%h %h %h %h", expected_C_bin[1][0], expected_C_bin[1][1], expected_C_bin[1][2], expected_C_bin[1][3]);
                $display("%h %h %h %h", expected_C_bin[2][0], expected_C_bin[2][1], expected_C_bin[2][2], expected_C_bin[2][3]);
                $display("%h %h %h %h", expected_C_bin[3][0], expected_C_bin[3][1], expected_C_bin[3][2], expected_C_bin[3][3]);
                
                $display("\n--- ACTUAL MATRIX (Hex) ---");
                $display("%h %h %h %h", C00, C01, C02, C03);
                $display("%h %h %h %h", C10, C11, C12, C13);
                $display("%h %h %h %h", C20, C21, C22, C23);
                $display("%h %h %h %h", C30, C31, C32, C33);
            end
        end
    endtask

    // --- MAIN EXECUTION ---
    integer r_idx, c_idx;
    initial begin
        $dumpfile("MATMUL_sim.vcd");
        $dumpvars(0, matmul_tb);
        clk = 0; reset = 0;

        // ---------------------------------------------------------
        // TEST 1: The Original Matrix (Incrementing A * All 1.0s B)
        // ---------------------------------------------------------
        matrix_A[0][0]=16'h3C00; matrix_A[0][1]=16'h3C00; matrix_A[0][2]=16'h3C00; matrix_A[0][3]=16'h3C00; 
        matrix_A[1][0]=16'h4000; matrix_A[1][1]=16'h4000; matrix_A[1][2]=16'h4000; matrix_A[1][3]=16'h4000; 
        matrix_A[2][0]=16'h4200; matrix_A[2][1]=16'h4200; matrix_A[2][2]=16'h4200; matrix_A[2][3]=16'h4200; 
        matrix_A[3][0]=16'h4400; matrix_A[3][1]=16'h4400; matrix_A[3][2]=16'h4400; matrix_A[3][3]=16'h4400; 
        for(r_idx=0; r_idx<4; r_idx=r_idx+1)
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) matrix_B[r_idx][c_idx] = 16'h3C00; 
        
        run_test("Test 1: Incrementing A x Ones B");

        // ---------------------------------------------------------
        // TEST 2: Identity Matrix Multiplication
        // ---------------------------------------------------------
        for(r_idx=0; r_idx<4; r_idx=r_idx+1)
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) matrix_A[r_idx][c_idx] = 16'h4000; 
        
        for(r_idx=0; r_idx<4; r_idx=r_idx+1)
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) matrix_B[r_idx][c_idx] = 16'h0000; 
        matrix_B[0][0]=16'h3C00; matrix_B[1][1]=16'h3C00; matrix_B[2][2]=16'h3C00; matrix_B[3][3]=16'h3C00; 
        
        run_test("Test 2: A x Identity Matrix");

        // ---------------------------------------------------------
        // TEST 3: Decimal Fractions (0.5 * 2.0)
        // ---------------------------------------------------------
        for(r_idx=0; r_idx<4; r_idx=r_idx+1) begin
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) begin
                matrix_A[r_idx][c_idx] = 16'h3800; // 0.5
                matrix_B[r_idx][c_idx] = 16'h4000; // 2.0
            end
        end
        run_test("Test 3: Fractions (0.5 x 2.0)");

        // ---------------------------------------------------------
        // TEST 4: Mixed Signs & Cancellation (Corner Case)
        // ---------------------------------------------------------
        for(r_idx=0; r_idx<4; r_idx=r_idx+1) begin
            matrix_A[r_idx][0] = 16'h3C00; //  1.0
            matrix_A[r_idx][1] = 16'hBC00; // -1.0 
            matrix_A[r_idx][2] = 16'h4000; //  2.0
            matrix_A[r_idx][3] = 16'hC000; // -2.0 
        end
        for(r_idx=0; r_idx<4; r_idx=r_idx+1)
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) matrix_B[r_idx][c_idx] = 16'h3C00;
        
        run_test("Test 4: Mixed Signs & Cancellation to Zero");

        // ---------------------------------------------------------
        // TEST 5: Large Exponents vs Small Exponents (Corner Case)
        // ---------------------------------------------------------
        for(r_idx=0; r_idx<4; r_idx=r_idx+1)
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) matrix_A[r_idx][c_idx] = 16'h5000; // 32.0 
            
        for(r_idx=0; r_idx<4; r_idx=r_idx+1)
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) matrix_B[r_idx][c_idx] = 16'h2800; // 0.03125 
            
        run_test("Test 5: Extreme Exponents (32.0 x 0.03125)");

        // ---------------------------------------------------------
        // TEST 6: Checkerboard Pattern (Spatial Routing Check)
        // ---------------------------------------------------------
        for(r_idx=0; r_idx<4; r_idx=r_idx+1) begin
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) begin
                if ((r_idx + c_idx) % 2 == 0) begin
                    matrix_A[r_idx][c_idx] = 16'h3C00;
                    matrix_B[r_idx][c_idx] = 16'h3C00;
                end else begin
                    matrix_A[r_idx][c_idx] = 16'h0000;
                    matrix_B[r_idx][c_idx] = 16'h0000;
                end
            end
        end
        run_test("Test 6: Checkerboard Matrix (Routing Check)");

        // ---------------------------------------------------------
        // TEST 7: The Null Matrix 
        // ---------------------------------------------------------
        for(r_idx=0; r_idx<4; r_idx=r_idx+1) begin
            for(c_idx=0; c_idx<4; c_idx=c_idx+1) begin
                matrix_A[r_idx][c_idx] = 16'h0000;
                matrix_B[r_idx][c_idx] = 16'h0000;
            end
        end
        run_test("Test 7: All Zeroes Matrix");

        $display("\n===============================================================");
        $display("ALL TESTS COMPLETED.");
        $display("===============================================================");
        $finish;
    end
endmodule