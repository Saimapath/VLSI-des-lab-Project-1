`timescale 1ns / 1ps

module tb_fpga_riscv_final();
    reg sys_clock;
    reg reset_rtl;
    wire [3:0] mem;
    integer write_cnt = 0;
    
    `define CPU_PATH dut.fpga_riscv_i.riscv_pipelined_0.inst
    `define CPU_CLK  dut.fpga_riscv_i.clk_wiz.clk_out1
    `define CPU_RSTN dut.fpga_riscv_i.rst_clk_wiz_100M.peripheral_aresetn

    fpga_riscv_wrapper dut (
        .sys_clock(sys_clock),
        .reset_rtl(reset_rtl),
        .MemWriteM(mem)
    );

    always #4 sys_clock = ~sys_clock;

    initial begin
        sys_clock = 0;
        reset_rtl = 1; 
        write_cnt = 0;
        
        $display("------------------------------------------------------------------");
        $display("   M-EXTENSION STANDALONE VERIFICATION");
        $display("------------------------------------------------------------------");

        #100;
        reset_rtl = 0;
        wait (dut.fpga_riscv_i.clk_wiz.locked === 1'b1);
    end

    always @(negedge `CPU_CLK) begin
        // Match the reference condition: RegWrite is high, not in reset, not x0
        if (`CPU_PATH.RegWriteW && (`CPU_RSTN === 1'b1) && `CPU_PATH.rf.a3 != 0) begin
            write_cnt = write_cnt + 1;
            
            case (write_cnt)
                // Using your new COE instruction values (13, 10, -1, 2)
                1:  check(32'h00, 5'd2,  32'd13,        "ADDI x2=13");
                2:  check(32'h04, 5'd3,  32'd10,        "ADDI x3=10");
                3:  check(32'h08, 5'd4,  32'hFFFFFFFF,  "ADDI x4=-1");
                4:  check(32'h0C, 5'd5,  32'd2,         "ADDI x5=2");
                
                // Multiplication Logic
                5:  check(32'h10, 5'd10, 32'd130,       "MUL (Signed Low)");
                6:  check(32'h14, 5'd11, 32'd0,         "MULH (Signed High)");
                7:  check(32'h18, 5'd12, 32'hFFFFFFFF,  "MULHSU (S*U High)");
                8:  check(32'h1C, 5'd13, 32'd1,         "MULHU (U*U High)");
                
                // Final Handoff
                9:  begin
                    check(32'h20, 5'd14, 32'hFFFFFFFF,  "SUB Dependency Check");
                    $display("------------------------------------------------------------------");
                    $display("[SUCCESS] M-Extension Verified!");
                    $display("------------------------------------------------------------------");
                    $finish;
                end
                default: $display("Extra Write: PC=%h x%0d=%h", `CPU_PATH.PCW, `CPU_PATH.rf.a3, `CPU_PATH.rf.wd3);
            endcase
        end
    end
    
    task check;
        input [31:0] expected_pc;
        input [4:0]  expected_reg;
        input [31:0] expected_data;
        input [127:0] name;
        begin
            if (`CPU_PATH.PCW === expected_pc && `CPU_PATH.rf.a3 === expected_reg && `CPU_PATH.rf.wd3 === expected_data) 
                $display("%t | %s | PASS | PC=%h, Reg=x%0d, Data=%h", $time, name, `CPU_PATH.PCW, `CPU_PATH.rf.a3, `CPU_PATH.rf.wd3);
            else begin
                $display("%t | %s | FAIL | Expected: PC=%h, Reg=x%0d, Data=%h", $time, name, expected_pc, expected_reg, expected_data);
                $display("                     | Got     : PC=%h, Reg=x%0d, Data=%h", `CPU_PATH.PCW, `CPU_PATH.rf.a3, `CPU_PATH.rf.wd3);
                $finish;
            end
        end
    endtask

    initial begin #20000; $finish; end
endmodule