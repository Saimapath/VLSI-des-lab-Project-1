`timescale 1ns/1ps
`include "../src/controller.v"

module controller_tb;
    // --- Named Constants for Readability ---
    // Opcodes
    localparam [6:0] OP_R_TYPE = 7'b0110011;
    localparam [6:0] OP_I_ALU  = 7'b0010011;
    localparam [6:0] OP_LW     = 7'b0000011;
    localparam [6:0] OP_SW     = 7'b0100011;
    localparam [6:0] OP_BEQ    = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;

    // ALU Control Signals (Matching your rv32i_alu)
    localparam [3:0] ALU_ADD  = 4'b0000;
    localparam [3:0] ALU_SUB  = 4'b0001;
    localparam [3:0] ALU_AND  = 4'b0010;
    localparam [3:0] ALU_OR   = 4'b0011;
    localparam [3:0] ALU_SLT  = 4'b1000;

    // ResultSrc Selectors
    localparam [1:0] RES_ALU  = 2'b00;
    localparam [1:0] RES_MEM  = 2'b01;
    localparam [1:0] RES_PC4  = 2'b10;
    localparam [1:0] RES_IMM  = 2'b11;

    // Logic Constants
    localparam HIGH = 1'b1;
    localparam LOW  = 1'b0;

    // --- Signals ---
    logic [6:0] op;
    logic [2:0] funct3;
    logic       funct7b5;
    logic       RegWriteD, MemWriteD, JumpD, BranchD, ALUSrcD;
    logic [1:0] ResultSrcD;
    logic [2:0] ImmSrcD;
    logic [3:0] ALUControlD;

    // Instantiate Controller
    controller dut (.*);
    // In SystemVerilog, the .* syntax is called Wildcard Named Port Connection.

    // It is a shorthand that automatically connects ports of a module instance to 
    // signals in the testbench (or parent module) that have the exact same name and bit-width.

    // --- Golden Model Task ---
    task check(
        input string name, 
        input [6:0]  i_op, input [2:0] f3, input f7,
        input rw, input mw, input j, input b, input asrc, 
        input [1:0] rsrc, input [3:0] alu
    );
        begin
            op = i_op; funct3 = f3; funct7b5 = f7;
            #5;
            if (RegWriteD !== rw || MemWriteD !== mw || JumpD !== j || 
                BranchD !== b || ALUSrcD !== asrc || ResultSrcD !== rsrc || 
                ALUControlD !== alu) begin
                $display("FAIL [%s] | RW:%b MW:%b J:%b B:%b AS:%b RS:%b ALU:%b", 
                          name, RegWriteD, MemWriteD, JumpD, BranchD, ALUSrcD, ResultSrcD, ALUControlD);
            end else begin
                $display("PASS [%s]", name);
            end
        end
    endtask

    initial begin
        $display("--- Starting Named Constant Controller Test ---");

        // Format: Name, Opcode, f3, f7, RegW, MemW, Jump, Branch, ALUSrc, ResultSrc, ALUControl
        
        // R-TYPE
        check("ADD",  OP_R_TYPE, 3'b000, LOW,  HIGH, LOW,  LOW,  LOW,  LOW,  RES_ALU, ALU_ADD);
        check("SUB",  OP_R_TYPE, 3'b000, HIGH, HIGH, LOW,  LOW,  LOW,  LOW,  RES_ALU, ALU_SUB);
        check("SLT",  OP_R_TYPE, 3'b010, LOW,  HIGH, LOW,  LOW,  LOW,  LOW,  RES_ALU, ALU_SLT);

        // I-TYPE & LOADS
        check("ADDI", OP_I_ALU,  3'b000, LOW,  HIGH, LOW,  LOW,  LOW,  HIGH, RES_ALU, ALU_ADD);
        check("LW",   OP_LW,     3'b010, LOW,  HIGH, LOW,  LOW,  LOW,  HIGH, RES_MEM, ALU_ADD);

        // STORES
        check("SW",   OP_SW,     3'b010, LOW,  LOW,  HIGH, LOW,  LOW,  HIGH, RES_ALU, ALU_ADD);

        // BRANCHES (Uses SUB to set zero flag)
        check("BEQ",  OP_BEQ,    3'b000, LOW,  LOW,  LOW,  LOW,  HIGH, LOW,  RES_ALU, ALU_SUB);

        // JUMPS & SPECIALS
        check("JAL",  OP_JAL,    3'b000, LOW,  HIGH, LOW,  HIGH, LOW,  LOW,  RES_PC4, ALU_ADD);
        check("LUI",  OP_LUI,    3'b000, LOW,  HIGH, LOW,  LOW,  LOW,  LOW,  RES_IMM, ALU_ADD);

        $display("--- Controller Test Complete ---");
        $finish;
    end
endmodule