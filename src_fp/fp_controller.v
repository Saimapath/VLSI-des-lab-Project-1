module fp_controller (
    input  wire [31:0] instr,       // The full 32-bit instruction
    // Output Flags to Main CPU Pipeline
    output reg         fp_alu_en,           // 1 = FPU needs to execute something
    output reg         fp_regwrite,         // 1 = Write result to Floating-Point Regfile (fd)
    output reg         fp_int_regwrite, // 1 = Write result to Integer Regfile (rd)
    output reg         fp_mem_write,        // 1 = FSW (Float Store)
    output reg         fp_mem_read,         // 1 = FLW (Float Load)
    
    // Output Command to the FPU Wrapper
    output reg [4:0]   fpucontrol           // Specific instruction ID for the FPU
);

// =======================================================================
    // 1. EXTRACT INSTRUCTION FIELDS
    // =======================================================================
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] funct5 = instr[31:27]; // Top 5 bits of funct7 (ignores 'fmt')
    wire [4:0] rs2    = instr[24:20]; // Needed to distinguish some conversions

    // --- FPU Control Command Dictionary ---
    localparam FPU_NOP      = 5'd0;
    
    // Fused Multiply-Add Variants
    localparam FPU_FMADD    = 5'd1;  // +(A * B) + C
    localparam FPU_FMSUB    = 5'd2;  // +(A * B) - C
    localparam FPU_FNMSUB   = 5'd3;  // -(A * B) + C
    localparam FPU_FNMADD   = 5'd4;  // -(A * B) - C
    
    // Basic Math
    localparam FPU_FADD     = 5'd5;
    localparam FPU_FSUB     = 5'd6;
    localparam FPU_FMUL     = 5'd7;
    localparam FPU_FDIV     = 5'd8;
    localparam FPU_FSQRT    = 5'd9;
    
    // Sign Injectors
    localparam FPU_FSGNJ    = 5'd10;
    localparam FPU_FSGNJN   = 5'd11;
    localparam FPU_FSGNJX   = 5'd12;
    
    // Min/Max & Comparators
    localparam FPU_FMIN     = 5'd13;
    localparam FPU_FMAX     = 5'd14;
    localparam FPU_FEQ      = 5'd15;
    localparam FPU_FLT      = 5'd16;
    localparam FPU_FLE      = 5'd17;
    
    // Classification & Conversions/Moves
    localparam FPU_FCLASS   = 5'd18;
    localparam FPU_FCVT_W_S = 5'd19; // Float to Int (Signed)
    localparam FPU_FCVT_WU_S= 5'd20; // Float to Int (Unsigned)
    localparam FPU_FCVT_S_W = 5'd21; // Int to Float (Signed)
    localparam FPU_FCVT_S_WU= 5'd22; // Int to Float (Unsigned)
    localparam FPU_FMV_X_W  = 5'd23; // Move Float to Int Reg
    localparam FPU_FMV_W_X  = 5'd24; // Move Int to Float Reg


    // =======================================================================
    // 2. MAIN DECODE LOGIC
    // =======================================================================
    always @(*) begin
        // Default assignments
        fp_alu_en           = 1'b0;
        fp_regwrite         = 1'b0;
        fp_int_regwrite = 1'b0;
        fp_mem_write        = 1'b0;
        fp_mem_read         = 1'b0;
        fpucontrol          = FPU_NOP;

        case (opcode)
            // --------------------------------------------------------
            // Fused Multiply-Add Operations (R4-Type)
            // --------------------------------------------------------
            7'b1000011: begin // FMADD
                fp_alu_en   = 1'b1;
                fp_regwrite = 1'b1;
                fpucontrol  = FPU_FMADD;
            end
            7'b1000111: begin // FMSUB
                fp_alu_en   = 1'b1;
                fp_regwrite = 1'b1;
                fpucontrol  = FPU_FMSUB;
            end
            7'b1001011: begin // FNMSUB
                fp_alu_en   = 1'b1;
                fp_regwrite = 1'b1;
                fpucontrol  = FPU_FNMSUB;
            end
            7'b1001111: begin // FNMADD
                fp_alu_en   = 1'b1;
                fp_regwrite = 1'b1;
                fpucontrol  = FPU_FNMADD;
            end

            // --------------------------------------------------------
            // Standard FP Operations (R-Type)
            // --------------------------------------------------------
            7'b1010011: begin 
                fp_alu_en = 1'b1;
                
                case (funct5)
                 
                    // Math Operations (Write to FD)
                    5'b00000: begin fpucontrol = FPU_FADD;  fp_regwrite = 1'b1; end
                    5'b00001: begin fpucontrol = FPU_FSUB;  fp_regwrite = 1'b1; end
                    5'b00010: begin fpucontrol = FPU_FMUL;  fp_regwrite = 1'b1; end
                    5'b00011: begin fpucontrol = FPU_FDIV;  fp_regwrite = 1'b1; end
                    5'b01011: begin fpucontrol = FPU_FSQRT; fp_regwrite = 1'b1; end
                    
                    // Sign Injection (Write to FD)
                    5'b00100: begin 
                        fp_regwrite = 1'b1;
                        if      (funct3 == 3'b000) fpucontrol = FPU_FSGNJ;
                        else if (funct3 == 3'b001) fpucontrol = FPU_FSGNJN;
                        else if (funct3 == 3'b010) fpucontrol = FPU_FSGNJX;
                    end
                    
                    // Min/Max (Write to FD)
                    5'b00101: begin
                        fp_regwrite = 1'b1;
                        if      (funct3 == 3'b000) fpucontrol = FPU_FMIN;
                        else if (funct3 == 3'b001) fpucontrol = FPU_FMAX;
                    end
                    
                    // Comparators (Write to RD)
                    5'b10100: begin
                        fp_int_regwrite = 1'b1;
                        if      (funct3 == 3'b010) fpucontrol = FPU_FEQ;
                        else if (funct3 == 3'b001) fpucontrol = FPU_FLT;
                        else if (funct3 == 3'b000) fpucontrol = FPU_FLE;
                    end
                    
                    // Classify & Move Float-to-Int (Write to RD)
                    5'b11100: begin
                        fp_int_regwrite = 1'b1;
                        if      (funct3 == 3'b001) fpucontrol = FPU_FCLASS;
                        else if (funct3 == 3'b000) fpucontrol = FPU_FMV_X_W;
                    end
                    
                    // Conversions Float-to-Int (Write to RD)
                    5'b11000: begin
                        fp_int_regwrite = 1'b1;
                        if      (rs2 == 5'b00000) fpucontrol = FPU_FCVT_W_S;
                        else if (rs2 == 5'b00001) fpucontrol = FPU_FCVT_WU_S;
                    end
                    
                    // Conversions Int-to-Float (Write to FD)
                    5'b11010: begin
                        fp_regwrite = 1'b1;
                        if      (rs2 == 5'b00000) fpucontrol = FPU_FCVT_S_W;
                        else if (rs2 == 5'b00001) fpucontrol = FPU_FCVT_S_WU;
                    end
                    
                    // Move Int-to-Float (Write to FD)
                    5'b11110: begin
                        fp_regwrite = 1'b1;
                        if (funct3 == 3'b000) fpucontrol = FPU_FMV_W_X;
                    end
                    
                    default: fpucontrol = FPU_NOP;
                endcase
            end
            
            // --------------------------------------------------------
            // Memory Operations (Loads & Stores)
            // --------------------------------------------------------
            7'b0000111: begin // FLW (Load Float)
                fp_mem_read = 1'b1;
                fp_regwrite = 1'b1;
            end
            
            7'b0100111: begin // FSW (Store Float)
                fp_mem_write = 1'b1;
            end
            
            default: begin
                    // For any non-FP instruction, ensure all control signals are deasserted
                    fp_alu_en           = 1'b0;
                    fp_regwrite         = 1'b0;
                    fp_int_regwrite = 1'b0;
                    fp_mem_write        = 1'b0;
                    fp_mem_read         = 1'b0;
                    fpucontrol          = FPU_NOP;
                // Non-FP instructions fall here and do nothing.
            end
        endcase
    end

endmodule