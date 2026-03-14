// --- Parameterized Control Unit ---
module controller(
    input  [6:0] op,
    input  [2:0] funct3,
    input        funct7b5,
    output reg   regwrite, 
    output reg [3:0]   memwrite, 
    output reg   jump, branch,zero_for_taken, alusrc,
    output reg [1:0] resultsrc,
    output reg [2:0] immsrc, // Updated to 3 bits for more immediate types
    output reg [3:0] alucontrol,

    output reg jalr, // Added for JALR instruction
    output reg upimm, 
    output reg [2:0] loadbits,
    output reg MemEn

);

    // --- Opcode Parameters ---
    localparam OP_R_TYPE    = 7'b0110011; // R-type
    localparam OP_I_ALU     = 7'b0010011; // I-type ALU
    localparam OP_LW        = 7'b0000011; // Load word
    localparam OP_SW        = 7'b0100011; // Store word
    localparam OP_BEQ       = 7'b1100011; // Branch equal
    localparam OP_JAL       = 7'b1101111; // Jump and link
    localparam OP_LUI       = 7'b0110111; // Load upper immediate
    localparam OP_AUIPC     = 7'b0010111; // Add upper immediate to PC
    localparam OP_JALR      = 7'b1100111; // Jump and link register
    
    // --- Floating Point & CSR Opcodes (F-Extension) ---
    localparam OP_FP_R_TYPE = 7'b1010011; // RVF R-type
    localparam OP_FLW       = 7'b0000111; // Float Load
    localparam OP_FSW       = 7'b0100111; // Float Store
    localparam OP_SYSTEM    = 7'b1110011; // Zicsr / System

    reg [1:0] aluop;

    // RegWrite Decoder
    always @(*) begin
        case(op)
            OP_LW, OP_R_TYPE, OP_I_ALU, OP_JAL, OP_JALR, OP_FP_R_TYPE, OP_FLW, OP_LUI, OP_AUIPC: regwrite = 1'b1;
            default: regwrite = 1'b0;
        endcase
    end

// MemWrite Decoder (Handles sb, sh, sw)
    always @(*) begin
        if (op == OP_SW || op == OP_FSW) begin
            case (funct3)
                3'b000: memwrite = 4'b0001; // sb: Store Byte (1 byte)
                3'b001: memwrite = 4'b0011; // sh: Store Half (2 bytes)
                3'b010: memwrite = 4'b1111; // sw: Store Word (4 bytes)
                default: memwrite = 4'b0000;
            endcase
        end else begin
            memwrite = 4'b0000;
        end
    end

    // Branch Decoder
    always @(*) begin
        case(op)
            OP_BEQ: begin
                 branch = 1'b1;
                 case(funct3)
                    3'b000,3'b101,3'b111: zero_for_taken=1'b1;
                    3'b001,3'b100,3'b110: zero_for_taken=1'b0;
                    default: zero_for_taken=1'b0;
                 endcase
               
            end
            default: begin 
                branch = 1'b0;
                zero_for_taken=1'b0;
            end
        endcase
    end


    // Jump Decoder
    always @(*) begin
        case(op)
            OP_JAL, OP_JALR:  jump = 1'b1;
            default: jump = 1'b0;
        endcase
    end

    // ALUSrc Decoder
    always @(*) begin
        case(op)
            OP_LW, OP_SW, OP_I_ALU, OP_FLW, OP_FSW,OP_JALR: alusrc = 1'b1;
            default: alusrc = 1'b0;
        endcase
    end

    // ImmSrc Decoder
    always @(*) begin
        case(op)
            OP_LW, OP_I_ALU, OP_FLW,OP_JALR: immsrc = 3'b000; // I-type
            OP_SW, OP_FSW:           immsrc = 3'b001; // S-type
            OP_BEQ:                  immsrc = 3'b010; // B-type
            OP_JAL:         immsrc = 3'b011; // J-type
            OP_LUI, OP_AUIPC:        immsrc = 3'b100; // I-type (LUI and AUIPC use imm[31:12] << 12)
            default:                 immsrc = 3'b000;
        endcase
    end

    // ResultSrc Decoder
    always @(*) begin
        case(op)
            OP_LW, OP_FLW: resultsrc = 2'b01; // Data Mem
            OP_JAL, OP_JALR:        resultsrc = 2'b10; // PC + 4
            OP_LUI, OP_AUIPC:        resultsrc = 2'b11; // Immediate (for LUI/AUIPC)
            default:       resultsrc = 2'b00; // ALU Result
        endcase
    end

    // --- ADDED: Jalr Signal Decoder ---
    always @(*) begin
        case(op)
            OP_JALR: jalr = 1'b1;
            default: jalr = 1'b0;
        endcase
    end

    // --- ADDED: Upper Immediate Mode Decoder ---
    always @(*) begin
        case(op)
            OP_LUI:  upimm = 1'b1; // Pure immediate
            default: upimm = 1'b0; // PC + Immediate (AUIPC)
        endcase
    end

    // --- ADDED: Load Byte/Halfword Logic Decoder ---
    always @(*) begin
        loadbits = funct3; // Passes lb, lh, lw, lbu, lhu to mem_extend
    end

    // --- ADDED: Memory Enable Decoder ---
    always @(*) begin
        case(op)
            OP_LW, OP_SW, OP_FLW, OP_FSW: MemEn = 1'b1;
            default: MemEn = 1'b0;
        endcase
    end

    // ALUOp Decoder (Internal)
    always @(*) begin
        case(op)
            OP_LW, OP_SW, OP_FLW, OP_FSW: aluop = 2'b00; // add
            OP_BEQ:                       aluop = 2'b01; // sub
            OP_R_TYPE, OP_I_ALU:          aluop = 2'b10; // funct
            default:                      aluop = 2'b00;
        endcase
    end

    // ALU Control Decoder
    always @(*) begin
        case(aluop)
            2'b00: alucontrol = 4'b0000; // add
            2'b01:case(funct3)
                3'b000, 3'b001: alucontrol = 4'b0001; // sub (for BEQ)
                3'b100, 3'b101: alucontrol = 4'b1000; // slt (for BLT)
                3'b110, 3'b111: alucontrol = 4'b1001; // sltu (for bltu/BGEU)
                default: alucontrol = 4'b0000; // add for other branches
                endcase
            default: case(funct3)
                3'b000: alucontrol = (funct7b5 && op[5]) ? 4'b0001 : 4'b0000; // sub/add
                3'b001: alucontrol = 4'b0101; // sll
                3'b010: alucontrol = 4'b1000; // slt
                3'b011: alucontrol = 4'b1001; // sltu
                3'b100: alucontrol = 4'b0100; // xor
                3'b101: alucontrol = (funct7b5) ? 4'b0111 : 4'b0110; // sra/srl
                3'b110: alucontrol = 4'b0011; // or
                3'b111: alucontrol = 4'b0010; // and
                default: alucontrol = 4'b0000;
            endcase
        endcase
    end
endmodule