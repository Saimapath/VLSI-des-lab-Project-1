`timescale 1ns/1ps
`include "../src/regfile.v"

module regfile_tb;
    logic clk, RegWriteW;
    logic [4:0]  Rs1D, Rs2D, RdW;
    logic [31:0] ResultW, RD1D, RD2D;

    // Instantiate Register File
    regfile dut (clk, RegWriteW, Rs1D, Rs2D, RdW, ResultW, RD1D, RD2D);

    // Clock Generation
    always #5 clk = ~clk;

    // Simplified Self-Checking Logic for x0
    always @(posedge clk) begin
        if (Rs1D == 5'd0) begin
            assert(RD1D === 32'h0) 
                else $error("CRITICAL: x0 is not zero! Got %h", RD1D);
        end
    end

    initial begin
        // Initialize signals
        clk = 0; RegWriteW = 0; Rs1D = 0; Rs2D = 0; RdW = 0; ResultW = 0;
        #10; // Wait for initialization

        // Test Case 1: Write to x5
        $display("Writing DEADBEEF to x5...");
        @(negedge clk);
        RegWriteW = 1; 
        RdW = 5'd5; 
        ResultW = 32'hDEAD_BEEF;
        
        @(posedge clk); // Data is latched here
        #1;             // Small delay to ensure memory is updated
        RegWriteW = 0;

        // Test Case 2: Read back x5
        $display("Reading back x5...");
        Rs1D = 5'd5;
        #1; // Asynchronous read settle time
        assert(RD1D === 32'hDEAD_BEEF) 
            else $error("RegFile Fail: x5 mismatch! Got %h at %d", RD1D, Rs1D);

        $display("RegFile Test Finished.");
        $finish;
    end
endmodule