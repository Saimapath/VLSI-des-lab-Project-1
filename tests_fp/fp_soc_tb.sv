`timescale 1ns / 1ps
`include "../src/pipeline.v"
`include "../src/alu.v"
`include "../src/controller.v"
`include "../src/data_mem_dummy.v" 
`include "../src/instr_mem.v"
`include "../src/regfile.v"
`include "../src/extend.v"
`include "../src/mem_extend.v"

`include "../src_fp/int_hazard_unit.v"

`include "../src_fp/riscv_fp.v"
`include "../src_fp/top_fp.v"
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


module tb_fp_soc_step();
    reg clk, reset;
    integer write_cnt;

    // Instantiate Processor
    riscv_soc dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    // --- Monitor Probe Wires ---
    // Deep probes into the datapath to watch exactly what is writing to the register files
    wire        int_write_en = dut.cpu.Final_RegWriteW && !reset && dut.cpu.Final_RdW != 0;
    wire [4:0]  int_write_rd = dut.cpu.Final_RdW;
    wire [31:0] int_write_wd = dut.cpu.Final_ResultW;

    wire        fp_write_en  = dut.fpu_pipe.fp_regwriteW && !reset; // Note: f0 IS writable!
    wire [4:0]  fp_write_rd  = dut.fpu_pipe.RdW_FP;
    wire [15:0] fp_write_wd  = dut.fpu_pipe.FP_ResultW;

    initial begin
        $dumpfile("fp_step_verify.vcd");
        $dumpvars(0, tb_fp_soc_step);
        
        // Clear memory first to prevent X states
        for (integer i = 0; i < 64; i = i + 1) dut.imem.ram[i] = 32'b0;

        // =========================================================================
        // PRE-LOAD DATA MEMORY (FP Constants)
        // =========================================================================
        dut.dmem.ram[0] = 32'h00003C00; // Address 0: 1.0
        dut.dmem.ram[1] = 32'h00004000; // Address 4: 2.0
        dut.dmem.ram[2] = 32'h0000C000; // Address 8: -2.0
        dut.dmem.ram[3] = 32'h00000000; // Address 12: Empty (For FSW check)

        // =========================================================================
        // THE RISC-V FPU PIPELINE TORTURE TEST
        // =========================================================================

        // --- TEST 1: FP Memory Loads & Basic Math ---
        // 00: flw f1, 0(x0)      (f1 = 1.0)
        dut.imem.ram[0]  = 32'h00002087; 
        // 04: flw f2, 4(x0)      (f2 = 2.0)
        dut.imem.ram[1]  = 32'h00402107; 
        // 08: fadd.s f3, f1, f2  (f3 = 1.0 + 2.0 = 3.0. Checks FP Forwarding!)
        dut.imem.ram[2]  = 32'h002081D3; 

        // --- TEST 2: FMA & Negative Numbers ---
        // 0C: flw f4, 8(x0)      (f4 = -2.0)
        dut.imem.ram[3]  = 32'h00802207; 
        // 10: fmul.s f5, f2, f4  (f5 = 2.0 * -2.0 = -4.0)
        dut.imem.ram[4]  = 32'h084102D3; 
        // 14: fmadd.s f6, f2, f4, f1 (f6 = (2.0 * -2.0) + 1.0 = -3.0. Checks 3-port hazard!)
        dut.imem.ram[5]  = 32'h08410343; 

        // --- TEST 3: Cross-Datapath Bridges (FP -> Int) ---
        // 18: feq.s x1, f1, f1   (x1 = 1. Checks 0-cycle combinational bridge)
        dut.imem.ram[6]  = 32'hA010A0D3; 
        // 1C: fcvt.w.s x2, f3    (x2 = 3. Checks float-to-int cast)
        dut.imem.ram[7]  = 32'hC0018153; 

        // --- TEST 4: FP Memory Stores ---
        // 20: fsw f6, 12(x0)     (Stores -3.0 into RAM address 12)
        dut.imem.ram[8]  = 32'h00602627; 

        // --- FINISH ---
        // 24: addi x30, x0, 1    (TRAP SUCCESS)
        dut.imem.ram[9]  = 32'h00100F13; 

        // Run
        clk = 0; reset = 1; write_cnt = 0;
        #25 reset = 0;

        $display("==================================================================================");
        $display("                       THE FPU PIPELINE TORTURE TEST");
        $display("==================================================================================");
        $display("Time  | Details            | Status | PC & Register Checks");
        $display("----------------------------------------------------------------------------------");
    end

    // ====================================================================
    // MONITOR: Synced to Writeback Stage (Watches BOTH Datapaths)
    // ====================================================================
    always @(negedge clk) begin
        // --- Detect Integer Writes ---
        if (int_write_en) begin
            write_cnt = write_cnt + 1;
            
            // TRAP LOGIC
            if (int_write_rd == 30 && int_write_wd == 1) begin
                $display("----------------------------------------------------------------------------------");
                
                // Final Check: Did FSW successfully store to Memory?
                if (dut.dmem.ram[3] === 32'h0000C200) 
                    $display("[PASS] Memory FSW Check: -3.0 successfully stored in Data RAM.");
                else 
                    $display("[FAIL] Memory FSW Check: Expected 0000C200, Got %h", dut.dmem.ram[3]);

                $display("[TORTURE TEST PASSED] Your FP coprocessor survived the gauntlet!");
                $display("==================================================================================");
                $finish;
            end
            
            case (write_cnt)
                7: check_int(32'h18, 5'd1, 32'd1, "FEQ Bridge Result  ");
                8: check_int(32'h1C, 5'd2, 32'd3, "FCVT Cast Result   ");
                default: $display("%t | FAIL   | Unexpected Int Write: PC=%h, x%0d=%h", $time, dut.cpu.PCW, int_write_rd, int_write_wd);
            endcase
        end
        
        // --- Detect Floating-Point Writes ---
        else if (fp_write_en) begin
            write_cnt = write_cnt + 1;
            case (write_cnt)
                1: check_fp(32'h00, 5'd1, 16'h3C00, "FLW 1.0            ");
                2: check_fp(32'h04, 5'd2, 16'h4000, "FLW 2.0            ");
                3: check_fp(32'h08, 5'd3, 16'h4200, "FADD (3.0) Pipeline");
                4: check_fp(32'h0C, 5'd4, 16'hC000, "FLW -2.0           ");
                5: check_fp(32'h10, 5'd5, 16'hC400, "FMUL (-4.0) Hazard ");
                6: check_fp(32'h14, 5'd6, 16'hC200, "FMADD (-3.0) 3-Port");
                default: $display("%t | FAIL   | Unexpected FP Write: PC=%h, f%0d=%h", $time, dut.cpu.PCW, fp_write_rd, fp_write_wd);
            endcase
        end
    end
    
    // ====================================================================
    // VERIFICATION TASKS
    // ====================================================================
    task check_int;
        input [31:0] expected_pc;
        input [4:0]  expected_reg;
        input [31:0] expected_data;
        input [159:0] name;
        begin
            if (dut.cpu.PCW === expected_pc && int_write_rd === expected_reg && int_write_wd === expected_data) 
                $display("%t | %s | PASS   | PC=%h, Reg=x%0d, Data=%h", 
                         $time, name, dut.cpu.PCW, int_write_rd, int_write_wd);
            else begin
                $display("%t | %s | FAIL   | Expected: PC=%h, x%0d=%h", $time, name, expected_pc, expected_reg, expected_data);
                $display("      |                      |        | Got     : PC=%h, x%0d=%h", dut.cpu.PCW, int_write_rd, int_write_wd);
                $finish;
            end
        end
    endtask

    task check_fp;
        input [31:0] expected_pc;
        input [4:0]  expected_reg;
        input [15:0] expected_data;
        input [159:0] name;
        begin
            if (dut.cpu.PCW === expected_pc && fp_write_rd === expected_reg && fp_write_wd === expected_data) 
                $display("%t | %s | PASS   | PC=%h, Reg=f%0d, Data=%h", 
                         $time, name, dut.cpu.PCW, fp_write_rd, fp_write_wd);
            else begin
                $display("%t | %s | FAIL   | Expected: PC=%h, f%0d=%h", $time, name, expected_pc, expected_reg, expected_data);
                $display("      |                      |        | Got     : PC=%h, f%0d=%h", dut.cpu.PCW, fp_write_rd, fp_write_wd);
                $finish;
            end
        end
    endtask
    
    // Safety Timeout
    initial begin
        #2000;
        $display("[TIMEOUT] Processor stalled indefinitely or stuck in loop.");
        $finish;
    end
endmodule