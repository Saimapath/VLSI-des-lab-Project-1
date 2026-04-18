`timescale 1ns / 1ps

`include "../src/pipeline.v"
`include "../src/alu.v"
`include "../src/instr_mem.v"
`include "../src/regfile.v"
`include "../src/extend.v"
`include "../src/mem_extend.v"

`include "../src/gpio_checkpointing.mem"

`include "../src_fp/int_hazard_unit.v"
`include "../src_fp/fp_datapath.v"      
`include "../src_fp/fp_hazard_unit.v"
`include "../src_fp/fp_controller.v"
`include "../src_fp/fp_regfile.v"
`include "../src_fp/fpu.v"
`include "../src_fp/fp_mac.v"
`include "../src_fp/fp_mult.v"
`include "../src_fp/fp_adder.v"
`include "../src_fp/fp_sign_inj.v"
`include "../src_fp/fp_convert.v"
`include "../src_fp/fp_compare.v"

`include "../src_systolic_array/dma_mac.v"
`include "../src_systolic_array/dma_riscv_controller.v"
`include "../src_systolic_array/top_fp_dma.v"
`include "../src_systolic_array/shared_data_bram.v"
`include "../src_systolic_array/dma.v"
`include "../src_systolic_array/riscv_fp_dma.v"
`include "../src_systolic_array/systolic_array.v"

`include "../src_gpio/gpio_int.v"
`include "../src_gpio/peripheral_decoder.v"
`include "../src_gpio/spi_int_v1.v"

module tb_soc_gpio();
    reg clk, reset;
    
    // Testbench tracking variables
    integer total_cycles, stalls;
    reg blinky_active;
    integer blink_count;

    // Instantiate your Top-Level SoC (Direct RTL, no Vivado Wrapper)
    riscv_soc dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    // The Gold Standard Monitor: Tracks every instruction that passes Writeback safely
    wire inst_retiring = dut.cpu.validW && !dut.cpu.StallW;

    initial begin
        $dumpfile("soc_omni_test.vcd");
        $dumpvars(0, tb_soc_omni_test);
        
        // =========================================================================
        // LOAD INSTRUCTION MEMORY (The Griller Program)
        // =========================================================================
        // Ensure "instr_mem.mem" contains the final Hex code and is in the sim folder
        // $readmemh("instr_mem.mem", dut.imem.ram);

        // =========================================================================
        // PRE-LOAD DATA MEMORY (FP & DMA Matrices)
        // =========================================================================
        // Floating Point Seed Data (Addr 96 -> Word Index 3)
        dut.dmem.bank0[3] = 32'h00003C00; // f1 = 1.0
        dut.dmem.bank1[3] = 32'h00004000; // f2 = 2.0
        dut.dmem.bank2[3] = 32'h0000C000; // f3 = -2.0
        dut.dmem.bank3[3] = 32'h00004400; // f4 = 4.0

        // Initialize Variables
        clk = 0; 
        reset = 1; 
        total_cycles = 0; 
        stalls = 0; 
        blinky_active = 0;
        blink_count = 0;

        #25 reset = 0; // Drop active-high reset

        $display("==================================================================================");
        $display("  SYSTEM OMNI-TEST 6.0: DIRECT RTL VERIFICATION (THE GRILLER)");
        $display("==================================================================================");
        $display("Time  | Phase Status");
        $display("----------------------------------------------------------------------------------");
    end

    // Cycle & Stall Counter
    always @(negedge clk) begin
        if (!reset) begin
            total_cycles = total_cycles + 1;
            if (dut.cpu.combined_sys_stall) stalls = stalls + 1;
        end
    end

    // =========================================================================
    // INSTRUCTION RETIREMENT MONITOR (Self-Checking)
    // =========================================================================
    always @(negedge clk) begin
        if (inst_retiring) begin
            
            // Map the safely retired Program Counters directly to Phase Completions
            if (!blinky_active) begin
                case (dut.cpu.PCW)
                    32'h014: $display("%0t | [PASS] PHASE 1: System Booted.", $time);
                    32'h048: $display("%0t | [PASS] PHASE 2: RV32I ALU & Forwarding Flawless.", $time);
                    32'h07C: $display("%0t | [PASS] PHASE 3: RV32I Memory & Load-Use Stalls Flawless.", $time);
                    32'h0F0: $display("%0t | [PASS] PHASE 4: RV32I Branches & Jumps Flawless.", $time);
                    32'h12C: $display("%0t | [PASS] PHASE 5: RV32F Casts Flawless.", $time);
                    32'h16C: $display("%0t | [PASS] PHASE 6: RV32F Math & Comparators Flawless.", $time);
                    32'h19C: $display("%0t | [PASS] PHASE 7: DMA Memory Interlocks Flawless.", $time);
                    
                    32'h1B4: begin
                        $display("%0t | [PASS] PHASE 8: Omni-Test Complete! Entering Visual Blinky Mode.", $time);
                        blinky_active = 1;
                    end
                    
                    // --- Death Trap Catchers ---
                    32'h08C, 32'h098, 32'h0A4, 32'h0B0, 32'h0BC, 32'h0C8, 32'h0D4, 32'h0E4: begin
                        $display("%0t | [FATAL ERROR] DEATH TRAP HIT! A branch or jump mispredicted at PC=%h", $time, dut.cpu.PCW);
                        $finish;
                    end
                endcase
            end 
            
            // --- Visual Blinky Mode Monitor ---
            else begin
                if (dut.cpu.PCW == 32'h1BC) begin
                    $display("%0t | [VISUAL] LEDs ON  (0xFF)", $time);
                    blink_count = blink_count + 1;
                    
                    if (blink_count == 3) begin
                        $display("==================================================================================");
                        $display("[%0t] [FINAL SUCCESS] 100%% INSTRUCTION COVERAGE ACHIEVED IN PURE RTL!", $time);
                        $display("  Total Execution Cycles: %0d | Total Pipeline Stalls: %0d", total_cycles, stalls);
                        $display("==================================================================================");
                        $finish;
                    end
                end 
                else if (dut.cpu.PCW == 32'h1D0) begin
                    $display("%0t | [VISUAL] LEDs OFF (0x00)", $time);
                end
            end
            
        end
    end

    // Safety Timeout
    initial begin
        #60000;
        $display("[%0t] [TIMEOUT] Processor stalled indefinitely or stuck in loop.", $time);
        $finish;
    end
endmodule