module fp_compare (
    input  wire [15:0] a,
    input  wire [15:0] b,
    
    // Outputs for FEQ, FLT, FLE (These go to the Integer Register File!)
    output wire        feq,
    output wire        flt,
    output wire        fle,
    
    // Outputs for FMIN, FMAX (These go to the FP Register File)
    output wire [15:0] fmin,
    output wire [15:0] fmax,
    
    // Output for FCLASS (Goes to Integer Register File)
    output wire [9:0]  a_class 
);

    // =======================================================================
    // 1. EXTRACT FIELDS & IDENTIFY SPECIAL CASES (Zero, Infinity, NaN)
    // =======================================================================
    wire a_sign = a[15];
    wire b_sign = b[15];
    wire [4:0] a_exp = a[14:10];
    wire [4:0] b_exp = b[14:10];
    wire [9:0] a_frac = a[9:0];
    wire [9:0] b_frac = b[9:0];

    wire [14:0] a_mag = a[14:0]; // Magnitude (Exponent + Fraction)
    wire [14:0] b_mag = b[14:0];

    wire a_is_zero = (a_mag == 15'd0);
    wire b_is_zero = (b_mag == 15'd0);
    
    wire a_is_inf  = (a_exp == 5'b11111) && (a_frac == 10'd0);
    wire a_is_nan  = (a_exp == 5'b11111) && (a_frac != 10'd0);
    wire b_is_nan  = (b_exp == 5'b11111) && (b_frac != 10'd0);
    wire has_nan   = a_is_nan | b_is_nan;

    // Canonical Quiet NaN for FP16 (Standard RISC-V behavior)
    localparam CANONICAL_NAN = 16'h7E00;

    // =======================================================================
    // 2. EQUALITY AND LESS-THAN LOGIC (Sign-Magnitude Integer Comparison)
    // =======================================================================
    
    // IEEE 754 Rule: +0.0 is exactly equal to -0.0
    // IEEE 754 Rule: Any comparison with NaN is strictly FALSE
    assign feq = ~has_nan && ( (a_is_zero && b_is_zero) || (a == b) );

    reg a_lt_b;
    always @(*) begin
        if (a_is_zero && b_is_zero) begin
            a_lt_b = 1'b0; // 0 is not less than 0
        end else if (a_sign != b_sign) begin
            a_lt_b = a_sign; // If signs differ, the negative one is smaller
        end else if (a_sign == 1'b0) begin
            a_lt_b = (a_mag < b_mag); // Both positive: smaller magnitude wins
        end else begin
            a_lt_b = (a_mag > b_mag); // Both negative: LARGER magnitude is mathematically smaller
        end
    end

    assign flt = ~has_nan && a_lt_b;
    assign fle = flt | feq;

    // =======================================================================
    // 3. MINIMUM AND MAXIMUM (RISC-V NaN Injection Rules)
    // =======================================================================
    
    // RISC-V Rule: If one input is NaN, return the OTHER input. 
    // If both are NaN, return Canonical NaN.
    // RISC-V Rule for FMIN/FMAX: -0.0 is considered LESS THAN +0.0
    
    assign fmin = (a_is_nan && b_is_nan) ? CANONICAL_NAN :
                  (a_is_nan) ? b :
                  (b_is_nan) ? a :
                  (a_is_zero && b_is_zero) ? (a_sign ? a : b) : // Return the negative zero
                  (a_lt_b) ? a : b;

    assign fmax = (a_is_nan && b_is_nan) ? CANONICAL_NAN :
                  (a_is_nan) ? b :
                  (b_is_nan) ? a :
                  (a_is_zero && b_is_zero) ? (a_sign ? b : a) : // Return the positive zero
                  (a_lt_b) ? b : a;

    // =======================================================================
    // 4. FCLASS INSTRUCTION (Classifies Operand A)
    // =======================================================================
    // Outputs a 10-bit mask to the integer register file representing the type.
    
    wire a_is_subnormal = (a_exp == 5'd0) && (a_frac != 10'd0);
    wire a_is_normal    = (a_exp != 5'd0) && (a_exp != 5'b11111);
    wire a_is_qnan      = a_is_nan && a_frac[9];  // MSB of fraction is 1 for Quiet NaN
    wire a_is_snan      = a_is_nan && ~a_frac[9]; // MSB of fraction is 0 for Signaling NaN
    
    assign a_class[0] = a_sign && a_is_inf;       // -Infinity
    assign a_class[1] = a_sign && a_is_normal;    // -Normal
    assign a_class[2] = a_sign && a_is_subnormal; // -Subnormal
    assign a_class[3] = a_sign && a_is_zero;      // -Zero
    assign a_class[4] = ~a_sign && a_is_zero;     // +Zero
    assign a_class[5] = ~a_sign && a_is_subnormal;// +Subnormal
    assign a_class[6] = ~a_sign && a_is_normal;   // +Normal
    assign a_class[7] = ~a_sign && a_is_inf;      // +Infinity
    assign a_class[8] = a_is_snan;                // Signaling NaN
    assign a_class[9] = a_is_qnan;                // Quiet NaN

endmodule