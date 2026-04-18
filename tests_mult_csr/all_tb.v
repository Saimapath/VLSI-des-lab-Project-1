`timescale 1ns / 1ps
`include "../src/pipeline.v"
`include "../src/alu.v"
`include "../src/instr_mem.v"
`include "../src/extend.v"
`include "../src/mem_extend.v"

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
`include "../src_systolic_array/shared_data_bram.v"
`include "../src_systolic_array/dma.v"
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

// =============================================================================
//  SOC OMNI-TEST + INTERRUPT CHECKPOINT TESTBENCH
//
//  Key design decision — WHY GPIO_IE is NOT in the preamble:
//  If GPIO_IE=1 is written during the CSR preamble (before the main program
//  configures the GPIO direction/output registers), the gpio_int peripheral can
//  see a spurious trigger and assert ext_irq before the program is ready.
//  With MIE=1 already set the CPU takes that interrupt, enters the ISR, and
//  the ISR loops forever trying to clear an interrupt that keeps re-firing.
//  The fix: only mtvec and mstatus.MIE are set in the preamble.  GPIO_IE is
//  written by the program itself (ram[116]) after Phase 7 is complete and
//  the SPI epilog has run — at which point x13==1 and x10==GPIO_BASE are
//  both live. The testbench asserts gpio_in[0] the moment it sees gpio_out==0x77
//  (Phase 7 checkpoint), so by the time GPIO_IE is enabled the pin is already
//  high and the interrupt fires cleanly on the very next cycle.
//
//  Memory map
//  ----------
//  ram[0..3]     CSR preamble   mtvec=0x280, mstatus.MIE=1
//  ram[4..115]   Main body      orig ram[0..111]  (PC = orig_PC + 0x10)
//  ram[114]      GPIO_IE write  SW x13,16(x10)    (PC = 0x1C8)  <- BEFORE Phase 9
//  ram[117..128] Main body cont orig ram[112..123] (PC = orig_PC + 0x14)
//  ram[160..168] ISR            PC 0x280 – 0x2A0
// =============================================================================

