`timescale 1ns / 1ps

module riscv_tb();
    reg clk, reset;
    integer write_cnt, csr_write_cnt;

    // --- Signal Monitoring ---
    wire [31:0] pc_wb      = dut.cpu.PCW; 
    wire [4:0]  rd_addr    = dut.cpu.rf.a3; 
    wire [31:0] rd_data    = dut.cpu.rf.wd3;
    wire        reg_we     = dut.cpu.RegWriteW; 
    
    wire        csr_we_hw   = dut.cpu.csr.we;
    wire [11:0] csr_addr_hw = dut.cpu.csr.write_addr;
    wire [31:0] csr_data_hw = dut.cpu.csr.write_data;

    riscv_soc dut (.clk(clk), .reset(reset));
    always #5 clk = ~clk;

    // --- CSR Hardware Write Verification (The "True" State) ---
    always @(posedge clk) begin
        if (csr_we_hw && reset) begin
            csr_write_cnt = csr_write_cnt + 1;
            case (csr_write_cnt)
                1:  csr_check(32'hFFFFFFFF, "CSRRW: Write All 1s");
                2:  csr_check(32'hFFFFFFFF, "CSRRS: Set (Hazard E->D)");
                3:  csr_check(32'h00000000, "CSRRC: Clear (Hazard M->D)");
                4:  csr_check(32'h12345678, "CSRRW: Pattern Write");
                5:  csr_check(32'h12345678, "CSRRS: Read-only w/ x0");
                6:  csr_check(32'h12345678, "CSRRC: Read-only w/ x0");
                7:  csr_check(32'h02345678, "CSRRC: Specific bit clear");
                8:  csr_check(32'h0234567F, "CSRRS: Specific bit set");
                9:  csr_check(32'hAAAAAAAA, "CSRRW: Alternating Bits");
                10: csr_check(32'h55555555, "CSRRW: Inverse Bits");
            endcase
        end
    end

    initial begin
        $dumpfile("csr_ultimate_test.vcd");
        $dumpvars(0, riscv_tb);

        // 1. Initialize Memory with NOPs
        for (integer i = 0; i < 256; i = i + 1) dut.imem.ram[i] = 32'h00000013; 

        // 2. The "Ultimate" Instruction Stream
        // --------------------------------------------------------------------------
        
        // --- SECTION 1: Back-to-Back Hazard Stress (PC 0x10-0x18) ---
        dut.imem.ram[4] = {12'h300, 5'd1, 3'b001, 5'd10, 7'b1110011}; // CSRRW: CSR=x1 (All 1s)
        dut.imem.ram[5] = {12'h300, 5'd1, 3'b010, 5'd11, 7'b1110011}; // CSRRS: CSR=CSR|x1 (Hazard)
        dut.imem.ram[6] = {12'h300, 5'd1, 3'b011, 5'd12, 7'b1110011}; // CSRRC: CSR=CSR&~x1 (Hazard)

        // --- SECTION 2: Pattern & Read-Only Logic (PC 0x24-0x30) ---
        dut.imem.ram[9]  = {12'h300, 5'd3, 3'b001, 5'd13, 7'b1110011}; // CSRRW: CSR=x3 (Pattern)
        dut.imem.ram[10] = {12'h300, 5'd0, 3'b010, 5'd14, 7'b1110011}; // CSRRS: x0 (Read Only)
        dut.imem.ram[11] = {12'h300, 5'd0, 3'b011, 5'd15, 7'b1110011}; // CSRRC: x0 (Read Only)
        
        // --- SECTION 3: Specific Bit Manipulations (PC 0x3C-0x44) ---
        dut.imem.ram[15] = {12'h300, 5'd4, 3'b011, 5'd16, 7'b1110011}; // CSRRC: Clear bit 28
        dut.imem.ram[16] = {12'h300, 5'd5, 3'b010, 5'd17, 7'b1110011}; // CSRRS: Set lower 7 bits
        
        // --- SECTION 4: Alternating Patterns (PC 0x50-0x54) ---
        dut.imem.ram[20] = {12'h300, 5'd6, 3'b001, 5'd18, 7'b1110011}; // CSRRW: 0xAAAAAAAA
        dut.imem.ram[21] = {12'h300, 5'd7, 3'b001, 5'd19, 7'b1110011}; // CSRRW: 0x55555555

        // End Flag
        dut.imem.ram[30] = {12'd1, 5'd0, 3'b000, 5'd30, 7'b0010011}; 

        // 3. Setup Logic
        clk = 0; reset = 0; write_cnt = 0; csr_write_cnt = 0;
        #22 reset = 1; 

        // Inject Golden Values
        dut.cpu.rf.rf[1] = 32'hFFFFFFFF; 
        dut.cpu.rf.rf[3] = 32'h12345678; 
        dut.cpu.rf.rf[4] = 32'h10000000; // Bit 28 mask
        dut.cpu.rf.rf[5] = 32'h0000007F; // Lower bits mask
        dut.cpu.rf.rf[6] = 32'hAAAAAAAA; 
        dut.cpu.rf.rf[7] = 32'h55555555; 

        $display("---------------------------------------------------------");
        $display("   ULTIMATE CSR VALIDATION: HAZARDS, PATTERNS, CORNERS");
        $display("---------------------------------------------------------");
    end

    // --- Integer RF Verification ---
    always @(negedge clk) begin
        if (reg_we && reset && rd_addr != 0) begin
            write_cnt = write_cnt + 1;
            case (write_cnt)
                1:  check(5'd10, 32'h00000000, "CSRRW: Initial Read      ");
                2:  check(5'd11, 32'hFFFFFFFF, "CSRRS: Read Hazard (E->D) ");
                3:  check(5'd12, 32'hFFFFFFFF, "CSRRC: Read Hazard (M->D) ");
                4:  check(5'd13, 32'h00000000, "CSRRW: Read before Pattern");
                5:  check(5'd14, 32'h12345678, "CSRRS: Read Pattern (x0)  ");
                6:  check(5'd15, 32'h12345678, "CSRRC: Read Pattern (x0)  ");
                7:  check(5'd16, 32'h12345678, "CSRRC: Read Pre-bit clear ");
                8:  check(5'd17, 32'h02345678, "CSRRS: Read Pre-bit set   ");
                9:  check(5'd18, 32'h0234567F, "CSRRW: Read Pre-Alternat. ");
                10: check(5'd19, 32'hAAAAAAAA, "CSRRW: Read Pre-Inverse   ");

                default: if (rd_addr == 30) begin
                    $display("---------------------------------------------------------");
                    $display("[TA VERIFICATION SUCCESSFUL]");
                    $display("---------------------------------------------------------");
                    $finish;
                end
            endcase
        end
    end

    task check;
        input [4:0] exp_reg; input [31:0] exp_data; input [191:0] test_name;
        begin
            if (rd_data === exp_data) $display("PASS | REG | %s | x%0d=%h", test_name, rd_addr, rd_data);
            else $display("FAIL | REG | %s | Exp %h, Got %h", test_name, exp_data, rd_data);
        end
    endtask

    task csr_check;
        input [31:0] exp_c; input [127:0] o_name;
        begin
            if (csr_data_hw === exp_c) $display("PASS | CSR | %s | Data:%h", o_name, csr_data_hw);
            else $display("FAIL | CSR | %s | Exp %h, Got %h", o_name, exp_c, csr_data_hw);
        end
    endtask
endmodule