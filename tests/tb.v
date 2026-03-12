`timescale 1ns / 1ps

module riscv_tb();
    reg clk;
    reg reset;

    // Instantiate System
    riscv_soc dut (
        .clk(clk),
        .reset(reset)
    );

    // Generate Clock (100MHz)
    always #5 clk = ~clk;

    initial begin
        // Initialize signals
        clk = 0;
        reset = 1;
        
        // Reset sequence
        #20;
        reset = 0;

        // Monitoring execution
        $display("Starting RISC-V Simulation...");
        
        // Timeout for safety
        #5000;
        $display("Simulation timeout reached.");
        $finish;
    end

    // Monitor Memory Writes for "End of Program" indicator
    always @(posedge clk) begin
        if (dut.MemWriteM == 4'b1111 && dut.ALUResultM == 32'h0000_1000) begin
            $display("Program finished successfully! Result: %h", dut.WriteDataM);
            $finish;
        end
    end

    // Waveform dump for GTKWave or Vivado
    initial begin
        $dumpfile("z.vcd");
        $dumpvars(0, riscv_tb);
    end

endmodule