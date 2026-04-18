// --- Merged Parameterized Control Unit ---
module controller(
    input  [6:0] op,
    input  [2:0] funct3,
    input  [6:0] funct7,   
    input  [11:0] imm,        // Added to decode mret (Instr[31:20])
    
    output reg   is_mret,     // Signal to trigger return to mepc       
    output reg   regwrite, 
    output reg [3:0]   memwrite, 
    output reg   jump, branch, zero_for_taken, alusrc,
    output reg [1:0] resultsrc,
    output reg [2:0] immsrc, 
    output reg [3:0] alucontrol,

    output reg jalr, 
    output reg upimm, 
    output reg [2:0] loadbits,
    output reg MemEn,
    output reg dma_mac_en,     // DMA trigger

    // ---> ADDED: CSR and Multiplier Control Signals
    output reg       csr,
    output reg [1:0] csr_ctrl,
    output reg       MultStart,
    output reg [1:0] Multcontrol
);

    wire funct7b5 = funct7[5];
    wire funct7b0 = funct7[0]; // Needed for Multiplier decode

    // --- Opcode Parameters ---
    localparam OP_R_TYPE    = 7'b0110011; 
    localparam OP_I_ALU     = 7'b0010011; 
    localparam OP_LW        = 7'b0000011; 
    localparam OP_SW        = 7'b0100011; 
    localparam OP_BEQ       = 7'b1100011; 
    localparam OP_JAL       = 7'b1101111; 
    localparam OP_LUI       = 7'b0110111; 
    localparam OP_AUIPC     = 7'b0010111; 
    localparam OP_JALR      = 7'b1100111; 
    
    // Extensions
    localparam OP_FP_R_TYPE = 7'b1010011; 
    localparam OP_FLW       = 7'b0000111; 
    localparam OP_FSW       = 7'b0100111; 
    localparam OP_I_CSR     = 7'b1110011; // ---> ADDED: CSR Opcode

    reg [1:0] aluop;

       always @(*) begin
        if ((op == OP_I_CSR) && (funct3 == 3'b000) && (imm == 12'h302)) 
            is_mret = 1'b1; 
        else 
            is_mret = 1'b0;
    end


    // RegWrite Decoder (Added OP_I_CSR)
    always @(*) begin
        case(op)
            OP_LW, OP_R_TYPE, OP_I_ALU, OP_JAL, OP_JALR, OP_LUI, OP_AUIPC: regwrite = 1'b1;
            OP_I_CSR: regwrite = (funct3 != 3'b000); 
            default: regwrite = 1'b0;
        endcase
    end

    // MemWrite Decoder
    always @(*) begin
        if (op == OP_SW || op == OP_FSW) begin
            case (funct3)
                3'b000: memwrite = 4'b0001;
                3'b001: memwrite = 4'b0011;
                3'b010: memwrite = 4'b1111;
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
            OP_LW, OP_SW, OP_I_ALU, OP_FLW, OP_FSW, OP_JALR: alusrc = 1'b1;
            default: alusrc = 1'b0;
        endcase
    end

    // ImmSrc Decoder
    always @(*) begin
        case(op)
            OP_LW, OP_I_ALU, OP_FLW, OP_JALR: immsrc = 3'b000;
            OP_SW, OP_FSW:                    immsrc = 3'b001;
            OP_BEQ:                           immsrc = 3'b010;
            OP_JAL:                           immsrc = 3'b011;
            OP_LUI, OP_AUIPC:                 immsrc = 3'b100;
            default:                          immsrc = 3'b000;
        endcase
    end

    // ResultSrc Decoder
    always @(*) begin
        case(op)
            OP_LW, OP_FLW:           resultsrc = 2'b01; // Data Mem
            OP_JAL, OP_JALR:         resultsrc = 2'b10; // PC + 4
            OP_LUI, OP_AUIPC:        resultsrc = 2'b11; // Immediate
            default:                 resultsrc = 2'b00; // ALU Result
        endcase
    end

    // --- ADDED: CSR Decoders ---
    always @(*) begin
        case(op)
            OP_I_CSR: csr = (funct3 != 3'b000); 
            default:  csr = 1'b0;
        endcase
    end
    always @(*) begin
        csr_ctrl = funct3[1:0];
    end

    // Other Single-Bit Decoders
    always @(*) begin
        case(op)
            OP_JALR: jalr = 1'b1;
            default: jalr = 1'b0;
        endcase
    end
    always @(*) begin
        case(op)
            OP_LUI:  upimm = 1'b1;
            default: upimm = 1'b0;
        endcase
    end
    always @(*) begin
        loadbits = funct3;
    end
    always @(*) begin
        case(op)
            OP_LW, OP_SW, OP_FLW, OP_FSW: MemEn = 1'b1;
            default: MemEn = 1'b0;
        endcase
    end

    // ALUOp Decoder (Internal)
    always @(*) begin
        case(op)
            OP_LW, OP_SW, OP_FLW, OP_FSW: aluop = 2'b00;
            OP_BEQ:                       aluop = 2'b01;
            OP_R_TYPE, OP_I_ALU:          aluop = 2'b10;
            default:                      aluop = 2'b00;
        endcase
    end

    // ALU Control Decoder
    always @(*) begin
        case(aluop)
            2'b00: alucontrol = 4'b0000; // add
            2'b01:case(funct3)
                3'b000, 3'b001: alucontrol = 4'b0001; // sub
                3'b100, 3'b101: alucontrol = 4'b1000; // slt
                3'b110, 3'b111: alucontrol = 4'b1001; // sltu
                default: alucontrol = 4'b0000;
                endcase
            default: case(funct3)
                3'b000: alucontrol = (funct7b5 && op[5]) ? 4'b0001 : 4'b0000; 
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

    // DMA MATMAC Decoder
    always @(*) begin
        if (op == 7'b0001011 && funct3 == 3'b000 && funct7 == 7'b0000001) begin
            dma_mac_en = 1'b1;
        end else begin
            dma_mac_en = 1'b0;
        end
    end

    // ---> ADDED: Multiplier Decode Logic
    always @(*) begin
        Multcontrol = funct3[1:0];
        // Multiplier instructions share OP_R_TYPE but have funct7[0] = 1
        if ((op == OP_R_TYPE) && (funct7b0 == 1'b1)) 
            MultStart = 1'b1;
        else 
            MultStart = 1'b0;
    end
endmodule