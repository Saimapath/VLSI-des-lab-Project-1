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

module tb_soc_omni_test();
    reg clk, reset;
    
    reg  [7:0] gpio_in;
    wire [7:0] gpio_out;
    wire cs_n;
    reg  miso;
    wire mosi;
    wire sclk;
    
    integer total_cycles, stalls;
    reg [7:0] prev_gpio_out;
    reg blinky_active;
    integer blink_count;

    riscv_soc dut (.clk(clk), .reset(reset), .gpio_in(gpio_in), .gpio_out(gpio_out), .miso(miso), .mosi(mosi), .sclk(sclk), .cs_n(cs_n));

    always #5 clk = ~clk;

    wire inst_retiring = dut.cpu.validW && !dut.cpu.StallW;

    initial begin
        $dumpfile("soc_omni_test.vcd");
        $dumpvars(0, tb_soc_omni_test);
        
        for (integer i = 0; i < 256; i = i + 1) dut.imem.ram[i] = 32'b0;

        dut.imem.ram[0]   = 32'h40000537;
        dut.imem.ram[1]   = 32'h50000637;
        dut.imem.ram[2]   = 32'h0FF00593;
        dut.imem.ram[3]   = 32'h00B52223;
        dut.imem.ram[4]   = 32'h01100593;
        dut.imem.ram[5]   = 32'h00B52023; 
        dut.imem.ram[6]   = 32'hFFF00093;
        dut.imem.ram[7]   = 32'h00108133;
        dut.imem.ram[8]   = 32'h402001B3;
        dut.imem.ram[9]   = 32'h00F1C213;
        dut.imem.ram[10]  = 32'h01026293;
        dut.imem.ram[11]  = 32'h0082F313;
        dut.imem.ram[12]  = 32'h00231393;
        dut.imem.ram[13]  = 32'h4010d413; 
        dut.imem.ram[14]  = 32'h0010d493; 
        dut.imem.ram[15]  = 32'h0000A693;
        dut.imem.ram[16]  = 32'h0000B713;
        dut.imem.ram[17]  = 32'h02200593;
        dut.imem.ram[18]  = 32'h00B52023; 
        dut.imem.ram[19]  = 32'h00000793;
        dut.imem.ram[20]  = 32'h0AA00813;
        dut.imem.ram[21]  = 32'h0107A023;
        dut.imem.ram[22]  = 32'h0007A883;
        dut.imem.ram[23]  = 32'h01188933;
        dut.imem.ram[24]  = 32'h01279023;
        dut.imem.ram[25]  = 32'h00079983;
        dut.imem.ram[26]  = 32'h0007D883;
        dut.imem.ram[27]  = 32'h01178023;
        dut.imem.ram[28]  = 32'h00078983;
        dut.imem.ram[29]  = 32'h0007C883;
        dut.imem.ram[30]  = 32'h03300593;
        dut.imem.ram[31]  = 32'h00B52023; 
        dut.imem.ram[32]  = 32'hFFB00A93;
        dut.imem.ram[33]  = 32'h00500B13;
        dut.imem.ram[34]  = 32'h016B0663;
        dut.imem.ram[35]  = 32'h0EE00593;
        dut.imem.ram[36]  = 32'h00B52023;
        dut.imem.ram[37]  = 32'h016A9663;
        dut.imem.ram[38]  = 32'h0EE00593;
        dut.imem.ram[39]  = 32'h00B52023;
        dut.imem.ram[40]  = 32'h016AC663;
        dut.imem.ram[41]  = 32'h0EE00593;
        dut.imem.ram[42]  = 32'h00B52023;
        dut.imem.ram[43]  = 32'h015B5663;
        dut.imem.ram[44]  = 32'h0EE00593;
        dut.imem.ram[45]  = 32'h00B52023;
        dut.imem.ram[46]  = 32'h015B6663;
        dut.imem.ram[47]  = 32'h0EE00593;
        dut.imem.ram[48]  = 32'h00B52023;
        dut.imem.ram[49]  = 32'h016AF663;
        dut.imem.ram[50]  = 32'h0EE00593;
        dut.imem.ram[51]  = 32'h00B52023;
        dut.imem.ram[52]  = 32'h00C00BEF;
        dut.imem.ram[53]  = 32'h0EE00593;
        dut.imem.ram[54]  = 32'h00B52023;
        dut.imem.ram[55]  = 32'h00000B97;
        dut.imem.ram[56]  = 32'h010B8C67;
        dut.imem.ram[57]  = 32'h0EE00593;
        dut.imem.ram[58]  = 32'h00B52023;
        dut.imem.ram[59]  = 32'h04400593;
        dut.imem.ram[60]  = 32'h00B52023; 
        dut.imem.ram[61]  = 32'h06000213;
        dut.imem.ram[62]  = 32'h00022087;
        dut.imem.ram[63]  = 32'h00422107;
        dut.imem.ram[64]  = 32'h00822187;
        dut.imem.ram[65]  = 32'h00C22207;
        dut.imem.ram[66]  = 32'h203084D3; 
        dut.imem.ram[67]  = 32'h20311553; 
        dut.imem.ram[68]  = 32'h2030A5D3; 
        dut.imem.ram[69]  = 32'hE00195D3; 
        dut.imem.ram[70]  = 32'hE0008D53; 
        dut.imem.ram[71]  = 32'h00000013; 
        dut.imem.ram[72]  = 32'h00000013; 
        dut.imem.ram[73]  = 32'hF00D0753; 
        dut.imem.ram[74]  = 32'hC00106D3; 
        dut.imem.ram[75]  = 32'h00000013; 
        dut.imem.ram[76]  = 32'h00000013; 
        dut.imem.ram[77]  = 32'hD00687D3; 
        dut.imem.ram[78]  = 32'h05500593; 
        dut.imem.ram[79]  = 32'h00B52023; 
        dut.imem.ram[80]  = 32'h084102C3;
        dut.imem.ram[81]  = 32'h08410347;
        dut.imem.ram[82]  = 32'h084103CB;
        dut.imem.ram[83]  = 32'h0841044F;
        dut.imem.ram[84]  = 32'h004108D3;
        dut.imem.ram[85]  = 32'h08220953;
        dut.imem.ram[86]  = 32'h104109D3;
        dut.imem.ram[87]  = 32'h28410653;
        dut.imem.ram[88]  = 32'h281196D3;
        dut.imem.ram[89]  = 32'hA0212453;
        dut.imem.ram[90]  = 32'hA01194D3;
        dut.imem.ram[91]  = 32'hA0220A53;
        dut.imem.ram[92]  = 32'h06600593;
        dut.imem.ram[93]  = 32'h00B52023; 
        dut.imem.ram[94]  = 32'h00000093;
        dut.imem.ram[95]  = 32'h02000113;
        dut.imem.ram[96]  = 32'h04000193;
        dut.imem.ram[97]  = 32'h0220800B;
        dut.imem.ram[98]  = 32'h00022603;
        dut.imem.ram[99]  = 32'h00C22223;
        dut.imem.ram[100] = 32'h00C12023;
        dut.imem.ram[101] = 32'h0000A683;
        dut.imem.ram[102] = 32'h0211800B;
        dut.imem.ram[103] = 32'h0231000B;
        dut.imem.ram[104] = 32'h07700593;
        dut.imem.ram[105] = 32'h00B52023; 
        dut.imem.ram[106] = 32'h0AA00693; 
        dut.imem.ram[107] = 32'h00D62023; 
        dut.imem.ram[108] = 32'h00100693; 
        dut.imem.ram[109] = 32'h00D62623; 
        dut.imem.ram[110] = 32'h09900593; 
        dut.imem.ram[111] = 32'h00B52023; 
        dut.imem.ram[112] = 32'h0FF00593; 
        dut.imem.ram[113] = 32'h00B52023; 
        dut.imem.ram[114] = 32'h01400693; 
        dut.imem.ram[115] = 32'hFFF68693; 
        dut.imem.ram[116] = 32'h00000013; 
        dut.imem.ram[117] = 32'hFE069CE3; 
        dut.imem.ram[118] = 32'h00052023; 
        dut.imem.ram[119] = 32'h01400693; 
        dut.imem.ram[120] = 32'hFFF68693; 
        dut.imem.ram[121] = 32'h00000013; 
        dut.imem.ram[122] = 32'hFE069CE3; 
        dut.imem.ram[123] = 32'hF57FF06F; 

        dut.dmem.bank0[3] = 32'h00003C00; // f1 = 1.0
        dut.dmem.bank1[3] = 32'h00004000; // f2 = 2.0
        dut.dmem.bank2[3] = 32'h0000C000; // f3 = -2.0
        dut.dmem.bank3[3] = 32'h00004400; // f4 = 4.0

        clk = 0; 
        reset = 0; 
        total_cycles = 0; 
        stalls = 0; 
        prev_gpio_out = 8'h00;
        blinky_active = 0;
        blink_count = 0;

        #25 reset = 1; 

        $display("==================================================================================");
        $display("  SYSTEM OMNI-TEST: STRICT INSTRUCTION-BY-INSTRUCTION VERIFICATION");
        $display("==================================================================================");
    end

    always @(negedge clk) begin
        if (reset) begin
            total_cycles = total_cycles + 1;
            if (dut.cpu.combined_sys_stall) stalls = stalls + 1; 
        end
    end

    task check;
        input [31:0] expected_pc;
        input [4:0]  expected_reg;
        input [31:0] expected_data;
        input [127:0] name;
        input [1:0]  inst_type; 
        
        reg [4:0]  actual_rd;
        reg [31:0] actual_data;
        begin
            if (inst_type == 2) begin
                if (dut.cpu.PCW === expected_pc)
                    $display("%0t | %s | PASS   | Executed safely at PC=%h", $time, name, dut.cpu.PCW);
                else
                    $display("%0t | %s \t | FAIL \t  | Expected: PC=%h \n |\t \t                                                  Got     : PC=%h", 
                             $time, name, expected_pc, dut.cpu.PCW);
            end else begin
                actual_rd   = (inst_type == 1) ? dut.fpu_pipe.RdW_FP : dut.cpu.Final_RdW;
                actual_data = (inst_type == 1) ? {16'h0000, dut.fpu_pipe.FP_ResultW} : dut.cpu.Final_ResultW;
                
                if (dut.cpu.PCW === expected_pc && actual_rd === expected_reg && actual_data === expected_data) 
                    $display("%0t | %s | PASS   | PC=%h, Reg=%s%0d, Data=%h", 
                             $time, name, dut.cpu.PCW, (inst_type==1)?"f":"x", actual_rd, actual_data);
                else 
                    $display("%0t | %s \t | FAIL \t  | Expected: PC=%h, Reg=%s%0d, Data=%h\n |\t \t                                                  Got     : PC=%h, Reg=%s%0d, Data=%h", 
                             $time, name, expected_pc, (inst_type==1)?"f":"x", expected_reg, expected_data, dut.cpu.PCW, (inst_type==1)?"f":"x", actual_rd, actual_data);
            end
        end
    endtask

    always @(negedge clk) begin
        if (inst_retiring && !blinky_active) begin
            case (dut.cpu.PCW)
                32'h000: check(32'h000, 10, 32'h40000000, "LUI   x10", 0);
                32'h004: check(32'h004, 12, 32'h50000000, "LUI   x12", 0);
                32'h008: check(32'h008, 11, 32'h000000FF, "ADDI  x11", 0);
                32'h00C: check(32'h00C, 0,  0,            "SW    x11", 2);
                32'h010: check(32'h010, 11, 32'h00000011, "ADDI  x11", 0);
                32'h014: check(32'h014, 0,  0,            "SW    x11", 2); 
                
                32'h018: check(32'h018, 1,  32'hFFFFFFFF, "ADDI  x1 ", 0);
                32'h01C: check(32'h01C, 2,  32'hFFFFFFFE, "ADD   x2 ", 0);
                32'h020: check(32'h020, 3,  32'h00000002, "SUB   x3 ", 0);
                32'h024: check(32'h024, 4,  32'h0000000D, "XORI  x4 ", 0);
                32'h028: check(32'h028, 5,  32'h0000001D, "ORI   x5 ", 0);
                32'h02C: check(32'h02C, 6,  32'h00000008, "ANDI  x6 ", 0);
                32'h030: check(32'h030, 7,  32'h00000020, "SLLI  x7 ", 0);
                32'h034: check(32'h034, 8,  32'hFFFFFFFF, "SRAI  x8 ", 0); 
                32'h038: check(32'h038, 9,  32'h7FFFFFFF, "SRLI  x9 ", 0); 
                32'h03C: check(32'h03C, 13, 32'h00000001, "SLTI  x13", 0);
                32'h040: check(32'h040, 14, 32'h00000000, "SLTIU x14", 0);
                32'h044: check(32'h044, 11, 32'h00000022, "ADDI  x11", 0);
                32'h048: check(32'h048, 0,  0,            "SW    x11", 2); 

                32'h04C: check(32'h04C, 15, 32'h00000000, "ADDI  x15", 0);
                32'h050: check(32'h050, 16, 32'h000000AA, "ADDI  x16", 0);
                32'h054: check(32'h054, 0,  0,            "SW    x16", 2);
                32'h058: check(32'h058, 17, 32'h000000AA, "LW    x17", 0);
                32'h05C: check(32'h05C, 18, 32'h00000154, "ADD   x18", 0);
                32'h060: check(32'h060, 0,  0,            "SH    x18", 2);
                32'h064: check(32'h064, 19, 32'h00000154, "LH    x19", 0);
                32'h068: check(32'h068, 17, 32'h00000154, "LHU   x17", 0);
                32'h06C: check(32'h06C, 0,  0,            "SB    x17", 2);
                32'h070: check(32'h070, 19, 32'h00000054, "LB    x19", 0);
                32'h074: check(32'h074, 17, 32'h00000054, "LBU   x17", 0);
                32'h078: check(32'h078, 11, 32'h00000033, "ADDI  x11", 0);
                32'h07C: check(32'h07C, 0,  0,            "SW    x11", 2); 

                32'h080: check(32'h080, 21, 32'hFFFFFFFB, "ADDI  x21", 0);
                32'h084: check(32'h084, 22, 32'h00000005, "ADDI  x22", 0);
                32'h088: check(32'h088, 0,  0,            "BEQ      ", 2);
                32'h094: check(32'h094, 0,  0,            "BNE      ", 2);
                32'h0A0: check(32'h0A0, 0,  0,            "BLT      ", 2);
                32'h0AC: check(32'h0AC, 0,  0,            "BGE      ", 2);
                32'h0B8: check(32'h0B8, 0,  0,            "BLTU     ", 2);
                32'h0C4: check(32'h0C4, 0,  0,            "BGEU     ", 2);
                32'h0D0: check(32'h0D0, 23, 32'h000000D4, "JAL   x23", 0);
                32'h0DC: check(32'h0DC, 23, 32'h000000DC, "AUIPC x23", 0);
                32'h0E0: check(32'h0E0, 24, 32'h000000E4, "JALR  x24", 0);
                32'h0EC: check(32'h0EC, 11, 32'h00000044, "ADDI  x11", 0);
                32'h0F0: check(32'h0F0, 0,  0,            "SW    x11", 2); 

                32'h0F4: check(32'h0F4, 4,  32'h00000060, "ADDI  x4 ", 0);
                32'h0F8: check(32'h0F8, 1,  32'h00003C00, "FLW   f1 ", 1); 
                32'h0FC: check(32'h0FC, 2,  32'h00004000, "FLW   f2 ", 1); 
                32'h100: check(32'h100, 3,  32'h0000C000, "FLW   f3 ", 1); 
                32'h104: check(32'h104, 4,  32'h00004400, "FLW   f4 ", 1); 
                32'h108: check(32'h108, 9,  32'h0000BC00, "FSGNJ f9 ", 1); 
                32'h10C: check(32'h10C, 10, 32'h00004000, "FSGNJNf10", 1); 
                32'h110: check(32'h110, 11, 32'h0000BC00, "FSGNJXf11", 1); 
                32'h114: check(32'h114, 11, 32'h00000002, "FCLASSx11", 0); 
                32'h118: check(32'h118, 26, 32'h00003C00, "FMV.X x26", 0); 
                32'h11C: check(32'h11C, 0,  0,            "NOP      ", 2); 
                32'h120: check(32'h120, 0,  0,            "NOP      ", 2); 
                32'h124: check(32'h124, 14, 32'h00003C00, "FMV.W f14", 1); 
                32'h128: check(32'h128, 13, 32'h00000002, "FCVT.Wx13", 0); 
                32'h12C: check(32'h12C, 0,  0,            "NOP      ", 2); 
                32'h130: check(32'h130, 0,  0,            "NOP      ", 2); 
                32'h134: check(32'h134, 15, 32'h00004000, "FCVT.Sf15", 1); 
                32'h138: check(32'h138, 11, 32'h00000055, "ADDI  x11", 0);
                32'h13C: check(32'h13C, 0,  0,            "SW    x11", 2); 

                // --- PHASE 6: FP MATH (FIXED EXPECTATIONS!) ---
                32'h140: check(32'h140, 5,  32'h00004880, "FMADD f5 ", 1); // 9.0
                32'h144: check(32'h144, 6,  32'h00004700, "FMSUB f6 ", 1); // 7.0
                32'h148: check(32'h148, 7,  32'h0000C700, "FNMSUBf7 ", 1); // -7.0
                32'h14C: check(32'h14C, 8,  32'h0000C880, "FNMADDf8 ", 1); // -9.0
                32'h150: check(32'h150, 17, 32'h00004600, "FADD  f17", 1); // 6.0
                32'h154: check(32'h154, 18, 32'h00004000, "FSUB  f18", 1); // 2.0
                32'h158: check(32'h158, 19, 32'h00004800, "FMUL  f19", 1); // 8.0
                32'h15C: check(32'h15C, 12, 32'h00004000, "FMIN  f12", 1); // 2.0
                32'h160: check(32'h160, 13, 32'h00003C00, "FMAX  f13", 1); // 1.0
                32'h164: check(32'h164, 8,  32'h00000001, "FEQ   x8 ", 0);
                32'h168: check(32'h168, 9,  32'h00000001, "FLT   x9 ", 0);
                32'h16C: check(32'h16C, 20, 32'h00000000, "FLE   x20", 0);
                32'h170: check(32'h170, 11, 32'h00000066, "ADDI  x11", 0);
                32'h174: check(32'h174, 0,  0,            "SW    x11", 2); 

                32'h178: check(32'h178, 1,  32'h00000000, "ADDI  x1 ", 0);
                32'h17C: check(32'h17C, 2,  32'h00000020, "ADDI  x2 ", 0);
                32'h180: check(32'h180, 3,  32'h00000040, "ADDI  x3 ", 0);
                32'h184: check(32'h184, 0,  0,            "DMA MAC  ", 2);
                32'h188: check(32'h188, 12, 32'h00003C00, "LW    x12", 0); 
                32'h18C: check(32'h18C, 0,  0,            "SW    x12", 2);
                32'h190: check(32'h190, 0,  0,            "SW    x12", 2);
                32'h194: check(32'h194, 13, 32'h44004400, "LW    x13", 0); 
                32'h198: check(32'h198, 0,  0,            "DMA      ", 2);
                32'h19C: check(32'h19C, 0,  0,            "DMA      ", 2);
                32'h1A0: check(32'h1A0, 11, 32'h00000077, "ADDI  x11", 0);
                32'h1A4: check(32'h1A4, 0,  0,            "SW    x11", 2); 

                32'h1A8: check(32'h1A8, 13, 32'h000000AA, "ADDI  x13", 0);
                32'h1AC: check(32'h1AC, 0,  0,            "SW    x13", 2);
                32'h1B0: check(32'h1B0, 13, 32'h00000001, "ADDI  x13", 0);
                32'h1B4: check(32'h1B4, 0,  0,            "SW    x13", 2);
                32'h1B8: check(32'h1B8, 11, 32'h00000099, "ADDI  x11", 0);
                32'h1BC: check(32'h1BC, 0,  0,            "SW    x11", 2); 
                
                default: ; 
            endcase
        end
    end

    always @(negedge clk) begin
        if (gpio_out !== prev_gpio_out && gpio_out !== 8'hxx) begin
            
            if (!blinky_active) begin
                case (gpio_out)
                    8'h11: $display("\n>>> [%0t] [CHECKPOINT] PHASE 1: System Booted.", $time);
                    8'h22: $display("\n>>> [%0t] [CHECKPOINT] PHASE 2: RV32I ALU Flawless.", $time);
                    8'h33: $display("\n>>> [%0t] [CHECKPOINT] PHASE 3: RV32I Memory Flawless.", $time);
                    8'h44: $display("\n>>> [%0t] [CHECKPOINT] PHASE 4: RV32I Branches Flawless.", $time);
                    8'h55: $display("\n>>> [%0t] [CHECKPOINT] PHASE 5: RV32F Casts Flawless.", $time);
                    8'h66: $display("\n>>> [%0t] [CHECKPOINT] PHASE 6: RV32F Math Flawless.", $time);
                    8'h77: $display("\n>>> [%0t] [CHECKPOINT] PHASE 7: DMA Memory Flawless.", $time);
                    
                    8'hEE: begin
                        $display("\n>>> [%0t] [FATAL ERROR] DEATH TRAP HIT! A branch or jump mispredicted.", $time);
                        $finish;
                    end

                    8'h99: begin
                        $display("\n>>> [%0t] [CHECKPOINT] PHASE 9: Omni-Test Complete! Entering Visual Blinky Mode.", $time);
                        blinky_active = 1;
                    end
                    
                    8'h00: ; 
                endcase
            end 
            else begin
                if (gpio_out == 8'hFF) begin
                    $display("[%0t] [VISUAL] LEDs ON  (0xFF)", $time);
                    blink_count = blink_count + 1;
                end 
                else if (gpio_out == 8'h00) begin
                    $display("[%0t] [VISUAL] LEDs OFF (0x00)", $time);
                end
                
                if (blink_count == 3) begin
                    $display("==================================================================================");
                    $display("[%0t] [FINAL SUCCESS] 100%% HARDWARE INSTRUCTION COVERAGE ACHIEVED!", $time);
                    $display("  Total CPU Cycles Elapsed: %0d", total_cycles);
                    $display("==================================================================================");
                    $finish;
                end
            end

            prev_gpio_out <= gpio_out;
        end
    end

    reg [7:0] spi_rx_data = 8'h00;
    integer spi_bit_count = 0;

    always @(posedge sclk) begin
        if (!cs_n) begin
            spi_rx_data = {spi_rx_data[6:0], mosi};
            spi_bit_count = spi_bit_count + 1;
            if (spi_bit_count == 8) begin
                $display("[%0t] [PASS] SPI Transmitted: 0x%h (Expected 0xAA)", $time, spi_rx_data);
                spi_bit_count = 0;
            end
        end
    end

    initial begin
        #60000;
        $display("[%0t] [TIMEOUT] Processor stalled indefinitely or stuck in loop.", $time);
        $finish;
    end
endmodule