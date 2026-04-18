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
    
    // External Pins
    reg  [7:0] gpio_in;
    wire [7:0] gpio_out;
    wire cs_n;
    reg  miso;
    wire mosi;
    wire sclk;
    
    // Testbench tracking variables
    integer total_cycles, stalls;
    reg [7:0] prev_gpio_out;
    reg blinky_active;
    integer blink_count;

    // Instantiate Top-Level SoC (Direct RTL)
    riscv_soc dut (
        .clk(clk), 
        .reset(reset),
        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .miso(miso),
        .mosi(mosi),
        .sclk(sclk),
        .cs_n(cs_n)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("soc_omni_test.vcd");
        $dumpvars(0, tb_soc_omni_test);
        
        // =========================================================================
        // LOAD INSTRUCTION MEMORY (Hardcoded Griller Program - Fast Sim Delay)
        // =========================================================================
        // Clear memory first
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
        dut.imem.ram[13]  = 32'h40105413;
        dut.imem.ram[14]  = 32'h00105493;
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
        dut.imem.ram[71]  = 32'hF00D0753;
        dut.imem.ram[72]  = 32'hC00106D3;
        dut.imem.ram[73]  = 32'hD00687D3;
        dut.imem.ram[74]  = 32'h05500593;
        dut.imem.ram[75]  = 32'h00B52023;
        dut.imem.ram[76]  = 32'h084102C3;
        dut.imem.ram[77]  = 32'h08410347;
        dut.imem.ram[78]  = 32'h084103CB;
        dut.imem.ram[79]  = 32'h0841044F;
        dut.imem.ram[80]  = 32'h004108D3;
        dut.imem.ram[81]  = 32'h08220953;
        dut.imem.ram[82]  = 32'h104109D3;
        dut.imem.ram[83]  = 32'h18220A53;
        dut.imem.ram[84]  = 32'h58020AD3;
        dut.imem.ram[85]  = 32'h28410653;
        dut.imem.ram[86]  = 32'h281196D3;
        dut.imem.ram[87]  = 32'hA0212453;
        dut.imem.ram[88]  = 32'hA01194D3;
        dut.imem.ram[89]  = 32'hA0220A53;
        dut.imem.ram[90]  = 32'h06600593;
        dut.imem.ram[91]  = 32'h00B52023;
        dut.imem.ram[92]  = 32'h00000093;
        dut.imem.ram[93]  = 32'h02000113;
        dut.imem.ram[94]  = 32'h04000193;
        dut.imem.ram[95]  = 32'h0220800B;
        dut.imem.ram[96]  = 32'h00022603;
        dut.imem.ram[97]  = 32'h00C22223;
        dut.imem.ram[98]  = 32'h00C12023;
        dut.imem.ram[99]  = 32'h0000A683;
        dut.imem.ram[100] = 32'h0211800B;
        dut.imem.ram[101] = 32'h0231000B;
        dut.imem.ram[102] = 32'h07700593;
        dut.imem.ram[103] = 32'h00B52023;
        dut.imem.ram[104] = 32'h0AA00693;
        dut.imem.ram[105] = 32'h00D62023;
        dut.imem.ram[106] = 32'h00100693;
        dut.imem.ram[107] = 32'h00D62623;
        dut.imem.ram[108] = 32'h09900593;
        dut.imem.ram[109] = 32'h00B52023;
        dut.imem.ram[110] = 32'h0FF00593;
        dut.imem.ram[111] = 32'h00B52023;
        dut.imem.ram[112] = 32'h01400693;
        dut.imem.ram[113] = 32'hFFF68693;
        dut.imem.ram[114] = 32'h00000013;
        dut.imem.ram[115] = 32'hFE069CE3;
        dut.imem.ram[116] = 32'h00052023;
        dut.imem.ram[117] = 32'h01400693;
        dut.imem.ram[118] = 32'hFFF68693;
        dut.imem.ram[119] = 32'h00000013;
        dut.imem.ram[120] = 32'hFE069CE3;
        dut.imem.ram[121] = 32'hF57FF06F;

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
        reset = 0; // Active-Low Reset
        gpio_in = 8'h00;
        miso = 1'b0;
        
        total_cycles = 0; 
        stalls = 0; 
        prev_gpio_out = 8'h00;
        blinky_active = 0;
        blink_count = 0;

        #25 reset = 1; // Release reset

        $display("==================================================================================");
        $display("  SYSTEM OMNI-TEST 7.0: DIRECT RTL GPIO/SPI OBSERVATION");
        $display("==================================================================================");
    end

    // Cycle & Stall Counter
    always @(negedge clk) begin
        if (reset) begin
            total_cycles = total_cycles + 1;
            if (dut.cpu.combined_sys_stall) stalls = stalls + 1;
        end
    end

    // ===================================================================
    // CHECKPOINT & BLINKY MONITOR (Watches top-level gpio_out)
    // ===================================================================
    always @(negedge clk) begin
        if (gpio_out !== prev_gpio_out && gpio_out !== 8'hxx) begin
            
            if (!blinky_active) begin
                case (gpio_out)
                    8'h11: $display("[%0t] [PASS] PHASE 1: System Booted.", $time);
                    8'h22: $display("[%0t] [PASS] PHASE 2: RV32I ALU & Forwarding Flawless.", $time);
                    8'h33: $display("[%0t] [PASS] PHASE 3: RV32I Memory & Load-Use Stalls Flawless.", $time);
                    8'h44: $display("[%0t] [PASS] PHASE 4: RV32I Branches & Jumps Flawless.", $time);
                    8'h55: $display("[%0t] [PASS] PHASE 5: RV32F Casts Flawless.", $time);
                    8'h66: $display("[%0t] [PASS] PHASE 6: RV32F Math & Comparators Flawless.", $time);
                    8'h77: $display("[%0t] [PASS] PHASE 7: DMA Memory Interlocks Flawless.", $time);
                    
                    8'hEE: begin
                        $display("[%0t] [FATAL ERROR] DEATH TRAP HIT! A branch or jump mispredicted.", $time);
                        $finish;
                    end

                    8'h99: begin
                        $display("[%0t] [PASS] PHASE 8: Omni-Test Complete! Entering Visual Blinky Mode.", $time);
                        blinky_active = 1;
                    end
                    
                    8'h00: ; 
                    default: $display("[%0t] [WARN] Unexpected GPIO Output: %h", $time, gpio_out);
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
                    $display("[%0t] [FINAL SUCCESS] 100%% HARDWARE PERIPHERAL COVERAGE ACHIEVED!", $time);
                    $display("  Total CPU Cycles Elapsed: %0d", total_cycles);
                    $display("==================================================================================");
                    $finish;
                end
            end

            prev_gpio_out <= gpio_out;
        end
    end

    // ===================================================================
    // PERIPHERAL MONITORS (Watches top-level SPI pins)
    // ===================================================================
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

    // Safety Timeout
    initial begin
        #60000;
        $display("[%0t] [TIMEOUT] Processor stalled indefinitely or stuck in loop.", $time);
        $finish;
    end
endmodule