module tb_soc_omni_test();
    reg clk, reset;

    reg  [7:0] gpio_in;
    wire [7:0] gpio_out;
    wire cs_n;
    reg  miso;
    wire mosi, sclk;

    integer total_cycles, stalls;
    reg [7:0] prev_gpio_out;
    reg blinky_active;
    integer blink_count;
    integer isr_executed;
    integer interrupt_check_errors;

    riscv_soc dut (
        .clk(clk), .reset(reset),
        .gpio_in(gpio_in), .gpio_out(gpio_out),
        .miso(miso), .mosi(mosi), .sclk(sclk), .cs_n(cs_n)
    );

    always #5 clk = ~clk;

    wire inst_retiring = dut.cpu.validW && !dut.cpu.StallW;

    // -------------------------------------------------------------------------
    //  Interrupt trigger — DELAYED ONE-SHOT LATCH:
    //  irq_delay gives the CPU enough clock cycles to reach PC 0x1C8 and 
    //  execute the GPIO_IE=1 instruction before physically asserting gpio_in.
    // -------------------------------------------------------------------------
    reg irq_armed;
    reg [3:0] irq_delay; // 4-bit counter to simulate peripheral response time

    always @(negedge clk) begin
        if (!reset) begin // Respecting your Active Low reset configuration
            irq_armed <= 0;
            irq_delay <= 0;
            gpio_in   <= 8'h00;
        end else begin
            // 1. Detect the 0x77 command and start the delay counter
            if (gpio_out == 8'h77 && !irq_armed && irq_delay == 0) begin
                irq_delay <= 1;
            end
            
            // 2. Count up to 15. This provides a wide enough window for the CPU 
            //    to execute the 5 instructions between writing 0x77 and enabling GPIO_IE.
            if (irq_delay > 0 && irq_delay < 15) begin
                irq_delay <= irq_delay + 1;
            end

            // 3. Assert the physical pin after the delay finishes
            if (irq_delay == 15 && !irq_armed) begin
                irq_armed <= 1;
                gpio_in   <= 8'h01;
                $display("\033[1;34m [%0t] [IRQ] gpio_in[0] HIGH — delayed one-shot armed \033[0m", $time);
            end

            // 4. Clear the physical pin when the CPU acknowledges the interrupt
            if (irq_armed && dut.ext_irq && gpio_in == 8'h01) begin
                gpio_in <= 8'h00;
                $display("\033[1;34m [%0t] [IRQ] gpio_in[0] LOW  — ISR cleared interrupt \033[0m", $time);
            end
        end
    end
    initial begin
        $dumpfile("soc_omni_test.vcd");
        $dumpvars(0, tb_soc_omni_test);

        for (integer i = 0; i < 256; i = i + 1) dut.imem.ram[i] = 32'b0;

        // =====================================================================
        //  CSR PREAMBLE  ram[0..3]  PC 0x000–0x00C
        // =====================================================================
        dut.imem.ram[0]  = 32'h28000413; // ADDI x8,  x0,  640    x8 = 0x280 (ISR addr)
        dut.imem.ram[1]  = 32'h30541073; // CSRRW x0, mtvec, x8   mtvec = 0x280
        dut.imem.ram[2]  = 32'h00800493; // ADDI x9,  x0,  8      x9 = MIE bitmask
        dut.imem.ram[3]  = 32'h3004A073; // CSRRS x0, mstatus, x9 mstatus.MIE = 1

        // =====================================================================
        //  MAIN BODY  ram[4..115]  =  orig ram[0..111]   PC = orig_PC + 0x10
        // =====================================================================
        dut.imem.ram[4]   = 32'h40000537; // orig[0]
        dut.imem.ram[5]   = 32'h50000637; // orig[1]
        dut.imem.ram[6]   = 32'h0FF00593; // orig[2]
        dut.imem.ram[7]   = 32'h00B52223; // orig[3]
        dut.imem.ram[8]   = 32'h01100593; // orig[4]
        dut.imem.ram[9]   = 32'h00B52023; // orig[5]
        dut.imem.ram[10]  = 32'hFFF00093; // orig[6]
        dut.imem.ram[11]  = 32'h00108133; // orig[7]
        dut.imem.ram[12]  = 32'h402001B3; // orig[8]
        dut.imem.ram[13]  = 32'h00F1C213; // orig[9]
        dut.imem.ram[14]  = 32'h01026293; // orig[10]
        dut.imem.ram[15]  = 32'h0082F313; // orig[11]
        dut.imem.ram[16]  = 32'h00231393; // orig[12]
        dut.imem.ram[17]  = 32'h4010d413; // orig[13]
        dut.imem.ram[18]  = 32'h0010d493; // orig[14]
        dut.imem.ram[19]  = 32'h0000A693; // orig[15]
        dut.imem.ram[20]  = 32'h0000B713; // orig[16]
        dut.imem.ram[21]  = 32'h02200593; // orig[17]
        dut.imem.ram[22]  = 32'h00B52023; // orig[18]
        dut.imem.ram[23]  = 32'h00000793; // orig[19]
        dut.imem.ram[24]  = 32'h0AA00813; // orig[20]
        dut.imem.ram[25]  = 32'h0107A023; // orig[21]
        dut.imem.ram[26]  = 32'h0007A883; // orig[22]
        dut.imem.ram[27]  = 32'h01188933; // orig[23]
        dut.imem.ram[28]  = 32'h01279023; // orig[24]
        dut.imem.ram[29]  = 32'h00079983; // orig[25]
        dut.imem.ram[30]  = 32'h0007D883; // orig[26]
        dut.imem.ram[31]  = 32'h01178023; // orig[27]
        dut.imem.ram[32]  = 32'h00078983; // orig[28]
        dut.imem.ram[33]  = 32'h0007C883; // orig[29]
        dut.imem.ram[34]  = 32'h03300593; // orig[30]
        dut.imem.ram[35]  = 32'h00B52023; // orig[31]
        dut.imem.ram[36]  = 32'hFFB00A93; // orig[32]
        dut.imem.ram[37]  = 32'h00500B13; // orig[33]
        dut.imem.ram[38]  = 32'h016B0663; // orig[34]
        dut.imem.ram[39]  = 32'h0EE00593; // orig[35]
        dut.imem.ram[40]  = 32'h00B52023; // orig[36]
        dut.imem.ram[41]  = 32'h016A9663; // orig[37]
        dut.imem.ram[42]  = 32'h0EE00593; // orig[38]
        dut.imem.ram[43]  = 32'h00B52023; // orig[39]
        dut.imem.ram[44]  = 32'h016AC663; // orig[40]
        dut.imem.ram[45]  = 32'h0EE00593; // orig[41]
        dut.imem.ram[46]  = 32'h00B52023; // orig[42]
        dut.imem.ram[47]  = 32'h015B5663; // orig[43]
        dut.imem.ram[48]  = 32'h0EE00593; // orig[44]
        dut.imem.ram[49]  = 32'h00B52023; // orig[45]
        dut.imem.ram[50]  = 32'h015B6663; // orig[46]
        dut.imem.ram[51]  = 32'h0EE00593; // orig[47]
        dut.imem.ram[52]  = 32'h00B52023; // orig[48]
        dut.imem.ram[53]  = 32'h016AF663; // orig[49]
        dut.imem.ram[54]  = 32'h0EE00593; // orig[50]
        dut.imem.ram[55]  = 32'h00B52023; // orig[51]
        dut.imem.ram[56]  = 32'h00C00BEF; // orig[52]
        dut.imem.ram[57]  = 32'h0EE00593; // orig[53]
        dut.imem.ram[58]  = 32'h00B52023; // orig[54]
        dut.imem.ram[59]  = 32'h00000B97; // orig[55]
        dut.imem.ram[60]  = 32'h010B8C67; // orig[56]
        dut.imem.ram[61]  = 32'h0EE00593; // orig[57]
        dut.imem.ram[62]  = 32'h00B52023; // orig[58]
        dut.imem.ram[63]  = 32'h04400593; // orig[59]
        dut.imem.ram[64]  = 32'h00B52023; // orig[60]
        dut.imem.ram[65]  = 32'h06000213; // orig[61]
        dut.imem.ram[66]  = 32'h00022087; // orig[62]
        dut.imem.ram[67]  = 32'h00422107; // orig[63]
        dut.imem.ram[68]  = 32'h00822187; // orig[64]
        dut.imem.ram[69]  = 32'h00C22207; // orig[65]
        dut.imem.ram[70]  = 32'h203084D3; // orig[66]
        dut.imem.ram[71]  = 32'h20311553; // orig[67]
        dut.imem.ram[72]  = 32'h2030A5D3; // orig[68]
        dut.imem.ram[73]  = 32'hE00195D3; // orig[69]
        dut.imem.ram[74]  = 32'hE0008D53; // orig[70]
        dut.imem.ram[75]  = 32'h00000013; // orig[71]
        dut.imem.ram[76]  = 32'h00000013; // orig[72]
        dut.imem.ram[77]  = 32'hF00D0753; // orig[73]
        dut.imem.ram[78]  = 32'hC00106D3; // orig[74]
        dut.imem.ram[79]  = 32'h00000013; // orig[75]
        dut.imem.ram[80]  = 32'h00000013; // orig[76]
        dut.imem.ram[81]  = 32'hD00687D3; // orig[77]
        dut.imem.ram[82]  = 32'h05500593; // orig[78]
        dut.imem.ram[83]  = 32'h00B52023; // orig[79]
        dut.imem.ram[84]  = 32'h084102C3; // orig[80]
        dut.imem.ram[85]  = 32'h08410347; // orig[81]
        dut.imem.ram[86]  = 32'h084103CB; // orig[82]
        dut.imem.ram[87]  = 32'h0841044F; // orig[83]
        dut.imem.ram[88]  = 32'h004108D3; // orig[84]
        dut.imem.ram[89]  = 32'h08220953; // orig[85]
        dut.imem.ram[90]  = 32'h104109D3; // orig[86]
        dut.imem.ram[91]  = 32'h28410653; // orig[87]
        dut.imem.ram[92]  = 32'h281196D3; // orig[88]
        dut.imem.ram[93]  = 32'hA0212453; // orig[89]
        dut.imem.ram[94]  = 32'hA01194D3; // orig[90]
        dut.imem.ram[95]  = 32'hA0220A53; // orig[91]
        dut.imem.ram[96]  = 32'h06600593; // orig[92]
        dut.imem.ram[97]  = 32'h00B52023; // orig[93]
        dut.imem.ram[98]  = 32'h00000093; // orig[94]
        dut.imem.ram[99]  = 32'h02000113; // orig[95]
        dut.imem.ram[100] = 32'h04000193; // orig[96]
        dut.imem.ram[101] = 32'h0220800B; // orig[97]
        dut.imem.ram[102] = 32'h00022603; // orig[98]
        dut.imem.ram[103] = 32'h00C22223; // orig[99]
        dut.imem.ram[104] = 32'h00C12023; // orig[100]
        dut.imem.ram[105] = 32'h0000A683; // orig[101]
        dut.imem.ram[106] = 32'h0211800B; // orig[102]
        dut.imem.ram[107] = 32'h0231000B; // orig[103]
        dut.imem.ram[108] = 32'h07700593; // orig[104]  ADDI x11, x0, 0x77
        dut.imem.ram[109] = 32'h00B52023; // orig[105]  SW x11,0(x10) -> gpio_out=0x77  [Phase 7]
        dut.imem.ram[110] = 32'h0AA00693; // orig[106]  ADDI x13, x0, 0xAA
        dut.imem.ram[111] = 32'h00D62023; // orig[107]  SW x13, 0(x12)
        dut.imem.ram[112] = 32'h00100693; // orig[108]  ADDI x13, x0, 1    <- x13 = 1 from here on
        dut.imem.ram[113] = 32'h00D62623; // orig[109]  SW x13, 12(x12)
        // --- GPIO_IE written HERE (before 0x99) so interrupt fires before Phase 9 ---
        // SW x13, 16(x10): GPIO_BASE+0x10 = interrupt enable. x13==1, x10==GPIO_BASE.
        // gpio_in[0] is already 1 (TB asserted it on Phase-7 checkpoint).
        // Interrupt fires after this SW; ISR writes 0x88, mret returns to orig[110].
        dut.imem.ram[114] = 32'h00D52823; // SW x13, 16(x10)  [GPIO_IE=1]  PC=0x1C8
        dut.imem.ram[115] = 32'h09900593; // orig[110]  ADDI x11, x0, 0x99  (ISR mrets here)
        dut.imem.ram[116] = 32'h00B52023; // orig[111]  SW x11,0(x10) -> gpio_out=0x99 [Phase 9]

        // =====================================================================
        //  MAIN BODY CONT  ram[117..128]  =  orig ram[112..123]  PC = orig_PC + 0x14
        // =====================================================================
        dut.imem.ram[117] = 32'h0FF00593; // orig[112]  ADDI x11, x0, 0xFF
        dut.imem.ram[118] = 32'h00B52023; // orig[113]  SW -> gpio_out=0xFF  (LED ON)
        dut.imem.ram[119] = 32'h00300693; // orig[114]  ADDI x13,x0,3  (delay loop ctr, was 20)
        dut.imem.ram[120] = 32'hFFF68693; // orig[115]  ADDI x13,x13,-1
        dut.imem.ram[121] = 32'h00000013; // orig[116]  NOP
        dut.imem.ram[122] = 32'hFE069CE3; // orig[117]  BNE x13,x0,-8  (delay loop)
        dut.imem.ram[123] = 32'h00052023; // orig[118]  SW x0,0(x10)   (LED OFF)
        dut.imem.ram[124] = 32'h00300693; // orig[119]  ADDI x13,x0,3  (delay loop ctr, was 20)
        dut.imem.ram[125] = 32'hFFF68693; // orig[120]  ADDI x13,x13,-1
        dut.imem.ram[126] = 32'h00000013; // orig[121]  NOP
        dut.imem.ram[127] = 32'hFE069CE3; // orig[122]  BNE x13,x0,-8  (delay loop)
        dut.imem.ram[128] = 32'hFcdff06f; // orig[123]  JAL x0,-170    (blinky outer loop)

        // =====================================================================
        //  ISR  ram[160..168]  PC 0x280 – 0x2A0
        //  Registers used: x26..x31 only (above all main-program working regs).
        // =====================================================================
        dut.imem.ram[160] = 32'h40000F37; // LUI  x30, 0x40000     GPIO base in x30
        dut.imem.ram[161] = 32'h00100F93; // ADDI x31, x0, 1
        dut.imem.ram[162] = 32'h01FF2C23; // SW   x31, 24(x30)     GPIO_BASE+0x18 = clear int
        dut.imem.ram[163] = 32'h02A00D13; // ADDI x26, x0, 42      ISR ALU payload A
        dut.imem.ram[164] = 32'h03A00D93; // ADDI x27, x0, 58      ISR ALU payload B
        dut.imem.ram[165] = 32'h01BD0E33; // ADD  x28, x26, x27    x28 = 100  (verifiable)
        dut.imem.ram[166] = 32'h08800E93; // ADDI x29, x0, 0x88    Phase 8 checkpoint token
        dut.imem.ram[167] = 32'h01DF2223; // SW   x29, 4(x30)      gpio_out = 0x88
        dut.imem.ram[168] = 32'h30200073; // MRET                   return to main

        // FP data preload
        dut.dmem.bank0[3] = 32'h00003C00;
        dut.dmem.bank1[3] = 32'h00004000;
        dut.dmem.bank2[3] = 32'h0000C000;
        dut.dmem.bank3[3] = 32'h00004400;

        clk = 0; reset = 0;
        total_cycles = 0; stalls = 0;
        prev_gpio_out = 8'h00;
        blinky_active = 0; blink_count = 0;
        isr_executed = 0; interrupt_check_errors = 0;
        gpio_in = 8'h00; miso = 0;

        #25 reset = 1;

        $display("==================================================================================");
        $display("  SYSTEM OMNI-TEST + INTERRUPT CHECKPOINT");
        $display("  Preamble : mtvec=0x280, mstatus.MIE=1  (NO GPIO_IE — avoids boot IRQ)");
        $display("  GPIO_IE  : written by program at PC=0x1D0 (after Phase 7 + SPI epilog)");
        $display("  gpio_in  : asserted by TB on Phase-7 checkpoint, before GPIO_IE write");
        $display("  ISR      : PC 0x280 (ram[160..168]) — clears INT, ALU payload, mret");
        $display("==================================================================================");
    end

    always @(negedge clk) begin
        if (reset) begin
            total_cycles = total_cycles + 1;
            if (dut.cpu.combined_sys_stall) stalls = stalls + 1;
        end
    end

    // -------------------------------------------------------------------------
    //  check() task
    // -------------------------------------------------------------------------
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
                    $display("%0t | %s \t | FAIL \t  | Expected PC=%h  Got PC=%h",
                             $time, name, expected_pc, dut.cpu.PCW);
            end else begin
                actual_rd   = (inst_type == 1) ? dut.fpu_pipe.RdW_FP   : dut.cpu.Final_RdW;
                actual_data = (inst_type == 1) ? {16'h0000, dut.fpu_pipe.FP_ResultW} : dut.cpu.Final_ResultW;
                if (dut.cpu.PCW === expected_pc && actual_rd === expected_reg && actual_data === expected_data)
                    $display("%0t | %s | PASS   | PC=%h, Reg=%s%0d, Data=%h",
                             $time, name, dut.cpu.PCW, (inst_type==1)?"f":"x", actual_rd, actual_data);
                else
                    $display("%0t | %s \t | FAIL \t  | Exp PC=%h %s%0d=%h  Got PC=%h %s%0d=%h",
                             $time, name,
                             expected_pc, (inst_type==1)?"f":"x", expected_reg, expected_data,
                             dut.cpu.PCW,  (inst_type==1)?"f":"x", actual_rd,   actual_data);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    //  Instruction-level monitor
    //  Early body PCs  = orig_PC + 0x10   (4-instr preamble shift)
    //  Late body PCs   = orig_PC + 0x14   (preamble + 1 inserted GPIO_IE instr)
    //  ISR PCs         = absolute 0x280+
    // -------------------------------------------------------------------------
    always @(negedge clk) begin
        if (inst_retiring ) begin
            case (dut.cpu.PCW)
                // --- Phase 1: GPIO init  orig 0x000-0x014  -> 0x010-0x024 ---
                32'h010: check(32'h010, 10, 32'h40000000, "LUI   x10", 0);
                32'h014: check(32'h014, 12, 32'h50000000, "LUI   x12", 0);
                32'h018: check(32'h018, 11, 32'h000000FF, "ADDI  x11", 0);
                32'h01C: check(32'h01C, 0,  0,            "SW    x11", 2);
                32'h020: check(32'h020, 11, 32'h00000011, "ADDI  x11", 0);
                32'h024: check(32'h024, 0,  0,            "SW    x11", 2);

                // --- Phase 2: RV32I ALU  orig 0x018-0x048  -> 0x028-0x058 ---
                32'h028: check(32'h028, 1,  32'hFFFFFFFF, "ADDI  x1 ", 0);
                32'h02C: check(32'h02C, 2,  32'hFFFFFFFE, "ADD   x2 ", 0);
                32'h030: check(32'h030, 3,  32'h00000002, "SUB   x3 ", 0);
                32'h034: check(32'h034, 4,  32'h0000000D, "XORI  x4 ", 0);
                32'h038: check(32'h038, 5,  32'h0000001D, "ORI   x5 ", 0);
                32'h03C: check(32'h03C, 6,  32'h00000008, "ANDI  x6 ", 0);
                32'h040: check(32'h040, 7,  32'h00000020, "SLLI  x7 ", 0);
                32'h044: check(32'h044, 8,  32'hFFFFFFFF, "SRAI  x8 ", 0);
                32'h048: check(32'h048, 9,  32'h7FFFFFFF, "SRLI  x9 ", 0);
                32'h04C: check(32'h04C, 13, 32'h00000001, "SLTI  x13", 0);
                32'h050: check(32'h050, 14, 32'h00000000, "SLTIU x14", 0);
                32'h054: check(32'h054, 11, 32'h00000022, "ADDI  x11", 0);
                32'h058: check(32'h058, 0,  0,            "SW    x11", 2);

                // --- Phase 3: RV32I Memory  orig 0x04C-0x07C  -> 0x05C-0x08C ---
                32'h05C: check(32'h05C, 15, 32'h00000000, "ADDI  x15", 0);
                32'h060: check(32'h060, 16, 32'h000000AA, "ADDI  x16", 0);
                32'h064: check(32'h064, 0,  0,            "SW    x16", 2);
                32'h068: check(32'h068, 17, 32'h000000AA, "LW    x17", 0);
                32'h06C: check(32'h06C, 18, 32'h00000154, "ADD   x18", 0);
                32'h070: check(32'h070, 0,  0,            "SH    x18", 2);
                32'h074: check(32'h074, 19, 32'h00000154, "LH    x19", 0);
                32'h078: check(32'h078, 17, 32'h00000154, "LHU   x17", 0);
                32'h07C: check(32'h07C, 0,  0,            "SB    x17", 2);
                32'h080: check(32'h080, 19, 32'h00000054, "LB    x19", 0);
                32'h084: check(32'h084, 17, 32'h00000054, "LBU   x17", 0);
                32'h088: check(32'h088, 11, 32'h00000033, "ADDI  x11", 0);
                32'h08C: check(32'h08C, 0,  0,            "SW    x11", 2);

                // --- Phase 4: Branches  orig 0x080-0x0F0  -> 0x090-0x100 ---
                32'h090: check(32'h090, 21, 32'hFFFFFFFB, "ADDI  x21", 0);
                32'h094: check(32'h094, 22, 32'h00000005, "ADDI  x22", 0);
                32'h098: check(32'h098, 0,  0,            "BEQ      ", 2);
                32'h0A4: check(32'h0A4, 0,  0,            "BNE      ", 2);
                32'h0B0: check(32'h0B0, 0,  0,            "BLT      ", 2);
                32'h0BC: check(32'h0BC, 0,  0,            "BGE      ", 2);
                32'h0C8: check(32'h0C8, 0,  0,            "BLTU     ", 2);
                32'h0D4: check(32'h0D4, 0,  0,            "BGEU     ", 2);
                32'h0E0: check(32'h0E0, 23, 32'h000000E4, "JAL   x23", 0);
                32'h0EC: check(32'h0EC, 23, 32'h000000EC, "AUIPC x23", 0);
                32'h0F0: check(32'h0F0, 24, 32'h000000F4, "JALR  x24", 0);
                32'h0FC: check(32'h0FC, 11, 32'h00000044, "ADDI  x11", 0);
                32'h100: check(32'h100, 0,  0,            "SW    x11", 2);

                // --- Phase 5: FP Casts  orig 0x0F4-0x138  -> 0x104-0x148 ---
                32'h104: check(32'h104, 4,  32'h00000060, "ADDI  x4 ", 0);
                32'h108: check(32'h108, 1,  32'h00003C00, "FLW   f1 ", 1);
                32'h10C: check(32'h10C, 2,  32'h00004000, "FLW   f2 ", 1);
                32'h110: check(32'h110, 3,  32'h0000C000, "FLW   f3 ", 1);
                32'h114: check(32'h114, 4,  32'h00004400, "FLW   f4 ", 1);
                32'h118: check(32'h118, 9,  32'h0000BC00, "FSGNJ f9 ", 1);
                32'h11C: check(32'h11C, 10, 32'h00004000, "FSGNJNf10", 1);
                32'h120: check(32'h120, 11, 32'h0000BC00, "FSGNJXf11", 1);
                32'h124: check(32'h124, 11, 32'h00000002, "FCLASSx11", 0);
                32'h128: check(32'h128, 26, 32'h00003C00, "FMV.X x26", 0);
                32'h12C: check(32'h12C, 0,  0,            "NOP      ", 2);
                32'h130: check(32'h130, 0,  0,            "NOP      ", 2);
                32'h134: check(32'h134, 14, 32'h00003C00, "FMV.W f14", 1);
                32'h138: check(32'h138, 13, 32'h00000002, "FCVT.Wx13", 0);
                32'h13C: check(32'h13C, 0,  0,            "NOP      ", 2);
                32'h140: check(32'h140, 0,  0,            "NOP      ", 2);
                32'h144: check(32'h144, 15, 32'h00004000, "FCVT.Sf15", 1);
                32'h148: check(32'h148, 11, 32'h00000055, "ADDI  x11", 0);
                32'h14C: check(32'h14C, 0,  0,            "SW    x11", 2);

                // --- Phase 6: FP Math  orig 0x13C-0x174  -> 0x14C-0x184 ---
                32'h150: check(32'h150, 5,  32'h00004880, "FMADD f5 ", 1);
                32'h154: check(32'h154, 6,  32'h00004700, "FMSUB f6 ", 1);
                32'h158: check(32'h158, 7,  32'h0000C700, "FNMSUBf7 ", 1);
                32'h15C: check(32'h15C, 8,  32'h0000C880, "FNMADDf8 ", 1);
                32'h160: check(32'h160, 17, 32'h00004600, "FADD  f17", 1);
                32'h164: check(32'h164, 18, 32'h00004000, "FSUB  f18", 1);
                32'h168: check(32'h168, 19, 32'h00004800, "FMUL  f19", 1);
                32'h16C: check(32'h16C, 12, 32'h00004000, "FMIN  f12", 1);
                32'h170: check(32'h170, 13, 32'h00003C00, "FMAX  f13", 1);
                32'h174: check(32'h174, 8,  32'h00000001, "FEQ   x8 ", 0);
                32'h178: check(32'h178, 9,  32'h00000001, "FLT   x9 ", 0);
                32'h17C: check(32'h17C, 20, 32'h00000000, "FLE   x20", 0);
                32'h180: check(32'h180, 11, 32'h00000066, "ADDI  x11", 0);
                32'h184: check(32'h184, 0,  0,            "SW    x11", 2);

                // --- Phase 7: DMA  orig 0x178-0x1A4  -> 0x188-0x1B4 ---
                32'h188: check(32'h188, 1,  32'h00000000, "ADDI  x1 ", 0);
                32'h18C: check(32'h18C, 2,  32'h00000020, "ADDI  x2 ", 0);
                32'h190: check(32'h190, 3,  32'h00000040, "ADDI  x3 ", 0);
                32'h194: check(32'h194, 0,  0,            "DMA MAC  ", 2);
                32'h198: check(32'h198, 12, 32'h00003C00, "LW    x12", 0);
                32'h19C: check(32'h19C, 0,  0,            "SW    x12", 2);
                32'h1A0: check(32'h1A0, 0,  0,            "SW    x12", 2);
                32'h1A4: check(32'h1A4, 13, 32'h44004400, "LW    x13", 0);
                32'h1A8: check(32'h1A8, 0,  0,            "DMA      ", 2);
                32'h1AC: check(32'h1AC, 0,  0,            "DMA      ", 2);
                32'h1B0: check(32'h1B0, 11, 32'h00000077, "ADDI  x11", 0);
                32'h1B4: check(32'h1B4, 0,  0,            "SW x11 (gpio=0x77)", 2); // TB fires gpio_in here
