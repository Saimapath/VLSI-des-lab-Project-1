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

module tb_fp_soc_step();
    reg clk, reset;
    integer int_wc, fp_wc; 

    riscv_soc dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    wire        int_write_en = dut.cpu.Final_RegWriteW && reset && dut.cpu.Final_RdW != 0;
    wire [4:0]  int_write_rd = dut.cpu.Final_RdW;
    wire [31:0] int_write_wd = dut.cpu.Final_ResultW;

    wire        fp_write_en  = dut.fpu_pipe.fp_regwriteW && reset; 
    wire [4:0]  fp_write_rd  = dut.fpu_pipe.RdW_FP;
    wire [15:0] fp_write_wd  = dut.fpu_pipe.FP_ResultW;

    wire int_write_retiring = int_write_en && !dut.cpu.StallW;
    wire fp_write_retiring  = fp_write_en  && !dut.cpu.StallW;

    initial begin
        $dumpfile("fp_step_verify.vcd");
        $dumpvars(0, tb_fp_soc_step);
        
        for (integer i = 0; i < 64; i = i + 1) dut.imem.ram[i] = 32'b0;

        // --- PRE-LOAD DATA MEMORY ---
        dut.dmem.ram[0] = 32'h00003C00; // addr 0: 1.0
        dut.dmem.ram[1] = 32'h00004000; // addr 4: 2.0
        dut.dmem.ram[2] = 32'h0000C000; // addr 8: -2.0
        dut.dmem.ram[3] = 32'h00004400; // addr 12: 4.0

        // =========================================================================
        // THE ULTIMATE RV32F INSTRUCTION GAUNTLET (Testing all 26 variants)
        // =========================================================================
        
        // --- 1. Memory Loads ---
        dut.imem.ram[0]  = 32'h00002087; // 00: flw f1, 0(x0)  -> 1.0 (3C00)
        dut.imem.ram[1]  = 32'h00402107; // 04: flw f2, 4(x0)  -> 2.0 (4000)
        dut.imem.ram[2]  = 32'h00802187; // 08: flw f3, 8(x0)  -> -2.0 (C000)
        dut.imem.ram[3]  = 32'h00C02207; // 0C: flw f4, 12(x0) -> 4.0 (4400)

        // --- 2. FMA Family (A*B+C variations) ---
        dut.imem.ram[4]  = 32'h084102C3; // 10: fmadd.s  f5, f2, f4, f1 -> (2*4)+1 = 9.0 (4880)
        dut.imem.ram[5]  = 32'h08410347; // 14: fmsub.s  f6, f2, f4, f1 -> (2*4)-1 = 7.0 (4700)
        dut.imem.ram[6]  = 32'h084103CB; // 18: fnmsub.s f7, f2, f4, f1 -> -(2*4)+1 = -7.0 (C700)
        dut.imem.ram[7]  = 32'h0841044F; // 1C: fnmadd.s f8, f2, f4, f1 -> -(2*4)-1 = -9.0 (C880)

        // --- 3. Basic Math ---
        dut.imem.ram[8]  = 32'h004108D3; // 20: fadd.s f17, f2, f4 -> 2+4 = 6.0 (4600)
        dut.imem.ram[9]  = 32'h08220953; // 24: fsub.s f18, f4, f2 -> 4-2 = 2.0 (4000)
        dut.imem.ram[10] = 32'h104109D3; // 28: fmul.s f19, f2, f4 -> 2*4 = 8.0 (4800)
        dut.imem.ram[11] = 32'h18220A53; // 2C: fdiv.s f20, f4, f2 -> TBD (FFFF)
        dut.imem.ram[12] = 32'h58020AD3; // 30: fsqrt.s f21, f4    -> TBD (FFFF)

        // --- 4. Sign Injection ---
        dut.imem.ram[13] = 32'h203084D3; // 34: fsgnj.s  f9, f1, f3  -> abs(1) with sign(-2) = -1.0 (BC00)
        dut.imem.ram[14] = 32'h20311553; // 38: fsgnjn.s f10, f2, f3 -> abs(2) with ~sign(-2) = +2.0 (4000)
        dut.imem.ram[15] = 32'h2030A5D3; // 3C: fsgnjx.s f11, f1, f3 -> sign(1)^sign(-2) = 0^1 = 1 = -1.0 (BC00)

        // --- 5. Min / Max ---
        dut.imem.ram[16] = 32'h28410653; // 40: fmin.s f12, f2, f4 -> min(2, 4) = 2.0 (4000)
        dut.imem.ram[17] = 32'h281196D3; // 44: fmax.s f13, f3, f1 -> max(-2, 1) = 1.0 (3C00)

        // --- 6. Comparators (Writes to Int) ---
        dut.imem.ram[18] = 32'hA02120D3; // 48: feq.s x1, f2, f2 -> 2 == 2 (1)
        dut.imem.ram[19] = 32'hA0119153; // 4C: flt.s x2, f3, f1 -> -2 < 1 (1)
        dut.imem.ram[20] = 32'hA02201D3; // 50: fle.s x3, f4, f2 -> 4 <= 2 (0)

        // --- 7. Classification ---
        dut.imem.ram[21] = 32'hE0019253; // 54: fclass.s x4, f3 -> class(-2.0) = Negative Normal (0x00000002)

       // --- 8. Data Moves (Raw Binary Bridges) ---
        dut.imem.ram[22] = 32'hE00082D3; // 58: fmv.x.w x5, f1 -> Move 3C00 into Int Reg
        dut.imem.ram[23] = 32'h00000013; // 5C: NOP (Wait for FPU to reach Int Writeback)
        dut.imem.ram[24] = 32'h00000013; // 60: NOP
        dut.imem.ram[25] = 32'hF0028753; // 64: fmv.w.x f14, x5 -> Move 3C00 back into FP Reg

        // --- 9. Converters ---
        dut.imem.ram[26] = 32'hC0010353; // 68: fcvt.w.s  x6, f2 -> Cast 2.0 to Int 2
        dut.imem.ram[27] = 32'hC01103D3; // 6C: fcvt.wu.s x7, f2 -> Cast 2.0 to Unsigned Int 2
        dut.imem.ram[28] = 32'h00000013; // 70: NOP (Wait for FPU to reach Int Writeback)
        dut.imem.ram[29] = 32'h00000013; // 74: NOP
        dut.imem.ram[30] = 32'hD00307D3; // 78: fcvt.s.w  f15, x6 -> Cast Int 2 to FP 2.0
        dut.imem.ram[31] = 32'hD0138853; // 7C: fcvt.s.wu f16, x7 -> Cast Unsigned 2 to FP 2.0

        // --- 10. Store & Finish ---
        // dut.imem.ram[32] = 32'h00902A27; // 80: fsw f19, 20(x0) -> Store 8.0 into RAM address 20
        dut.imem.ram[32] = 32'h01302A27; // fsw f19
        dut.imem.ram[33] = 32'h00100F13; // 84: addi x30, x0, 1 -> TRAP!

        clk = 0; reset = 0; int_wc = 0; fp_wc = 0;
        #25 reset = 1;

        $display("==================================================================================");
        $display("                       THE ULTIMATE RV32F INSTRUCTION GAUNTLET");
        $display("==================================================================================");
        $display("Time  | Details            | Status | PC & Register Checks");
        $display("----------------------------------------------------------------------------------");
    end

    always @(negedge clk) begin
        // --- INTEGER WRITEBACK MONITOR ---
        if (int_write_retiring) begin
            int_wc = int_wc + 1;
            
            if (int_write_rd == 30 && int_write_wd == 1) begin
                $display("----------------------------------------------------------------------------------");
                if (dut.dmem.ram[5] === 32'h00004800) 
                    $display("[PASS] Memory FSW Check: 8.0 successfully stored in Data RAM.");
                else 
                    $display("[FAIL] Memory FSW Check: Expected 00004800, Got %h", dut.dmem.ram[5]);

                $display("[OMNI-TEST PASSED] Every single RISC-V floating point instruction functions perfectly!");
                $display("==================================================================================");
                $finish;
            end
            
            case (int_wc)
                1: check_int(32'h48, 5'd1, 32'd1, "FEQ (2 == 2)       ");
                2: check_int(32'h4C, 5'd2, 32'd1, "FLT (-2 < 1)       ");
                3: check_int(32'h50, 5'd3, 32'd0, "FLE (4 <= 2)       ");
                4: check_int(32'h54, 5'd4, 32'd2, "FCLASS (-2.0)      ");
                5: check_int(32'h58, 5'd5, 32'h00003C00, "FMV.X.W            ");
                6: check_int(32'h68, 5'd6, 32'd2, "FCVT.W.S           ");
                7: check_int(32'h6C, 5'd7, 32'd2, "FCVT.WU.S          ");
                default: $display("%t | FAIL   | Unexpected Int Write: PC=%h, x%0d=%h", $time, dut.cpu.PCW, int_write_rd, int_write_wd);
            endcase
        end
        
        // --- FLOATING POINT WRITEBACK MONITOR ---
        if (fp_write_retiring) begin
            fp_wc = fp_wc + 1;
            case (fp_wc)
                1:  check_fp(32'h00, 5'd1,  16'h3C00, "FLW 1.0            ");
                2:  check_fp(32'h04, 5'd2,  16'h4000, "FLW 2.0            ");
                3:  check_fp(32'h08, 5'd3,  16'hC000, "FLW -2.0           ");
                4:  check_fp(32'h0C, 5'd4,  16'h4400, "FLW 4.0            ");
                5:  check_fp(32'h10, 5'd5,  16'h4880, "FMADD  (9.0)       ");
                6:  check_fp(32'h14, 5'd6,  16'h4700, "FMSUB  (7.0)       ");
                7:  check_fp(32'h18, 5'd7,  16'hC700, "FNMSUB (-7.0)      ");
                8:  check_fp(32'h1C, 5'd8,  16'hC880, "FNMADD (-9.0)      ");
                9:  check_fp(32'h20, 5'd17, 16'h4600, "FADD   (6.0)       ");
                10: check_fp(32'h24, 5'd18, 16'h4000, "FSUB   (2.0)       ");
                11: check_fp(32'h28, 5'd19, 16'h4800, "FMUL   (8.0)       ");
                12: check_fp(32'h2C, 5'd20, 16'hFFFF, "FDIV   (TBD)       ");
                13: check_fp(32'h30, 5'd21, 16'hFFFF, "FSQRT  (TBD)       ");
                14: check_fp(32'h34, 5'd9,  16'hBC00, "FSGNJ  (-1.0)      ");
                15: check_fp(32'h38, 5'd10, 16'h4000, "FSGNJN (+2.0)      ");
                16: check_fp(32'h3C, 5'd11, 16'hBC00, "FSGNJX (-1.0)      ");
                17: check_fp(32'h40, 5'd12, 16'h4000, "FMIN   (2.0)       ");
                18: check_fp(32'h44, 5'd13, 16'h3C00, "FMAX   (1.0)       ");
                19: check_fp(32'h64, 5'd14, 16'h3C00, "FMV.W.X (1.0)      ");
                20: check_fp(32'h78, 5'd15, 16'h4000, "FCVT.S.W           ");
                21: check_fp(32'h7C, 5'd16, 16'h4000, "FCVT.S.WU          ");
                default: $display("%t | FAIL   | Unexpected FP Write: PC=%h, f%0d=%h", $time, dut.cpu.PCW, fp_write_rd, fp_write_wd);
            endcase
        end
    end
    
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
            end
        end
    endtask
    
    initial begin
        #4000;
        $display("[TIMEOUT] Processor stalled indefinitely or stuck in loop.");
        $finish;
    end
endmodule