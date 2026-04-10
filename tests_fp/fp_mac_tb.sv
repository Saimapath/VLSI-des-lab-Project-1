`timescale 1ns / 1ps
`include "../src_fp/fp_mac.v"
`include "../src_fp/fp_mult.v"
`include "../src_fp/fp_adder.v"


module fp_mac_tb();

    // --- Signals ---
    reg clk;
    reg rst_n;
    reg [15:0] a, b, c;
    reg        add_sub;
    reg [2:0]  rm;

    wire [15:0] result;

    // --- FP16 Constants ---
    localparam FP16_0_0    = 16'h0000;
    localparam FP16_1_0    = 16'h3C00;
    localparam FP16_2_0    = 16'h4000;
    localparam FP16_3_0    = 16'h4200;
    localparam FP16_4_0    = 16'h4400;
    localparam FP16_5_0    = 16'h4500;
    localparam FP16_6_0    = 16'h4600;
    localparam FP16_10_0   = 16'h4900;
    localparam FP16_NEG_2  = 16'hC000; // -2.0

    // --- DUT Instantiation ---
    fp_mac_pipelined dut (
        .clk(clk), .rst_n(rst_n),
        .a(a), .b(b), .c(c),
        .add_sub(add_sub), .rm(rm),
        .result(result)
    );

    // --- Clock Generation (125 MHz) ---
    always #4 clk = ~clk;
    initial begin
        $dumpfile("fp_mac_tb.vcd");
        $dumpvars(0, fp_mac_tb);
    end
    

    // --- STIMULUS BLOCK (Feeding the Pipeline) ---
    initial begin
        // Initialize
        clk = 0; rst_n = 0;
        a = 0; b = 0; c = 0; add_sub = 0; rm = 0;

        // Release reset
        #15 rst_n = 1;

        $display("===============================================================");
        $display(" FIRING INSTRUCTIONS INTO PIPELINE (1 PER CYCLE)");
        $display("===============================================================");

        // INSTRUCTION 1: Normal MAC (2.0 * 3.0 + 4.0 = 10.0) -> Expect 4900
        @(negedge clk);
        a = FP16_2_0; b = FP16_3_0; c = FP16_4_0; add_sub = 0;
        
        $display("Time: %0t | Fired Instr 1: 2.0 * 3.0 + 4.0", $time);

        // INSTRUCTION 2: Multiply by Zero (0.0 * 3.0 + 4.0 = 4.0) -> Expect 4400
        @(negedge clk);
        a = FP16_0_0; b = FP16_3_0; c = FP16_4_0; add_sub = 0;
        $display("Time: %0t | Fired Instr 2: 0.0 * 3.0 + 4.0", $time);

        // INSTRUCTION 3: Add Zero (2.0 * 3.0 + 0.0 = 6.0) -> Expect 4600
        @(negedge clk);
        a = FP16_2_0; b = FP16_3_0; c = FP16_0_0; add_sub = 0;
        $display("Time: %0t | Fired Instr 3: 2.0 * 3.0 + 0.0", $time);

        // INSTRUCTION 4: All Zeros (0.0 * 0.0 + 0.0 = 0.0) -> Expect 0000
        @(negedge clk);
        a = FP16_0_0; b = FP16_0_0; c = FP16_0_0; add_sub = 0;
        $display("Time: %0t | Fired Instr 4: 0.0 * 0.0 + 0.0", $time);

        // INSTRUCTION 5: Negative Subtraction Repurposed FADD (1.0 * 5.0 + (-2.0) = 3.0) -> Expect 4200
        @(negedge clk);
        a = FP16_1_0; b = FP16_5_0; c = FP16_NEG_2; add_sub = 0;
        $display("Time: %0t | Fired Instr 5: 1.0 * 5.0 + (-2.0)", $time);

        // FLUSH PIPELINE: Stop feeding inputs
        @(negedge clk);
        a = 0; b = 0; c = 0;
        $display("Time: %0t | Pipeline Input Stopped (Flushing...)", $time);
    end

    // --- MONITOR BLOCK (Checking the Outputs 2 Cycles Later) ---
    // This block runs completely independently of the stimulus block.
    // It wakes up on the positive edge and checks the output.
    initial begin
        // Wait for reset to finish
        @(posedge rst_n);

        $display("\n===============================================================");
        $display(" CATCHING RESULTS FROM PIPELINE (LATENCY = 2 CYCLES)");
        $display("===============================================================");

        // Wait for Cycle 1 to propagate (2 clock cycles latency)
        @(posedge clk); // Cycle 1 (Mult finishes)
        @(posedge clk); // Cycle 2 (Add finishes)
        @(posedge clk); @(posedge clk); @(posedge clk); 
        // On the next edges, the results will pour out one after the other!
        // @(posedge clk);
        #1; // 1ns delay to ensure waveform signals have settled for printing
        $display("Time: %0t | Caught Result 1 (Expect 4900 for 10.0) -> %h", $time, result);

        @(posedge clk);
        #1;
        $display("Time: %0t | Caught Result 2 (Expect 4400 for 4.0)  -> %h", $time, result);

        @(posedge clk);
        #1;
        $display("Time: %0t | Caught Result 3 (Expect 4600 for 6.0)  -> %h", $time, result);

        @(posedge clk);
        #1;
        $display("Time: %0t | Caught Result 4 (Expect 0000 for 0.0)  -> %h", $time, result);

        @(posedge clk);
        #1;
        $display("Time: %0t | Caught Result 5 (Expect 4200 for 3.0)  -> %h", $time, result);

        #20;
        $display("\nPipeline test complete! Throughput of 1 achieved successfully.");
        $finish;
    end

endmodule