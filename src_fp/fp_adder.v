module fp_adder_sub (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        add_sub, // 0 for addition, 1 for subtraction
    input  wire [2:0]  rm,      // Rounding Mode (from CSR)
    output wire [15:0] result
);

    // =======================================================================
    // OPTIMIZATION 1 & 2: Integer Compare and Early Swap
    // =======================================================================
    // Fast magnitude compare (ignores sign bit)
    wire a_is_larger = (a[14:0] >= b[14:0]);

    // Route to Larger (L) and Smaller (S)
    wire [14:0] L_abs = a_is_larger ? a[14:0] : b[14:0];
    wire [14:0] S_abs = a_is_larger ? b[14:0] : a[14:0];
    wire L_sign       = a_is_larger ? a[15]   : b[15];
    wire S_sign       = a_is_larger ? b[15]   : a[15];

    wire [4:0] L_exp = L_abs[14:10];
    wire [4:0] S_exp = S_abs[14:10];

    // Inject hidden bits ONLY once they are sorted
    wire [10:0] L_mant = (L_exp == 0) ? {1'b0, L_abs[9:0]} : {1'b1, L_abs[9:0]};
    wire [10:0] S_mant = (S_exp == 0) ? {1'b0, S_abs[9:0]} : {1'b1, S_abs[9:0]};

    // =======================================================================
    // OPTIMIZATION 3 & 4: Single Subtractor and Sign Collapse
    // =======================================================================
    // Since L >= S, this is ALWAYS positive. No 2nd subtractor needed!
    wire [4:0] diff_exponent = L_exp - S_exp;

    // Output sign mathematically reduced to a single mux
    wire o_sign = (add_sub == 0) ? L_sign : (a_is_larger ? a[15] : ~b[15]);

    wire signs_match = (L_sign == S_sign);
    wire do_subtract = (add_sub == 0) ? !signs_match : signs_match;

    // =======================================================================
    // ALIGNMENT SHIFTER (Clamped to 15)
    // =======================================================================
    wire [3:0] shift_amt = (diff_exponent > 5'd14) ? 4'd15 : diff_exponent[3:0];

    wire [25:0] extended_shift = {S_mant, 15'b0} >> shift_amt;

    wire [10:0] shifted_main = extended_shift[25:15];
    wire G = extended_shift[14];
    wire R = extended_shift[13];
    wire S = (|extended_shift[12:0]) | (diff_exponent > 5'd14); 

    wire [13:0] S_mant_grs = {shifted_main, G, R, S};
    wire [13:0] L_mant_grs = {L_mant, 3'b000}; 

    // =======================================================================
    // THE SINGLE ALU
    // =======================================================================
    wire [13:0] b_operand = do_subtract ? ~S_mant_grs : S_mant_grs;
    wire [14:0] raw_add_result = L_mant_grs + b_operand + {14'd0, do_subtract};

    wire [14:0] add_sub_mantissa = do_subtract ? {1'b0, raw_add_result[13:0]} : raw_add_result;

    // =======================================================================
    // NORMALIZATION (Parallel LZC)
    // =======================================================================
    reg [3:0]  lzc;
    always @(*) begin
        casez (add_sub_mantissa)
            15'b1_????_????_????_??: lzc = 4'd0;  
            15'b0_1???_????_????_??: lzc = 4'd0;  
            15'b0_01??_????_????_??: lzc = 4'd1;
            15'b0_001?_????_????_??: lzc = 4'd2;
            15'b0_0001_????_????_??: lzc = 4'd3;
            15'b0_0000_1???_????_??: lzc = 4'd4;
            15'b0_0000_01??_????_??: lzc = 4'd5;
            15'b0_0000_001?_????_??: lzc = 4'd6;
            15'b0_0000_0001_????_??: lzc = 4'd7;
            15'b0_0000_0000_1???_??: lzc = 4'd8;
            15'b0_0000_0000_01??_??: lzc = 4'd9;
            15'b0_0000_0000_001?_??: lzc = 4'd10;
            15'b0_0000_0000_0001_??: lzc = 4'd11;
            15'b0_0000_0000_0000_1?: lzc = 4'd12;
            default:                 lzc = 4'd15; 
        endcase
    end

    // Redundancy deletion: If LZC is 15, the mantissa is entirely zero.
    wire is_zero = (lzc == 4'd15);
    
    reg [13:0] norm_mant;
    reg [4:0]  norm_exp;

    always @(*) begin
        if (is_zero) begin
            norm_mant = 14'd0;
            norm_exp  = 5'd0;
        end else if (!do_subtract && add_sub_mantissa[14] == 1'b1) begin
            norm_mant = {add_sub_mantissa[14:2], add_sub_mantissa[1] | add_sub_mantissa[0]};
            norm_exp  = L_exp + 5'd1;
        end else begin
            norm_mant = (add_sub_mantissa[13:0] << lzc);
            norm_exp  = L_exp - {1'b0, lzc};
        end
    end 

    // =======================================================================
    // ROUNDING & PACKING
    // =======================================================================
    wire norm_L = norm_mant[3];
    wire norm_G = norm_mant[2];
    wire norm_R = norm_mant[1];
    wire norm_Sticky = norm_mant[0];
    
    reg round_up;
    always @(*) begin
        case (rm)
            3'b000: round_up = (norm_G & (norm_R | norm_Sticky)) | (norm_G & ~norm_R & ~norm_Sticky & norm_L); 
            3'b001: round_up = 1'b0; 
            3'b010: round_up = o_sign & (norm_G | norm_R | norm_Sticky); 
            3'b011: round_up = ~o_sign & (norm_G | norm_R | norm_Sticky); 
            3'b100: round_up = norm_G; 
            default: round_up = 1'b0;
        endcase
    end

    wire [11:0] rounded_frac = {1'b0, norm_mant[13:3]} + round_up;

    reg [9:0] final_frac;
    reg [4:0] final_exp;

    always @(*) begin
        if (is_zero) begin
            final_frac = 10'd0;
            final_exp  = 5'd0;
        end else if (rounded_frac[11] == 1'b1) begin
            final_frac = 10'd0; 
            final_exp  = norm_exp + 5'd1;
        end else begin
            final_frac = rounded_frac[9:0];
            final_exp  = norm_exp;
        end
    end

    assign result = {o_sign, final_exp, final_frac};

endmodule