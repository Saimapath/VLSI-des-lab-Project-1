module control_unit (
    input  clk,
    input  reset,
    input  [6:0] op,
    input  [2:0] funct3,
    input        funct7_5, // bit 30
    input        zero,     // From ALU for branch logic
    output reg   PCWrite,
    output reg   AdrSrc,
    output reg[3:0]   MemWrite,
    output reg   IRWrite,
    output reg   RegWrite,
    output reg [1:0] ResultSrc,
    output reg [3:0] ALUControl,
    output reg [1:0] ALUSrcB,
    output reg [1:0] ALUSrcA,
    output reg [2:0] ImmSrc
);

    parameter S0_FETCH    = 4'd0,
        S1_DECODE   = 4'd1,
        S2_MEMADR   = 4'd2,
        S3_MEMREAD  = 4'd3,
        S4_MEMWB    = 4'd4,
        S5_MEMWRITE = 4'd5,
        S6_EXECUTER = 4'd6,
        S7_ALUWB    = 4'd7,
        S8_EXECUTEI = 4'd8,
        S9_JAL      = 4'd9,
        S10_BEQ     = 4'd10;

    reg [3:0] current_state, next_state;
    reg [1:0] ALUOp; // Internal signal used for decoding ALUControl

    // State Register
    always @(posedge clk or posedge reset) begin
        if (reset) current_state <= S0_FETCH;
        else       current_state <= next_state;
    end

    // Output and Next State Logic
    always @(*) begin
        // Default values to prevent latches
        {PCWrite, AdrSrc, MemWrite, IRWrite, RegWrite} = 9'b0;
        {ResultSrc, ALUSrcA, ALUSrcB, ALUOp} = 8'b0;
        
        case (current_state)
            S0_FETCH: begin
                AdrSrc = 0;
                IRWrite = 1;
                ALUSrcA = 2'b00;
                ALUSrcB = 2'b10;
                ALUOp = 2'b00;
                ResultSrc = 2'b10;
                PCWrite = 1;
                next_state = S1_DECODE;
            end

            S1_DECODE: begin
                ALUSrcA = 2'b01;
                ALUSrcB = 2'b01;
                ALUOp = 2'b00;

                ResultSrc = 2'b11; 
                RegWrite = (op == 7'b0110111) ? 1'b1 : 1'b0;
                // will use the ALU to calculate branch target, but we won't write back the result, so no need to set ResultSrc or RegWrite
                case (op)
                    7'b0000011, 7'b0100011: next_state = S2_MEMADR;
                    7'b0110011:             next_state = S6_EXECUTER;
                    7'b0010011:             next_state = S8_EXECUTEI;
                    7'b1101111:             next_state = S9_JAL;
                    7'b1100011:             next_state = S10_BEQ;
                    7'b0110111:             next_state = S0_FETCH; // LUI
                    7'b0010111:             next_state = S7_ALUWB; //
                    // add tpu instr?
                    default:                next_state = S0_FETCH;
                endcase
            end

            S2_MEMADR: begin
                ALUSrcA = 2'b10;
                ALUSrcB = 2'b01;
                ALUOp = 2'b00;
                next_state = (op == 7'b0000011) ? S3_MEMREAD : S5_MEMWRITE;
                //it won't reach this state at all if the opc was  smth else
            end

            S3_MEMREAD: begin
                //assertion: this state is only reached for load instructions
                ResultSrc = 2'b00;
                AdrSrc = 1;
                next_state = S4_MEMWB;
            end

            S4_MEMWB: begin
                ResultSrc = 2'b01;
                RegWrite = 1;
                next_state = S0_FETCH;
            end

            S5_MEMWRITE: begin
                //change this to 4 bits if you want to do byte/halfword stores later, but for now we will only do word stores, so we can just set all bits to the same value    
                ResultSrc = 2'b00;
                AdrSrc = 1;
                case (funct3)
                    3'b000: MemWrite = 4'b0001; // SB
                    3'b001: MemWrite = 4'b0011; // SH
                    3'b010: MemWrite = 4'b1111; // SW
                    default: MemWrite = 4'b0000; // For unsupported store types, we won't write to memory
                endcase
                // write data is always from rs2, so no need to set ALUSrcA/B
                next_state = S0_FETCH;
            end

            S6_EXECUTER: begin
                ALUSrcA = 2'b10;
                ALUSrcB = 2'b00;
                ALUOp = 2'b10;
                next_state = S7_ALUWB;
            end

            S8_EXECUTEI: begin
                ALUSrcA = 2'b10;
                ALUSrcB = 2'b01;
                ALUOp = 2'b10;
                next_state = S7_ALUWB;
            end

            S7_ALUWB: begin
                ResultSrc = 2'b00; // LUI writes back to register, others write back from memory
                RegWrite = 1;
                next_state = S0_FETCH;
            end

            S9_JAL: begin
                ALUSrcA = 2'b01;
                ALUSrcB = 2'b10; 
                ALUOp = 2'b00;
                ResultSrc = 2'b00;
                PCWrite = 1;
                next_state = S7_ALUWB;
            end

            S10_BEQ: begin
                ALUSrcA = 2'b10;
                ALUSrcB = 2'b00;
                ALUOp = 2'b01;
                ResultSrc = 2'b00; // from last state's ALU result, which is branch target calculation
                if(funct3 == 3'b000 || funct3 == 3'b101 || funct3 == 3'b111) PCWrite = zero;
                else if (funct3 == 3'b001 || funct3 == 3'b110 || funct3 == 3'b100) PCWrite = ~zero;
                else PCWrite = 1'b0; // For unsupported branch types, we won't take the branch
                next_state = S0_FETCH;
            end
        endcase
    end

    // ALU Decoder (Maps ALUOp to specific control signals)
// Updated ALU Decoder (4-bit Output)
    // Requires: input [6:0] op (specifically op[5]) to distinguish R-type vs I-type
    
    always @(*) begin
        case (ALUOp)
            2'b00: ALUControl = 4'b0000; // LW, SW -> Addition
            2'b01: begin
                case (funct3)
                    3'b000,3'b001: ALUControl = 4'b0001; // BEQ -> Subtraction
                    3'b100,3'b101: ALUControl = 4'b1000; // ble / bge -> slt / slt (same as BEQ, but we will use the zero flag differently in the control unit)
                    3'b110,3'b111: ALUControl = 4'b1001; // bge -> sltu (same as BEQ, but we will use the zero flag differently in the control unit)
                    default: ALUControl = 4'b0000; // For other branch types, we can default to addition for target calculation
                endcase
            end

            default: begin // ALUOp = 2'b10 (R-Type and I-Type ALU instructions)
                case (funct3)
                    // ADD / SUB / ADDI
                    // Only subtract if it is R-type (op[5]=1) AND bit 30 is set.
                    // ADDI (op[5]=0) always adds.
                    3'b000: begin
                        if (funct7_5 && op[5]) ALUControl = 4'b0001; // SUB
                        else                   ALUControl = 4'b0000; // ADD / ADDI
                    end
                    
                    // SLL / SLLI (Shift Left Logical)
                    3'b001: ALUControl = 4'b0101; 
                    
                    // SLT / SLTI (Set Less Than Signed)
                    3'b010: ALUControl = 4'b1000; 
                    
                    // SLTU / SLTIU (Set Less Than Unsigned)
                    3'b011: ALUControl = 4'b1001; 
                    
                    // XOR / XORI
                    3'b100: ALUControl = 4'b0100; 
                    
                    // SRL / SRA / SRLI / SRAI
                    // Both R-type and I-type shifts use funct7_5 to distinguish Logical/Arithmetic
                    3'b101: begin
                        if (funct7_5) ALUControl = 4'b0111; // SRA / SRAI
                        else          ALUControl = 4'b0110; // SRL / SRLI
                    end
                    
                    // OR / ORI
                    3'b110: ALUControl = 4'b0011; 
                    
                    3'b111: ALUControl = 4'b0010; 
                    
                    default: ALUControl = 4'b0000;
                endcase
            end
        endcase
    end


    // ImmSrc Decoder (Based on opcode)
    always @(*) begin
        case (op)
            7'b0010011, 7'b0000011: ImmSrc = 3'b000; // I-type / Load
            7'b0100011:             ImmSrc = 3'b001; // S-type (Store)
            7'b1100011:             ImmSrc = 3'b010; // B-type (Branch)
            7'b1101111:             ImmSrc = 3'b011; // J-type (JAL)
            7'b0110111, 7'b0010111: ImmSrc = 3'b100; // U-type (LUI/AUIPC) - using a custom code to indicate zero-extension
            default:                ImmSrc = 3'b000;
        endcase
    end

endmodule