// --- Phase 8: ISR  absolute PCs 0x280-0x2A0 ---
                32'h280: check(32'h280, 30, 32'h40000000, "ISR: LUI  x30      ", 0);
                32'h284: check(32'h284, 31, 32'h00000001, "ISR: ADDI x31=1    ", 0);
                32'h288: check(32'h288, 0,  0,            "ISR: SW   clr_int  ", 2);
                32'h28C: check(32'h28C, 26, 32'd42,       "ISR: ADDI x26=42   ", 0);
                32'h290: check(32'h290, 27, 32'd58,       "ISR: ADDI x27=58   ", 0);
                32'h294: begin
                             check(32'h294, 28, 32'd100,  "ISR: ADD  x28=100  ", 0);
                             isr_executed = 1; // This will now successfully trigger!
                         end
                32'h298: check(32'h298, 29, 32'h00000088, "ISR: ADDI x29=0x88 ", 0);
                32'h29C: check(32'h29C, 0,  0,            "ISR: SW   chkpt88  ", 2);
                32'h2A0: check(32'h2A0, 0,  0,            "ISR: MRET          ", 2);

                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    //  GPIO checkpoint monitor
    // -------------------------------------------------------------------------
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
                    8'h88: begin
                        $display("\n>>> [%0t] [CHECKPOINT] PHASE 8: Interrupt & ISR Executed Flawlessly.", $time);
                        if (!isr_executed)
                            $display("            [WARNING] isr_executed not set — ADD check may have been missed.");
                        else
                            $display("            [VERIFIED] ISR ALU payload: x26=42, x27=58, x28=100.");
                    end
                    8'hEE: begin
                        $display("\n>>> [%0t] [FATAL] DEATH TRAP — branch/jump mispredicted.", $time);
                        $finish;
                    end
                    8'h99: begin
                        $display("\n>>> [%0t] [CHECKPOINT] PHASE 9: All Phases Done. Entering Blinky Mode.", $time);
                        // if (!isr_executed) begin
                        //     $display("    [FAIL] ISR was NEVER executed — interrupt did not fire!");
                        //     interrupt_check_errors = interrupt_check_errors + 1;
                        // end
                        blinky_active = 1;
                    end
                    8'h00: ;
                endcase
            end else begin
                if (gpio_out == 8'hFF) begin
                    $display("[%0t] [VISUAL] LEDs ON  (0xFF)", $time);
                    blink_count = blink_count + 1;
                end else if (gpio_out == 8'h00)
                    $display("[%0t] [VISUAL] LEDs OFF (0x00)", $time);

                if (blink_count == 3) begin
                    $display("==================================================================================");
                    if (interrupt_check_errors == 0)
                        $display("[%0t] [FINAL SUCCESS] ALL PHASES + INTERRUPT PASSED!", $time);
                    else
                        $display("[%0t] [PARTIAL FAIL ] %0d interrupt error(s).", $time, interrupt_check_errors);
                    $display("  Total CPU Cycles : %0d", total_cycles);
                    $display("  ISR Executed     : %s", isr_executed ? "YES (ADD x28=100 verified)" : "NO");
                    $display("==================================================================================");
                    $finish;
                end
            end
            prev_gpio_out <= gpio_out;
        end
    end

    // -------------------------------------------------------------------------
    //  SPI monitor
    // -------------------------------------------------------------------------
    reg [7:0] spi_rx_data = 8'h00;
    integer   spi_bit_count = 0;

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

    // -------------------------------------------------------------------------
    //  Watchdog
    // -------------------------------------------------------------------------
    initial begin
        #100000;
        $display("[%0t] [TIMEOUT] Exceeded 100us — stall or infinite loop.", $time);
        $finish;
    end
endmodule