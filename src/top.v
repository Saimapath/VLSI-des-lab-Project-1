module riscv_soc(
    input clk,
    input reset
);
    // Interconnect wires
    wire [31:0]  ImemOut,  WriteDataM, ReadDataM;
    wire [29:0] ALUResultM, PCF; // Added for direct connection to Data Memory
    wire [3:0]  MemWriteM;
    wire        MemEnM;
    wire       iMemEnF;

    // Processor Instance
    riscv_pipelined cpu (
        .clk(clk),
        .reset(reset),
        .PCF_out(PCF),
        .ImemOut(ImemOut),
        .MemWriteM(MemWriteM),
        .iMemEnF(iMemEnF),
        .MemEnM(MemEnM),
        .ALUResultM_out(ALUResultM),
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