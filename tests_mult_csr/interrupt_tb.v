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

module riscv_final_validation_tb();
    reg clk, reset;
    always #5 clk = ~clk;

    // External Physical Pins
    reg  [7:0] gpio_in;
    wire [7:0] gpio_out;
    reg miso;
    wire cs_n, mosi, sclk;

    // Instantiate Full SoC
    riscv_soc dut (
        .clk(clk), .reset(reset),
        .gpio_in(gpio_in), .gpio_out(gpio_out),
        .miso(miso), .mosi(mosi), .sclk(sclk), .cs_n(cs_n)
    );

    // Probes for monitoring
    wire [31:0] pc_wb       = dut.cpu.PCW;
    wire [4:0]  rd_addr     = dut.cpu.rf.a3;          
    wire [31:0] rd_data     = dut.cpu.rf.wd3;
    wire        reg_we      = dut.cpu.RegWriteW;      

    integer errors = 0;
    integer isr_executed = 0;

    // Validation task for terminal output
    task validate(input [31:0] exp_data, input [4:0] exp_reg, input [255:0] msg);
        begin
            if (rd_data === exp_data && rd_addr === exp_reg) begin
                $display("\033[1;32m [PASS] PC: %h | %s | Reg x%d = %d \033[0m", pc_wb, msg, rd_addr, rd_data);
            end else begin
                $display("\033[1;31m [FAIL] PC: %h | %s | Expected x%d=%d, Got x%d=%d \033[0m", 
                         pc_wb, msg, exp_reg, exp_data, rd_addr, rd_data);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("riscv_stress_test.vcd");
        $dumpvars(0, riscv_final_validation_tb);
        setup_memory();

        clk = 0; reset = 0; gpio_in = 8'h00; miso = 0;
        
        $display("\033[1;36m---------------------------------------------------------");
        $display(" TIME (ps) |  PC WB    |  STATUS  |  RESULT VALIDATION");
        $display("---------------------------------------------------------\033[0m");

        #22 reset = 1;

        // Wait until CPU finishes configuring GPIO and reaches Main Program
        wait(pc_wb == 32'h1C);
        
        // Assert external GPIO pin to trigger Edge Detector
        @(posedge clk);
        gpio_in = 8'h01;
        $display("\033[1;34m [%0t] [ACTION] PHYSICAL GPIO PIN 0 ASSERTED HIGH \033[0m", $time);
        
        // Wait until we see ISR execution start
        wait(pc_wb == 32'hC0);
        gpio_in = 8'h00;
        $display("\033[1;34m [%0t] [ACTION] CPU Trapped to ISR. GPIO PIN 0 DE-ASSERTED \033[0m", $time);

        // End simulation once the main program finishes the final check
        wait(pc_wb == 32'h2C);
        #50;
        
        $display("\033[1;36m---------------------------------------------------------");
        if (errors == 0 && isr_executed) 
            $display("\033[1;32m FINAL RESULT: FULL SYSTEM INTERRUPT STRESS TEST PASSED \033[0m");
        else 
            $display("\033[1;31m FINAL RESULT: TEST FAILED WITH %d ERRORS \033[0m", errors);
        $display("---------------------------------------------------------\033[0m");
        $finish;
    end

    // Monitor: Decides which instruction to validate based on the Writeback PC
    always @(negedge clk) begin
        if (reg_we && reset && (rd_addr != 5'd0) && (rd_addr != 5'd8) && (rd_addr != 5'd9)) begin
            case (pc_wb)
                // --- Main program ---
                32'h0000001C: validate(32'd15,   5'd1,  "MAIN: Load x1");
                32'h00000020: validate(32'd10,   5'd2,  "MAIN: Load x2");
                32'h00000024: validate(32'd150,  5'd3,  "MAIN: MUL x3");
                
                // --- ISR Execution ---
                32'h000000CC: validate(32'd2,    5'd10, "ISR:  Load x10");
                32'h000000D0: validate(32'd60,   5'd11, "ISR:  SLL x11 (Shift Test)");
                32'h000000D4: begin 
                                validate(32'd62,   5'd12, "ISR:  OR x12 (Logic Test)");
                                isr_executed = 1;
                              end

                // --- Resume Main ---
                32'h00000028: validate(32'd135,  5'd4,  "MAIN: SUB x4 (Post-MRET Resume)");
                32'h0000002C: validate(32'd1,    5'd30, "MAIN: Sentinel x30");
            endcase
        end
    end

    task setup_memory;
    begin
        // Fill memory with NOPs
        for (integer i = 0; i < 512; i = i + 1) dut.imem.ram[i] = 32'h00000013; 

        // 1. Setup CSRs (mtvec=0xC0, MIE=1)
        dut.imem.ram[0] = {12'd192, 5'd0, 3'b000, 5'd8, 7'b0010011}; // 0x00: x8=192
        dut.imem.ram[1] = {12'h305, 5'd8, 3'b001, 5'd0, 7'b1110011}; // 0x04: mtvec=x8
        dut.imem.ram[2] = {12'd8,   5'd0, 3'b000, 5'd9, 7'b0010011}; // 0x08: x9=8
        dut.imem.ram[3] = {12'h300, 5'd9, 3'b010, 5'd0, 7'b1110011}; // 0x0C: mstatus.MIE=1

        // 2. Setup GPIO Interrupt Enable (Write 1 to Base + 0x10)
        dut.imem.ram[4] = 32'h40000537;                              // 0x10: lui x10, 0x40000
        dut.imem.ram[5] = 32'h00100593;                              // 0x14: addi x11, x0, 1
        dut.imem.ram[6] = 32'h00B52823;                              // 0x18: sw x11, 16(x10) -> Enable INT on GPIO[0]

        // 3. Main Program
        dut.imem.ram[7] = {12'd15, 5'd0, 3'b000, 5'd1, 7'b0010011};  // 0x1C: x1=15
        dut.imem.ram[8] = {12'd10, 5'd0, 3'b000, 5'd2, 7'b0010011};  // 0x20: x2=10
        dut.imem.ram[9] = {7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011}; // 0x24: x3=x1*x2 (150)
        dut.imem.ram[10]= {7'b0100000, 5'd1, 5'd3, 3'b000, 5'd4, 7'b0110011}; // 0x28: x4=x3-x1 (135)
        dut.imem.ram[11]= {12'd1,  5'd0, 3'b000, 5'd30, 7'b0010011}; // 0x2C: x30=1
        dut.imem.ram[12]= 32'h0000006f;                              // 0x30: jal x0, 0 (Infinite Loop)

        // 4. ISR (0xC0 / index 48) - Clear INT & Math Payload
        dut.imem.ram[48] = 32'h40000537;                             // 0xC0: lui x10, 0x40000
        dut.imem.ram[49] = 32'h00100593;                             // 0xC4: addi x11, x0, 1
        dut.imem.ram[50] = 32'h00B52C23;                             // 0xC8: sw x11, 24(x10) -> Clear INT on GPIO[0]
        
        dut.imem.ram[51] = {12'd2, 5'd0, 3'b000, 5'd10, 7'b0010011}; // 0xCC: x10=2
        dut.imem.ram[52] = {7'b0000000, 5'd10, 5'd1, 3'b001, 5'd11, 7'b0110011}; // 0xD0: x11 = x1 << x10 (60)
        dut.imem.ram[53] = {7'b0000000, 5'd2, 5'd11, 3'b110, 5'd12, 7'b0110011}; // 0xD4: x12 = x11 | x2 (62)
        dut.imem.ram[54] = 32'h30200073;                             // 0xD8: mret
    end
    endtask
endmodule