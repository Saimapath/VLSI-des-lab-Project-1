module riscv_soc(
    input clk,
    input reset
);
    // Interconnect wires
    wire [31:0] PCF, InstrF, ALUResultM, WriteDataM, ReadDataM;
    wire [3:0]  MemWriteM;
    wire        MemEnM;

    // Processor Instance
    riscv_pipelined cpu (
        .clk(clk),
        .reset(reset),
        .PCF(PCF),
        .InstrF(InstrF),
        .MemWriteM(MemWriteM),
        .MemEnM(MemEnM),
        .ALUResultM(ALUResultM),
        .WriteDataM(WriteDataM),
        .ReadDataM(ReadDataM)
    );

    // Instruction Memory (BRAM Style)
    bram_imem imem (
        .clk(clk),
        .addr(PCF),
        .dout(InstrF)
    );

    // Data Memory (BRAM Style)
    bram_dmem dmem (
        .clk(clk),
        .en(MemEnM),
        .we(MemWriteM),
        .addr(ALUResultM),
        .din(WriteDataM),
        .dout(ReadDataM)
    );

endmodule