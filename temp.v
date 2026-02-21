`timescale 1ns / 1ps

module tb_riscv();
    reg clk;
    reg reset;

    riscv_top dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    initial begin
        // 1. Setup VCD with depth
        $dumpfile("riscv_full_debug.vcd");
        // $dumpvars(0, tb_riscv) dumps EVERYTHING in tb_riscv and below
        // including arrays like the regfile and memory
        $dumpvars(0, tb_riscv); 

        clk = 0;
        reset = 1;
        #22 reset = 0; // Reset released slightly after clock edge

        #2000; // Run long enough to see multiple instructions
        $finish;
    end
endmodule