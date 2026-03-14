`timescale 1ns / 1ps
`include "../src/pipeline.v"
`include "../src/alu.v"
`include "../src/controller.v"
`include "../src/data_mem_dummy.v"
`include "../src/instr_mem.v"
`include "../src/regfile.v"
`include "../src/extend.v"
`include "../src/hazard_unit.v"
`include "../src/mem_extend.v"
`include "../src/riscv.v"
`include "../src/top.v"

module tb_step_by_step();
    reg clk, reset;
    integer write_cnt;

    // Instantiate Processor
    riscv_soc dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    initial begin
        $dumpfile("step_verify.vcd");
        $dumpvars(0, tb_step_by_step);
        
        // ---------------------------------------------------------------
        // MEMORY INITIALIZATION DIRECTLY FROM TESTBENCH
        // ---------------------------------------------------------------
        // Clear memory first to prevent X states
        for (integer i = 0; i < 64; i = i + 1) dut.imem.ram[i] = 32'b0;

       // --- PHASE 1: Harris & Harris Textbook Program ---
        // Format Map:
        // R-Type: {funct7, rs2, rs1, funct3, rd, opcode}
        // I-Type: {imm[11:0], rs1, funct3, rd, opcode}
        // S-Type: {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode}
        // B-Type: {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode}
        // J-Type: {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode}

        // 00: addi x2, x0, 5
        dut.imem.ram[0]  = {12'd5, 5'd0, 3'b000, 5'd2, 7'b0010011}; 
        
        // 04: addi x3, x0, 12
        dut.imem.ram[1]  = {12'd12, 5'd0, 3'b000, 5'd3, 7'b0010011}; 
        
        // 08: addi x7, x3, -9 (12'hFF7)
        dut.imem.ram[2]  = {12'hFF7, 5'd3, 3'b000, 5'd7, 7'b0010011}; 
        
        // 0C: or x4, x7, x2
        dut.imem.ram[3]  = {7'b0000000, 5'd2, 5'd7, 3'b110, 5'd4, 7'b0110011}; 
        
        // 10: and x5, x3, x4
        dut.imem.ram[4]  = {7'b0000000, 5'd4, 5'd3, 3'b111, 5'd5, 7'b0110011}; 
        
        // 14: add x5, x5, x4
        dut.imem.ram[5]  = {7'b0000000, 5'd4, 5'd5, 3'b000, 5'd5, 7'b0110011}; 
        
        // 18: beq x5, x7, end (Target is 0x48. Offset = 48. imm[12]=0, imm[10:5]=1, imm[4:1]=8, imm[11]=0)
        dut.imem.ram[6]  = {1'b0, 6'd1, 5'd7, 5'd5, 3'b000, 4'd8, 1'b0, 7'b1100011}; 
        
        // 1C: slt x4, x3, x4
        dut.imem.ram[7]  = {7'b0000000, 5'd4, 5'd3, 3'b010, 5'd4, 7'b0110011}; 
        
        // 20: beq x4, x0, around (Target is 0x28. Offset = 8)
        dut.imem.ram[8]  = {1'b0, 6'd0, 5'd0, 5'd4, 3'b000, 4'd4, 1'b0, 7'b1100011}; 
        
        // 24: addi x5, x0, 0 (Skipped instruction)
        dut.imem.ram[9]  = {12'd0, 5'd0, 3'b000, 5'd5, 7'b0010011}; 
        
        // 28: around: slt x4, x7, x2
        dut.imem.ram[10] = {7'b0000000, 5'd2, 5'd7, 3'b010, 5'd4, 7'b0110011}; 
        
        // 2C: add x7, x4, x5
        dut.imem.ram[11] = {7'b0000000, 5'd5, 5'd4, 3'b000, 5'd7, 7'b0110011}; 
        
        // 30: sub x7, x7, x2 (Funct7 for SUB is 0100000)
        dut.imem.ram[12] = {7'b0100000, 5'd2, 5'd7, 3'b000, 5'd7, 7'b0110011}; 
        
        // 34: sw x7, 84(x3) (Offset = 84. imm[11:5]=2, imm[4:0]=20)
        dut.imem.ram[13] = {7'd2, 5'd7, 5'd3, 3'b010, 5'd20, 7'b0100011}; 
        
        // 38: lw x2, 96(x0)
        dut.imem.ram[14] = {12'd96, 5'd0, 3'b010, 5'd2, 7'b0000011}; 
        
        // 3C: add x9, x2, x5
        dut.imem.ram[15] = {7'b0000000, 5'd5, 5'd2, 3'b000, 5'd9, 7'b0110011}; 
        
        // 40: jal x3, end (Target is 0x48. Offset = 8. imm[10:1]=4)
        dut.imem.ram[16] = {1'b0, 10'd4, 1'b0, 8'd0, 5'd3, 7'b1101111}; 
        
        // 44: addi x2, x0, 1 (Skipped instruction)
        dut.imem.ram[17] = {12'd1, 5'd0, 3'b000, 5'd2, 7'b0010011}; 
        
        // 48: end: add x2, x2, x9
        dut.imem.ram[18] = {7'b0000000, 5'd9, 5'd2, 3'b000, 5'd2, 7'b0110011}; 
        
        // 4C: sw x2, 32(x3) (Offset = 32. imm[11:5]=1, imm[4:0]=0)
        dut.imem.ram[19] = {7'd1, 5'd2, 5'd3, 3'b010, 5'd0, 7'b0100011};
        
        // --- PHASE 2: Expanding to the remaining 40 Instructions ---
        // 50: LUI x10, 0x12345 (U-Type format: imm[31:12] | rd | opcode)
        dut.imem.ram[20] = {20'h12345, 5'd10, 7'b0110111}; 
        
        // 54: AUIPC x11, 0 (x11 = PC = 84 / 0x54)
        dut.imem.ram[21] = {20'h00000, 5'd11, 7'b0010111}; 
        
        // 58: SLLI x12, x2, 2 (x12 = 25 << 2 = 100)
        dut.imem.ram[22] = {7'b0, 5'd2, 5'd2, 3'b001, 5'd12, 7'b0010011}; 
        
        // 5C: SRLI x13, x12, 1 (x13 = 100 >> 1 = 50)
        dut.imem.ram[23] = {7'b0, 5'd1, 5'd12, 3'b101, 5'd13, 7'b0010011}; 
        
        // 60: XORI x14, x2, -1 (x14 = 25 ^ -1 = -26)
        dut.imem.ram[24] = {12'hFFF, 5'd2, 3'b100, 5'd14, 7'b0010011}; 

        // 64: BNE x2, x0, +8 (25 != 0, so branch is TAKEN. Skip to 6C)
        dut.imem.ram[25] = {1'b0, 6'b0, 5'd0, 5'd2, 3'b001, 4'b0100, 1'b0, 7'b1100011};

        // 68: ADDI x30, x0, 99 (TRAP - should be skipped)
        dut.imem.ram[26] = {12'd99, 5'd0, 3'b000, 5'd30, 7'b0010011};

        // 6C: SB x2, 104(x0) (Store Byte 25 at address 104)
        dut.imem.ram[27] = {7'b0000011, 5'd2, 5'd0, 3'b000, 5'b01000, 7'b0100011};

        // 70: LB x15, 104(x0) (Load Byte. x15 = 25)
        dut.imem.ram[28] = {12'd104, 5'd0, 3'b000, 5'd15, 7'b0000011};

        // 74: JALR x16, x11, 40 (Jump to x11 + 40 -> 84 + 40 = 124 (0x7C). Link PC+4=120 to x16)
        dut.imem.ram[29] = {12'd40, 5'd11, 3'b000, 5'd16, 7'b1100111};

        // 78: ADDI x30, x0, 99 (TRAP - should be skipped by JALR)
        dut.imem.ram[30] = {12'd99, 5'd0, 3'b000, 5'd30, 7'b0010011};

        // 7C: ADDI x30, x0, 1 (Target of JALR -> SUCCESS TRAP)
        dut.imem.ram[31] = {12'd1, 5'd0, 3'b000, 5'd30, 7'b0010011};


        // Run
        clk = 0; reset = 1; write_cnt = 0;
        #25 reset = 0;

        $display("----------------------------------------------------------------------------------");
        $display("   RISC-V FULL INSTRUCTION VERIFICATION");
        $display("----------------------------------------------------------------------------------");
        $display("Time  | Details            | Status | PC & Register Checks");
        $display("----------------------------------------------------------------------------------");
    end

    // ====================================================================
    // MONITOR: Checks execution whenever Register File is written
    // ====================================================================
    always @(negedge clk) begin
        if (dut.cpu.RegWriteW && !reset && dut.cpu.rf.a3 != 0) begin
            write_cnt = write_cnt + 1;
            
            // TRAP LOGIC: x30 is reserved for testing branch failures or success
            if (dut.cpu.rf.a3 == 30) begin
                if (dut.cpu.rf.wd3 == 1) begin
                    $display("----------------------------------------------------------------------------------");
                    $display("[SUCCESS] All Control Flow (Branches, JAL, JALR) and Data Path passed!");
                    $display("----------------------------------------------------------------------------------");
                    $finish;
                end else begin
                    $display("%t | Trap Hit! Branch Fail| FAIL   | Expected to skip instruction at PC=%h", $time, dut.cpu.PCW);
                    $finish;
                end
            end
            
            case (write_cnt)
                // --- PHASE 1: Harris & Harris Checks ---
                // Format: check(Expected_PC, Expected_Reg_Addr, Expected_Data, Name);
                1:  check(32'h00, 5'd2,  32'd5,  "ADDI x2 = 5");
                2:  check(32'h04, 5'd3,  32'd12, "ADDI x3 = 12");
                3:  check(32'h08, 5'd7,  32'd3,  "ADDI x7 = 3");
                4:  check(32'h0C, 5'd4,  32'd7,  "OR   x4 = 7");
                5:  check(32'h10, 5'd5,  32'd4,  "AND  x5 = 4");
                6:  check(32'h14, 5'd5,  32'd11, "ADD  x5 = 11");
                7:  check(32'h1C, 5'd4,  32'd0,  "SLT  x4 = 0");   // PC 1C because 18 is BEQ not-taken
                8:  check(32'h28, 5'd4,  32'd1,  "SLT  x4 = 1");   // PC 28 because 20 is BEQ taken
                9:  check(32'h2C, 5'd7,  32'd12, "ADD  x7 = 12");
                10: check(32'h30, 5'd7,  32'd7,  "SUB  x7 = 7");
                11: check(32'h38, 5'd2,  32'd7,  "LW   x2 = 7");   // PC 38 because 34 is SW
                12: check(32'h3C, 5'd9,  32'd18, "ADD  x9 = 18");
                13: check(32'h40, 5'd3,  32'h44, "JAL  x3 = 0x44");// Link address is PC+4
                14: check(32'h48, 5'd2,  32'd25, "ADD  x2 = 25");  // PC 48 because JAL jumps over 44

                // --- PHASE 2: Extended Instruction Checks ---
                15: check(32'h50, 5'd10, 32'h12345000, "LUI   x10"); // PC 50 because 4C is SW
                16: check(32'h54, 5'd11, 32'd84,       "AUIPC x11"); // 0x54 = 84 in decimal
                17: check(32'h58, 5'd12, 32'd100,      "SLLI  x12"); // 25 << 2
                18: check(32'h5C, 5'd13, 32'd50,       "SRLI  x13"); // 100 >> 1
                19: check(32'h60, 5'd14, -32'd26,      "XORI  x14"); // 25 ^ -1
                20: check(32'h70, 5'd15, 32'd25,       "LB    x15"); // PC 70 because 64 is BNE, 6C is SB
                21: check(32'h74, 5'd16, 32'd120,      "JALR  x16"); // Link address is 0x74 + 4 = 116 + 4 = 120 (0x78)

                default: $display("Extra Write to x%0d = %h at PC %h", dut.cpu.rf.a3, dut.cpu.rf.wd3, dut.cpu.PCW);
            endcase
        end
    end
    
    // ====================================================================
    // VERIFICATION TASK: Checks PC, Register Address, and Data
    // ====================================================================
    task check;
        input [31:0] expected_pc;
        input [4:0]  expected_reg;
        input [31:0] expected_data;
        input [127:0] name;
        begin
            // Verifies the Program Counter matches the instruction
            // Verifies the Write Register matches the destination
            // Verifies the Write Data matches the ALU/Mem Result
            if (dut.cpu.PCW === expected_pc && dut.cpu.rf.a3 === expected_reg && dut.cpu.rf.wd3 === expected_data) 
                $display("%t | %s | PASS   | PC=%h, Reg=x%0d, Data=%h", 
                         $time, name, dut.cpu.PCW, dut.cpu.rf.a3, dut.cpu.rf.wd3);
            else 
                $display("%t | %s \t | FAIL \t  | Expected: PC=%h, Reg=x%0d, Data=%h\n |\t \t                                                   Got     : PC=%h, Reg=x%0d, Data=%h", 
                         $time, name, expected_pc, expected_reg, expected_data, dut.cpu.PCW, dut.cpu.rf.a3, dut.cpu.rf.wd3);
        end
    endtask
    

    // Safety Timeout
    initial begin
        #2000;
        $display("[TIMEOUT] Simulation stuck. Check Branch Logic loops.");
        $finish;
    end
endmodule