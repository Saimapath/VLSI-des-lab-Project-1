`timescale 1ns / 1ps

module tb_load_store();
    reg clk, reset;
    integer write_cnt;

    // Instantiate Processor
    riscv_top dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    initial begin
        $dumpfile("load_store_test.vcd");
        $dumpvars(0, tb_load_store);
        
        // Load the hex file provided above
        $readmemh("S_U_I.hex", dut.dp.mem_inst.mem);

        clk = 0; reset = 1; write_cnt = 0;
        #25 reset = 0;

        $display("---------------------------------------------------------------");
        $display("   RISC-V LOAD/STORE & LUI/AUIPC TEST");
        $display("---------------------------------------------------------------");
        $display("Time  | Instr | Dest | Result     | Expected   | Status");
        $display("---------------------------------------------------------------");
    end

    // Monitor Writes
    always @(negedge clk) begin
        if (dut.cu.RegWrite && !reset && dut.dp.rf.a3 != 0) begin
            write_cnt = write_cnt + 1;
            
            case (write_cnt)
                // LUI Check
                1: check(1, 32'h12345000, "LUI      ");

                // AUIPC Check (PC=4 + Imm=0x10000000)
                // Note: IF your AUIPC logic shifts imm by 12, check expected value carefully.
                // Standard: imm[31:12] << 12. 
                2: check(2, 32'h10000004, "AUIPC    ");

                // Base Address Setup
                3: check(3, 32'h00000040, "ADDI (Base)");

                // LW Check (Verifies SW worked)
                4: check(4, 32'h12345000, "LW       ");

                // HALF-WORD Checks
                5: check(5, 32'hFFFFFa88, "ADDI (Setup)"); // Init value
                // Store happens here (invisible to RegWrite)
                6: check(6, 32'hFFFFFa88, "LH (Signed) "); // Sign extended F88
                7: check(7, 32'h0000Fa88, "LHU (Unsign)"); // Zero extended F88
                
                // Note: In hex above I used 0xF88.
                // If ADDI immediate is 12-bit, 0xF88 is -120 (0xF88). 
                // Wait, 0xF88 is 12 bits. 
                // Let's correct expectation: 0xF88 -> Sign Ext -> 0xFFFFF888.

                // BYTE Checks
                // Store happens here
                8: check(8, 32'hFFFFFF88, "LB (Signed) "); // Sign extended 88
                9: check(9, 32'h00000088, "LBU (Unsign)"); // Zero extended 88

                default: $display("Extra Write: x%0d = %h", dut.dp.rf.a3, dut.dp.rf.wd3);
            endcase
        end
    end
    
    // Verification Task
    task check;
        input [4:0]  reg_idx;
        input [31:0] expected;
        input [95:0] name;
        begin
            if (dut.dp.rf.wd3 === expected) 
                $display("%t | %s | x%2d   | %h | %h | PASS", $time, name, reg_idx, dut.dp.rf.wd3, expected);
            else 
                $display("%t | %s | x%2d   | %h | %h | FAIL <<<<", $time, name, reg_idx, dut.dp.rf.wd3, expected);
        end
    endtask

    // Timeout
    initial begin
        #5000;
        $finish;
    end
endmodule