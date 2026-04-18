`timescale 1ns / 1ps
`include "../src/pipeline.v"
`include "../src/alu.v"
// `include "../src/controller.v"
// `include "../src/data_mem_dummy.v" 
`include "../src/instr_mem.v"
`include "../src/extend.v"
`include "../src/mem_extend.v"



// `include "../src_fp/riscv_fp.v"
// `include "../src_fp/top_fp.v"
`include "../src_fp/fp_datapath.v"      // Include new FP files
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
// `include "../src_systolic_array/dma_riscv_controller.v"
// `include "../src_systolic_array/top_fp_dma.v"
`include "../src_systolic_array/shared_data_bram.v"
`include "../src_systolic_array/dma.v"
// `include "../src_systolic_array/riscv_fp_dma.v"
`include "../src_systolic_array/systolic_array.v"

`include "../src_gpio/gpio_int.v"
`include "../src_gpio/peripheral_decoder.v"
`include "../src_gpio/spi_int_v1.v"

`include "../src_mul_csr_dma_fp/controller.v"
`include "../src_mul_csr_dma_fp/hazard_unit.v"
`include "../src_mul_csr_dma_fp/regfile.v"
`include "../src_mul_csr_dma_fp/csr_hazard.v"
`include "../src_mul_csr_dma_fp/csr_ops.v"
`include "../src_mul_csr_dma_fp/csr_regfile.v"

