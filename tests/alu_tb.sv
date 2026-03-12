`timescale 1ns/1ps
`include "../src/alu.v"

module alu_tb;
    logic [31:0] SrcAE, SrcBE;
    logic [3:0]  ALUControlE;
    logic [31:0] ALUResultE;
    logic        ZeroE;

    // Instantiate ALU
    rv32i_alu dut (
        .a(SrcAE), 
        .b(SrcBE), 
        .alu_control(ALUControlE), 
        .result(ALUResultE), 
        .zero(ZeroE)
    );

    // Self-checking Task
    task check_alu(input [31:0] a, input [31:0] b, input [3:0] ctrl, input [31:0] exp, input exp_z);
        begin
            SrcAE = a; SrcBE = b; ALUControlE = ctrl;
            #5; 
            assert(ALUResultE === exp && ZeroE === exp_z)
                else $error("ALU Fail: A=%h, B=%h, Ctrl=%b | Got %h (Z:%b), Exp %h (Z:%b)", 
                            a, b, ctrl, ALUResultE, ZeroE, exp, exp_z);
        end
    endtask

    initial begin
        $display("Starting ALU Test...");
        check_alu(32'd10, 32'd20, 4'b0000, 32'd30, 1'b0); // ADD
        check_alu(32'd30, 32'd10, 4'b0001, 32'd20, 1'b0); // SUB
        check_alu(32'd10, 32'd10, 4'b0001, 32'd0,  1'b1); // SUB (Zero check)
        check_alu(32'hFFFF_FFFF, 32'd1, 4'b1000, 32'd1, 1'b0); // SLT (-1 < 1)
        $display("ALU Test Finished.");
        $finish;
    end
endmodule