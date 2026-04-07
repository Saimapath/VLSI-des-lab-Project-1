module riscv_soc(
    input clk,
    input reset
);
    // Interconnect wires
    wire [31:0] PCF, ImemOut, ALUResultM, WriteDataM, ReadDataM;
    wire [3:0]  MemWriteM;
    wire        MemEnM;
    wire       iMemEnF;

    // Processor Instance
    riscv_pipelined cpu (
        .clk(clk),
        .reset(reset),
        .PCF(PCF),
        .ImemOut(ImemOut),
        .MemWriteM(MemWriteM),
        .iMemEnF(iMemEnF),
        .MemEnM(MemEnM),
        .ALUResultM(ALUResultM),
        .WriteDataM(WriteDataM),
        .ReadDataM(ReadDataM)
    );

    // Instruction Memory (BRAM Style)
    bram_imem imem (
        .clk(clk),
        .addr(PCF),
        .dout(ImemOut),
        .en(iMemEnF) // Enable signal from CPU
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