`include "../src_mul_csr_dma_fp/full_adder.v"
`include "../src_mul_csr_dma_fp/half_adder.v"
`include "../src_mul_csr_dma_fp/multiplier_16x16.v"
`include "../src_mul_csr_dma_fp/multiplier_block.v"
`include "../src_mul_csr_dma_fp/pp_calculator_unsigned.v"
`include "../src_mul_csr_dma_fp/pp_calculator.v"
`include "../src_mul_csr_dma_fp/pp_lastbit.v"

`include "../src_mul_csr_dma_fp/riscv_mult_csr_dma_fp.v"
`include "../src_mul_csr_dma_fp/top.v"
// Include all your FP, DMA, and CSR/Mult files here just like your Omni-Test

 
module tb_custom_mult_csr();
    reg clk, reset;
    
    integer total_cycles, stalls;

    // Instantiate Top-Level SoC (Direct RTL)
    riscv_soc dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    // Instruction Retirement Monitor
    wire inst_retiring = dut.cpu.validW && !dut.cpu.StallW;

    initial begin
        $dumpfile("custom_mult_csr.vcd");
        $dumpvars(0, tb_custom_mult_csr);
        
        // Clear memory
        for (integer i = 0; i < 64; i = i + 1) dut.imem.ram[i] = 32'b0;

        // =========================================================================
        // LOAD TARGETED MULT & CSR PROGRAM
        // =========================================================================
        dut.imem.ram[0] = 32'hFFF00093; // 00: addi x1, x0, -1   (x1 = 0xFFFFFFFF)
        dut.imem.ram[1] = 32'h00200113; // 04: addi x2, x0, 2    (x2 = 0x00000002)
        dut.imem.ram[2] = 32'h022081B3; // 08: mul x3, x1, x2    (x3 = 0xFFFFFFFE)
        dut.imem.ram[3] = 32'h02209233; // 0C: mulh x4, x1, x2   (x4 = 0xFFFFFFFF)
        dut.imem.ram[4] = 32'h0220A2B3; // 10: mulhsu x5, x1, x2 (x5 = 0xFFFFFFFF)
        dut.imem.ram[5] = 32'h0220B333; // 14: mulhu x6, x1, x2  (x6 = 0x00000001)
        dut.imem.ram[6] = 32'h30019073; // 18: csrrw x0, mstatus, x3 (mstatus = 0xFFFFFFFE)
        dut.imem.ram[7] = 32'h300023F3; // 1C: csrrs x7, mstatus, x0 (x7 = 0xFFFFFFFE)
        dut.imem.ram[8] = 32'h30013473; // 20: csrrc x8, mstatus, x2 (Clear bit 1)
        dut.imem.ram[9] = 32'h300024F3; // 24: csrrs x9, mstatus, x0 (x9 = 0xFFFFFFFC)
        dut.imem.ram[10]= 32'h00000013; // 28: nop
        dut.imem.ram[11]= 32'h00000013; // 2C: nop

        // Initialize (Active-Low Reset)
        clk = 0; 
        reset = 0; 
        total_cycles = 0; 
        stalls = 0; 

        #25 reset = 1; // Release Reset

        $display("==================================================================================");
        $display("  TARGETED MULTIPLIER & CSR HARDWARE TEST");
        $display("==================================================================================");
    end

    // Cycle & Stall Counter
    always @(negedge clk) begin
        if (reset) begin
            total_cycles = total_cycles + 1;
            if (dut.cpu.combined_sys_stall) stalls = stalls + 1;
        end
    end

    // Self-Checking Monitor
    always @(negedge clk) begin
        if (inst_retiring) begin
            case (dut.cpu.PCW)
                32'h08: begin
                    if (dut.cpu.Final_ResultW === 32'hFFFFFFFE) 
                        $display("%0t | [PASS] MUL    | Lower 32 bits = 0xFFFFFFFE (-2)", $time);
                    else 
                        $display("%0t | [FAIL] MUL    | Expected 0xFFFFFFFE, Got 0x%h", $time, dut.cpu.Final_ResultW);
                end
                
                32'h0C: begin
                    if (dut.cpu.Final_ResultW === 32'hFFFFFFFF) 
                        $display("%0t | [PASS] MULH   | Upper 32 Signed = 0xFFFFFFFF", $time);
                    else 
                        $display("%0t | [FAIL] MULH   | Expected 0xFFFFFFFF, Got 0x%h", $time, dut.cpu.Final_ResultW);
                end
                
                32'h10: begin
                    if (dut.cpu.Final_ResultW === 32'hFFFFFFFF) 
                        $display("%0t | [PASS] MULHSU | Upper 32 Signed/Unsigned = 0xFFFFFFFF", $time);
                    else 
                        $display("%0t | [FAIL] MULHSU | Expected 0xFFFFFFFF, Got 0x%h", $time, dut.cpu.Final_ResultW);
                end
                
                32'h14: begin
                    if (dut.cpu.Final_ResultW === 32'h00000001) 
                        $display("%0t | [PASS] MULHU  | Upper 32 Unsigned = 0x00000001", $time);
                    else 
                        $display("%0t | [FAIL] MULHU  | Expected 0x00000001, Got 0x%h", $time, dut.cpu.Final_ResultW);
                end
                
                32'h1C: begin
                    if (dut.cpu.Final_ResultW === 32'hFFFFFFFE) 
                        $display("%0t | [PASS] CSRRW  | Successfully wrote & read MUL result from mstatus", $time);
                    else 
                        $display("%0t | [FAIL] CSRRW  | Expected 0xFFFFFFFE, Got 0x%h", $time, dut.cpu.Final_ResultW);
                end
                
                32'h24: begin
                    if (dut.cpu.Final_ResultW === 32'hFFFFFFFC) begin
                        $display("%0t | [PASS] CSRRC  | Successfully cleared bits in mstatus (0xFFFFFFFC)", $time);
                        $display("==================================================================================");
                        $display("[FINAL SUCCESS] Your Custom Multiplier and CSR Ops modules passed perfectly!");
                        $display("  Total Execution Cycles: %0d", total_cycles);
                        $display("==================================================================================");
                        $finish;
                    end
                    else begin
                        $display("%0t | [FAIL] CSRRC  | Bit Clear Failed! Expected 0xFFFFFFFC, Got 0x%h", $time, dut.cpu.Final_ResultW);
                    end
                end
            endcase
        end
    end

    // Safety Timeout
    initial begin
        #5000;
        $display("[%0t] [TIMEOUT] Processor stalled indefinitely.", $time);
        $finish;
    end
endmodule