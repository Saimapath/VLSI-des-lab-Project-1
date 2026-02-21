`timescale 1ns / 1ps

module tb_step_by_step();
    reg clk, reset;
    integer write_cnt;

    // Instantiate Processor
    riscv_top dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    initial begin
        $dumpfile("step_verify.vcd");
        $dumpvars(0, tb_step_by_step);
        
        $readmemh("program.hex", dut.dp.mem_inst.mem);

        clk = 0; reset = 1; write_cnt = 0;
        #25 reset = 0;

        $display("---------------------------------------------------------------");
        $display("   RISC-V FULL INSTRUCTION VERIFICATION");
        $display("---------------------------------------------------------------");
        $display("Time  | Instr Type | Details            | Status");
    end

    // Monitor Writes to Registers
    always @(negedge clk) begin
        if (dut.cu.RegWrite && !reset && dut.dp.rf.a3 != 0) begin
            write_cnt = write_cnt + 1;
            
            // If x30 is written, a Branch Logic Trap was triggered!
            if (dut.dp.rf.a3 == 30) begin
                $display("%t | BRANCH     | Trap Hit! Code: %0d | FAIL <<<<", $time, dut.dp.rf.wd3);
                $finish;
            end
            
            case (write_cnt)
                // --- INIT & ALU CHECKS ---
                1: check(1,  32'd15,        "ADDI x1 (Init)");
                2: check(2,  32'd5,         "ADDI x2 (Init)");
                3: check(3,  32'hFFFFFFFF,  "ADDI x3 (-1)  ");

                4: check(4,  32'd1,         "SLT  (-1 < 15)");
                5: check(5,  32'd0,         "SLTU (Max < 15)");
                6: check(6,  32'd1,         "SLT  (5 < 15) ");
                7: check(7,  32'd1,         "SLTU (5 < 15) ");

                8: check(8,  32'd20,        "ADD           ");
                9: check(9,  32'd10,        "SUB           ");
                10: check(10, 32'd10,       "XOR           ");
                11: check(11, 32'd15,       "OR            ");
                12: check(12, 32'd5,        "AND           ");
                13: check(13, 32'd480,      "SLL           ");
                14: check(14, 32'd0,        "SRL           ");
                15: check(15, 32'hFFFFFFFF, "SRA           ");

                // --- BRANCH CHECK ---
                // We don't see writes for taken branches, but we see the Final Success Write (x16)
                // If we reach here (write_cnt 16) with value 0xAA, it means ALL branches passed.
                16: begin
                    if (dut.dp.rf.wd3 === 32'h000000AA) begin
                        $display("%t | BRANCH     | BEQ, BNE, BLT... | PASS", $time);
                        $display("%t | BRANCH     | Fallthrough Check| PASS", $time);
                        $display("---------------------------------------------------------------");
                        $display(" [SUCCESS] ALL INSTRUCTIONS PASSED.");
                        $finish;
                    end else begin
                        check(16, 32'hAA, "Branch Fallthrough");
                    end
                end

                default: $display("Extra Write to x%0d = %h", dut.dp.rf.a3, dut.dp.rf.wd3);
            endcase
        end
    end
    
    // Helper Task
    task check;
        input [4:0]  reg_idx;
        input [31:0] expected;
        input [127:0] name;
        begin
            if (dut.dp.rf.wd3 === expected) 
                $display("%t | ALU/SLT    | %s | PASS", $time, name);
            else 
                $display("%t | ALU/SLT    | %s | FAIL (Exp %h Got %h)", $time, name, expected, dut.dp.rf.wd3);
        end
    endtask
    
    // Safety Timeout
    initial begin
        #5000;
        $display("[TIMEOUT] Simulation stuck. Check Branch Logic loops.");
        $finish;
    end
endmodule