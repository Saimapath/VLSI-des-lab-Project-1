module fp16_multiplier (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [2:0]  rm,      // Rounding Mode (from CSR)
    output wire [15:0] result
);

    // =======================================================================
    // STAGE 1: UNPACK & HANDLE ZEROES
    // =======================================================================
    wire a_sign = a[15];
    wire b_sign = b[15];
    wire [4:0] a_exp = a[14:10];
    wire [4:0] b_exp = b[14:10];
    
    // Check for zero inputs (if exponent is 0, we treat it as 0.0)
    wire a_is_zero = (a_exp == 5'd0);
    wire b_is_zero = (b_exp == 5'd0);
    wire result_is_zero = a_is_zero | b_is_zero;

    // Extract mantissas and append the hidden '1'
    wire [10:0] a_mant = a_is_zero ? 11'd0 : {1'b1, a[9:0]};
    wire [10:0] b_mant = b_is_zero ? 11'd0 : {1'b1, b[9:0]};

    // =======================================================================
    // STAGE 2: MULTIPLY & ADD EXPONENTS
    // =======================================================================
    wire o_sign = a_sign ^ b_sign;
    
    // 11-bit x 11-bit multiplication yields a 22-bit product
    // Vivado will map this directly to a DSP48E1 slice
    wire [21:0] raw_product = a_mant * b_mant; 
    
    // Exponent calculation: Exp_A + Exp_B - Bias (15)
    // We use a 7-bit signed wire to easily catch underflow (< 0) or overflow (> 31)
    wire signed [6:0] raw_exp = {2'b00, a_exp} + {2'b00, b_exp} - 7'sd15;

    // =======================================================================
    // STAGE 3: NORMALIZE (Shift & Extract GRS)
    // =======================================================================
    // Since we multiply two normalized numbers (1.x * 1.y), the result can ONLY 
    // be in the range [1.0, 3.99]. This means the hidden '1' is either at bit 20 or 21.
    // We do NOT need a complex Leading Zero Counter!
    
    reg [9:0] norm_frac;
    reg signed [6:0] norm_exp;
    reg G, R, S;

    always @(*) begin
        if (raw_product[21] == 1'b1) begin
            // Result is >= 2.0 (e.g., 10.xxxx...)
            // Shift right by 1, increment exponent
            norm_exp  = raw_exp + 7'sd1;
            norm_frac = raw_product[20:11]; // Top 10 fraction bits
            G         = raw_product[10];
            R         = raw_product[9];
            S         = |raw_product[8:0];  // Sticky is OR of all remaining bits
        end else begin
            // Result is < 2.0 (e.g., 01.xxxx...)
            // No shift needed
            norm_exp  = raw_exp;
            norm_frac = raw_product[19:10];
            G         = raw_product[9];
            R         = raw_product[8];
            S         = |raw_product[7:0];
        end
    end

    // =======================================================================
    // STAGE 4: ROUNDING
    // =======================================================================
    wire L = norm_frac[0];
    reg round_up;

    always @(*) begin
        case (rm)
            3'b000: round_up = (G & (R | S)) | (G & ~R & ~S & L); // RNE
            3'b001: round_up = 1'b0; // RTZ
            3'b010: round_up = o_sign & (G | R | S); // RDN
            3'b011: round_up = ~o_sign & (G | R | S); // RUP
            3'b100: round_up = G; // RMM
            default: round_up = 1'b0;
        endcase
    end

    wire [10:0] rounded_frac = {1'b0, norm_frac} + round_up;

    // =======================================================================
    // STAGE 5: POST-ROUNDING & EXCEPTION HANDLING
    // =======================================================================
    reg [9:0] final_frac;
    reg [4:0] final_exp;

    always @(*) begin
        if (result_is_zero || norm_exp <= 7'sd0) begin
            // Underflow or Zero input -> Return 0.0
            final_exp  = 5'd0;
            final_frac = 10'd0;
        end else if (rounded_frac[10] == 1'b1) begin
            // Post-rounding overflow (e.g., 1.111 rounded up to 10.000)
            if (norm_exp + 7'sd1 >= 7'sd31) begin
                final_exp  = 5'd31; // Infinity
                final_frac = 10'd0;
            end else begin
                final_exp  = norm_exp[4:0] + 5'd1;
                final_frac = 10'd0;
            end
        end else if (norm_exp >= 7'sd31) begin
            // Exponent Overflow -> Return Infinity
            final_exp  = 5'd31;
            final_frac = 10'd0;
        end else begin
            // Normal operation
            final_exp  = norm_exp[4:0];
            final_frac = rounded_frac[9:0];
        end
    end

    // =======================================================================
    // FINAL OUTPUT PACKING
    // =======================================================================
    assign result = {o_sign, final_exp, final_frac};

endmodule