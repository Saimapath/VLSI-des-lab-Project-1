module riscv_top (
    input  wire clk,
    input  wire reset
);

    // Internal Wires for Control Signals
    wire PCWrite, AdrSrc, IRWrite, RegWrite, zero;
    wire [1:0] ResultSrc, ALUSrcA, ALUSrcB ;
    wire [3:0] ALUControl, MemWrite;
    wire [6:0] op;
    wire [2:0] funct3,ImmSrc;
    wire       funct7_5;

    // Control Unit Instance
    control_unit cu (
        .clk(clk), .reset(reset), .op(op), .funct3(funct3), 
        .funct7_5(funct7_5), .zero(zero), .PCWrite(PCWrite), 
        .AdrSrc(AdrSrc), .MemWrite(MemWrite), .IRWrite(IRWrite), 
        .RegWrite(RegWrite), .ResultSrc(ResultSrc), .ALUControl(ALUControl), 
        .ALUSrcB(ALUSrcB), .ALUSrcA(ALUSrcA), .ImmSrc(ImmSrc)
    );

    // Datapath Instance
    rv32i_multicycle_datapath dp (
        .clk(clk), .reset(reset), .PCWrite(PCWrite), .AdrSrc(AdrSrc), 
        .MemWrite(MemWrite), .IRWrite(IRWrite), .RegWrite(RegWrite), 
        .ResultSrc(ResultSrc), .ALUSrcA(ALUSrcA), .ALUSrcB(ALUSrcB), 
        .ImmSrc(ImmSrc), .ALUControl(ALUControl), .op(op), 
        .funct3(funct3), .funct7_5(funct7_5), .zero(zero)
    );

endmodule