module rv32i_alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  alu_control,
    output [31:0] result,
    output        zero
);

    wire [4:0] shamt = b[4:0];

    // --- 1. SHARED ARITHMETIC CORE ---
    // Instead of two separate adders, we use one and invert 'b' for subtraction.
    // This halves the area and reduces the routing complexity to the final MUX.
    wire is_sub = (alu_control == 4'b0001);
    wire [31:0] b_inv = is_sub ? ~b : b;
    wire [31:0] sum_res = a + b_inv + is_sub;

    // --- 2. PARALLEL PRE-COMPUTATION ---
    // Calculate EVERYTHING simultaneously so the router doesn't have to wait.
    wire signed [31:0] a_signed = a;
    wire signed [31:0] b_signed = b;
    
    wire slt_res  = (a_signed < b_signed); 
    wire sltu_res = (a < b);               
    
    wire [31:0] and_res = a & b;
    wire [31:0] or_res  = a | b;
    wire [31:0] xor_res = a ^ b;
    
    wire [31:0] sll_res = a << shamt;
    wire [31:0] srl_res = a >> shamt;
    wire [31:0] sra_res = $signed(a) >>> shamt;

    // --- 3. FLATTENED FINAL MUX ---
    // Because everything is pre-calculated, this becomes a very shallow LUT tree.
    reg [31:0] res_comb;
    always @(*) begin
        case (alu_control)
            4'b0000: res_comb = sum_res;             // ADD
            4'b0001: res_comb = sum_res;             // SUB
            4'b0010: res_comb = and_res;             // AND
            4'b0011: res_comb = or_res;              // OR
            4'b0100: res_comb = xor_res;             // XOR
            4'b0101: res_comb = sll_res;             // SLL
            4'b0110: res_comb = srl_res;             // SRL
            4'b0111: res_comb = sra_res;             // SRA
            4'b1000: res_comb = {31'b0, slt_res};    // SLT
            4'b1001: res_comb = {31'b0, sltu_res};   // SLTU
            default: res_comb = 32'b0;
        endcase
    end

    assign result = res_comb;
    assign zero = (res_comb == 32'b0);

endmodule