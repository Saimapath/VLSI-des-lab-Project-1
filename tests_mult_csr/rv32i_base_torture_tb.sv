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

module tb_step_by_step();
    reg clk, reset;
    integer write_cnt;

    // Instantiate Processor
    riscv_soc dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    initial begin
        $dumpfile("step_verify.vcd");
        $dumpvars(0, tb_step_by_step);
        
        // Clear memory first to prevent X states
        for (integer i = 0; i < 64; i = i + 1) dut.imem.ram[i] = 32'b0;

        // =========================================================================
        // THE RISC-V PIPELINE TORTURE TEST
        // =========================================================================

        // --- TEST 1: Forwarding Cascades & x0 Hardwiring ---
        // 00: addi x1, x0, 10
        dut.imem.ram[0]  = 32'h00A00093; 
        // 04: addi x0, x1, 20 (ATTEMPT TO CORRUPT x0 - Should be ignored by RegFile)
        dut.imem.ram[1]  = 32'h01408013; 
        // 08: add x2, x1, x0 (If x0 was corrupted, x2 will be 30. If safe, x2 = 10)
        dut.imem.ram[2]  = 32'h00008133; 
        // 0C: add x3, x2, x1 (x3 = 10 + 10 = 20. Forwarding: x2 from MEM, x1 from WB)
        dut.imem.ram[3]  = 32'h001101B3; 

        // --- TEST 2: Load-Use Hazard Stall Check ---
        // 10: sw x3, 0(x0) (Store 20 at address 0)
        dut.imem.ram[4]  = 32'h00302023; 
        // 14: lw x4, 0(x0) (Load 20 back into x4)
        dut.imem.ram[5]  = 32'h00002203; 
        // 18: add x5, x4, x1 (HAZARD! Stall required. x5 = 20 + 10 = 30)
        dut.imem.ram[6]  = 32'h001202B3; 

        // --- TEST 3: Signed vs Unsigned Branch Comparisons ---
        // 1C: addi x6, x0, -5 (x6 = 0xFFFFFFFB)
        dut.imem.ram[7]  = 32'hFFB00313; 
        // 20: addi x7, x0, 5  (x7 = 0x00000005)
        dut.imem.ram[8]  = 32'h00500393; 
        // 24: blt x6, x7, +8 (SIGNED: -5 < 5. Branch MUST be taken -> Jump to 2C)
        dut.imem.ram[9]  = 32'h00734463; 
        // 28: addi x30, x0, 99 (TRAP - Failed Signed BLT)
        dut.imem.ram[10] = 32'h06300F13; 
        
        // 2C: bltu x6, x7, +8 (UNSIGNED: 0xFFFFFFFB > 5. Branch MUST NOT be taken)
        dut.imem.ram[11] = 32'h00736463; 
        // 30: jal x0, +8 (Jump over the trap)
        dut.imem.ram[12] = 32'h0080006F; 
        // 34: addi x30, x0, 99 (TRAP - Failed Unsigned BLTU)
        dut.imem.ram[13] = 32'h06300F13; 

        // --- TEST 4: AUIPC and JALR Dynamic Linking ---
        // 38: auipc x8, 0 (x8 = PC = 0x38)
        dut.imem.ram[14] = 32'h00000417; 
        // 3C: addi x8, x8, 16 (x8 = 0x38 + 16 = 0x48)
        dut.imem.ram[15] = 32'h01040413; 
        // 40: jalr x9, x8, 0 (Jump to 0x48. Link PC+4 [0x44] into x9)
        dut.imem.ram[16] = 32'h000404E7; 
        // 44: addi x30, x0, 99 (TRAP - Failed JALR)
        dut.imem.ram[17] = 32'h06300F13; 

        // --- TEST 5: Arithmetic & Logical Shift Edge Cases ---
        // 48: addi x10, x0, 1
        dut.imem.ram[18] = 32'h00100513; 
        // 4C: slli x10, x10, 31 (x10 = 0x80000000)
        dut.imem.ram[19] = 32'h01F51513; 
        // 50: srai x11, x10, 31 (Arithmetic Right: Sign extend. x11 = 0xFFFFFFFF)
        dut.imem.ram[20] = 32'h41F55593; 
        // 54: srli x12, x11, 1 (Logical Right: Zero fill. x12 = 0x7FFFFFFF)
        dut.imem.ram[21] = 32'h0015D613; 
        // 58: xor x13, x12, x10 (x13 = 0x7FFFFFFF ^ 0x80000000 = 0xFFFFFFFF)
        dut.imem.ram[22] = 32'h00A646B3; 

        // --- TEST 6: Upper Immediate & Finish ---
        // 5C: lui x14, 0x12345 (x14 = 0x12345000)
        dut.imem.ram[23] = 32'h12345737; 
        // 60: addi x30, x0, 1 (SUCCESS TRAP)
        dut.imem.ram[24] = 32'h00100F13; 

        // Run
        clk = 0; reset = 0; write_cnt = 0;
        #25 reset = 1;

        $display("==================================================================================");
        $display("                       THE PIPELINE TORTURE TEST");
        $display("==================================================================================");
        $display("Time  | Details            | Status | PC & Register Checks");
        $display("----------------------------------------------------------------------------------");
    end

    // ====================================================================
    // MONITOR: Synced to Writeback Stage
    // ====================================================================
    always @(negedge clk) begin
        if (dut.cpu.RegWriteW && reset && dut.cpu.rf.a3 != 0) begin
            write_cnt = write_cnt + 1;
            
            // TRAP LOGIC
            if (dut.cpu.rf.a3 == 30) begin
                if (dut.cpu.rf.wd3 == 1) begin
                    $display("----------------------------------------------------------------------------------");
                    $display("[TORTURE TEST PASSED] Your processor survived the gauntlet!");
                    $display("==================================================================================");
                    $finish;
                end else begin
                    $display("%t | Trap Hit!        | FAIL   | Fatal logic error at PC=%h", $time, dut.cpu.PCW);
                    $finish;
                end
            end
            
            case (write_cnt)
                1:  check(32'h00, 5'd1,  32'd10,       "Init x1");
                2:  check(32'h08, 5'd2,  32'd10,       "x0 Hardwire Check");
                3:  check(32'h0C, 5'd3,  32'd20,       "Double Forwarding");
                4:  check(32'h14, 5'd4,  32'd20,       "Load Word");
                5:  check(32'h18, 5'd5,  32'd30,       "Load-Use Stall");
                6:  check(32'h1C, 5'd6,  -32'd5,       "Init x6 (Negative)");
                7:  check(32'h20, 5'd7,  32'd5,        "Init x7 (Positive)");
                8:  check(32'h38, 5'd8,  32'h38,       "AUIPC PC Check");
                9:  check(32'h3C, 5'd8,  32'h48,       "PC Offset Math");
                10: check(32'h40, 5'd9,  32'h44,       "JALR Link PC+4");
                11: check(32'h48, 5'd10, 32'd1,        "Init x10");
                12: check(32'h4C, 5'd10, 32'h80000000, "Shift Left Log.");
                13: check(32'h50, 5'd11, 32'hFFFFFFFF, "Shift Right Arith.");
                14: check(32'h54, 5'd12, 32'h7FFFFFFF, "Shift Right Log.");
                15: check(32'h58, 5'd13, 32'hFFFFFFFF, "XOR Check");
                16: check(32'h5C, 5'd14, 32'h12345000, "LUI Check");

                default: $display("Extra Write to x%0d = %h at PC %h", dut.cpu.rf.a3, dut.cpu.rf.wd3, dut.cpu.PCW);
            endcase
        end
    end
    
    // ====================================================================
    // VERIFICATION TASK
    // ====================================================================
    task check;
        input [31:0] expected_pc;
        input [4:0]  expected_reg;
        input [31:0] expected_data;
        input [127:0] name;
        begin
            if (dut.cpu.PCW === expected_pc && dut.cpu.rf.a3 === expected_reg && dut.cpu.rf.wd3 === expected_data) 
                $display("%t | %s | PASS   | PC=%h, Reg=x%0d, Data=%h", 
                         $time, name, dut.cpu.PCW, dut.cpu.rf.a3, dut.cpu.rf.wd3);
            else 
                $display("%t | %s \t | FAIL \t  | Expected: PC=%h, Reg=x%0d, Data=%h\n |\t \t                              Got     : PC=%h, Reg=x%0d, Data=%h", 
                         $time, name, expected_pc, expected_reg, expected_data, dut.cpu.PCW, dut.cpu.rf.a3, dut.cpu.rf.wd3);
        end
    endtask
    
    // Safety Timeout
    initial begin
        #2000;
        $display("[TIMEOUT] Processor stalled indefinitely or stuck in loop.");
        $finish;
    end
endmodule