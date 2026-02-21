module rv32i_multicycle_datapath (
    input  clk, reset,
    input  PCWrite, AdrSrc, IRWrite, RegWrite,
    input  [1:0] ResultSrc, ALUSrcA, ALUSrcB, 
    input  [3:0] ALUControl,MemWrite,
    output [6:0] op,
    output [2:0] funct3,ImmSrc,
    output       funct7_5,
    output       zero
);
    reg [31:0] PC, OldPC, Instr, A, B, ALUOut;
    wire [31:0] Adr, ReadData, rd1, rd2, ImmExt, ALUResult, Data;
    reg [31:0] SrcA, SrcB, Result,Dataraw;

    // PC Logic
    always @(posedge clk or posedge reset) begin
        if (reset) PC <= 32'h0;
        else if (PCWrite) PC <= Result;
    end

    assign Adr = AdrSrc ? ALUOut : PC;

    // Instantiate Memory, RegFile, Extend, ALU
    memory_dummy mem_inst (clk, 1'b1, MemWrite, Adr[11:2], B, ReadData);

    extend_mem ext_mem_inst (Dataraw, funct3, Data);

    always @(posedge clk) begin
        if (IRWrite) begin Instr <= ReadData; OldPC <= PC; end
        Dataraw <= ReadData;
    end

    assign {op, funct3, funct7_5} = {Instr[6:0], Instr[14:12], Instr[30]};

    regfile rf (clk, RegWrite, Instr[19:15], Instr[24:20], Instr[11:7], Result, rd1, rd2);
    always @(posedge clk) begin A <= rd1; B <= rd2; end

    extend ext_unit (Instr[31:7], ImmSrc, ImmExt);

    // Muxes
    always @(*) begin
        case(ALUSrcA) 2'b00: SrcA = PC; 2'b01: SrcA = OldPC; default: SrcA = A; endcase
        case(ALUSrcB) 2'b00: SrcB = B; 2'b01: SrcB = ImmExt; default: SrcB = 32'd4; endcase
    end

    rv32i_alu alu_inst (SrcA, SrcB, ALUControl, ALUResult, zero);
    always @(posedge clk) ALUOut <= ALUResult;

    always @(*) begin
        case(ResultSrc) 2'b00: Result = ALUOut; 2'b01: Result = Data; default: Result = ALUResult; endcase
    end
endmodule