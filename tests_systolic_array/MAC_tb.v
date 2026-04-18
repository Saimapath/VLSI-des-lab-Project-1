`timescale 1ns / 1ps
`include "../src_systolic_array/MAC.v"

module MAC_tb();

    reg clk;
    reg reset;
    reg [15:0] Ain, Bin;
    wire [15:0] Aout, Bout, C;

    // Internal variables for checking
    real expected_accum = 0.0;
    real expected_prod_reg = 0.0; 

    // Intermediate variables for $strobe (iverilog workaround)
    real real_Ain, real_Bin, real_C;
    reg [31:0] status_str; // 32 bits to hold the 4-character string "PASS" or "FAIL"

    // Function to convert 16-bit Hex (Half Precision) to Real
    function real hex_to_real(input [15:0] hex);
        reg sign;
        reg [4:0] exp;
        reg [9:0] mant;
        begin
            sign = hex[15];
            exp = hex[14:10];
            mant = hex[9:0];
            if (exp == 0) hex_to_real = 0.0;
            else hex_to_real = (sign ? -1.0 : 1.0) * (1.0 + (mant / 1024.0)) * (2.0**(exp - 15));
        end
    endfunction

    // Instantiate Unit Under Test
    MAC uut (
        .Ain(Ain), .Bin(Bin), .clk(clk), .reset(reset),
        .Aout(Aout), .Bout(Bout), .C(C)
    );

    // Clock Generation
    always #15 clk = ~clk;

    initial begin
        $dumpfile("MAC_sim.vcd");
        $dumpvars(0, MAC_tb);

        clk = 0; reset = 0; Ain = 0; Bin = 0;
        
        $display("--------------------------------------------------------------------------------------------------");
        $display("Time\t| Ain [Real] \t\t| Bin [Real] \t\t|| Expected C \t| Actual C [Real] \t| Match?");
        $display("--------------------------------------------------------------------------------------------------");

        @(negedge clk); 
        reset = 1;

        // Test Case 1: 1.0 * 2.0 = 2.0
        @(negedge clk); 
        Ain = 16'h3C00; Bin = 16'h4000; 
        
        // Test Case 2: 2.0 * 3.0 = 6.0
        @(negedge clk); 
        Ain = 16'h4000; Bin = 16'h4200; 

        // Test Case 3: 0.5 * 1.0 = 0.5
        @(negedge clk); 
        Ain = 16'h3800; Bin = 16'h3C00; 

        // Flush pipeline (Push 0s so the final accumulation triggers)
        @(negedge clk);
        Ain = 16'h0000; Bin = 16'h0000; 
        @(negedge clk);

        // Let the pipeline finish
        #90;
        $display("--------------------------------------------------------------------------------------------------");
        $finish;
    end

    // GOLDEN MODEL: Exactly matches the 2-stage hardware pipeline
    always @(posedge clk) begin
        if (!reset) begin
            expected_accum <= 0.0;
            expected_prod_reg <= 0.0;
        end else begin
            expected_prod_reg <= hex_to_real(Ain) * hex_to_real(Bin);
            expected_accum <= expected_accum + expected_prod_reg;
        end
    end

    // INTERMEDIATE ASSIGNMENTS: Workaround for iverilog $strobe limitations
    always @(*) begin
        real_Ain = hex_to_real(Ain);
        real_Bin = hex_to_real(Bin);
        real_C   = hex_to_real(C);
        
        if (real_C == expected_accum) 
            status_str = "PASS";
        else 
            status_str = "FAIL";
    end

    // MONITOR: Now passes simple variables instead of complex expressions
    always @(posedge clk) begin
        if (reset) begin
            $strobe("%0t\t| %h [%.2f] \t| %h [%.2f] \t|| %.2f \t| %h [%.2f] \t| %0s", 
                $time, 
                Ain, real_Ain, 
                Bin, real_Bin, 
                expected_accum, 
                C, real_C,
                status_str
            );
        end
    end

endmodule