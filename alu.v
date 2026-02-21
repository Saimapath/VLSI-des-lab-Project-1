module rv32i_alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  alu_control,
    output reg [31:0] result,
    output        zero
);

    wire [4:0] shamt = b[4:0];

    // 1. Explicitly calculate comparisons OUTSIDE the always block
    // This forces Verilog to respect the signedness.
    wire signed [31:0] a_signed = a;
    wire signed [31:0] b_signed = b;
    
    wire slt_res  = (a_signed < b_signed); // Signed Comparison
    wire sltu_res = (a < b);               // Unsigned Comparison

    always @(*) begin
        case (alu_control)
            // Arithmetic
            4'b0000: result = a + b;         // ADD
            4'b0001: result = a - b;         // SUB
            
            // Logic
            4'b0010: result = a & b;         // AND
            4'b0011: result = a | b;         // OR
            4'b0100: result = a ^ b;         // XOR
            
            // Shifts
            4'b0101: result = a << shamt;              // SLL
            4'b0110: result = a >> shamt;              // SRL
            4'b0111: result = $signed(a) >>> shamt;    // SRA
            
            // Comparisons - Use the pre-calculated wires!
            4'b1000: result = {31'b0, slt_res};        // SLT
            4'b1001: result = {31'b0, sltu_res};       // SLTU
            
            default: result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);

endmodule