module fp_adder_sub (
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        add_sub, // 0 for addition, 1 for subtraction
    input  wire [2:0]  rm,      // Rounding Mode (from CSR)
    output wire [15:0] result
);

wire [4:0] a_exponent, b_exponent;
wire [10:0] a_mantissa, b_mantissa, o_mantissa;
wire [14:0]  sum_mantissa, diff_mantissa;
wire a_sign, b_sign;
reg o_sign;

assign a_exponent = a[14:10];
assign b_exponent = b[14:10];
assign a_mantissa = (a_exponent == 0) ? {1'b0, a[9:0]} : {1'b1, a[9:0]};
assign b_mantissa = (b_exponent == 0) ? {1'b0, b[9:0]} : {1'b1, b[9:0]};
assign a_sign = a[15];
assign b_sign = b[15];

wire a_is_larger = {a_exponent, a_mantissa} >= {b_exponent, b_mantissa};
wire [4:0] o_exponent = a_is_larger ? a_exponent : b_exponent;  
wire [4:0] diff_exponent = a_is_larger ? (a_exponent - b_exponent) : (b_exponent - a_exponent);

wire [10:0] smaller_mantissa = a_is_larger ? b_mantissa : a_mantissa;
wire [10:0] larger_mantissa  = a_is_larger ? a_mantissa : b_mantissa;

wire [41:0] extended_shift = {smaller_mantissa, 31'b0} >> diff_exponent;

wire [10:0] shifted_main = extended_shift[41:31];
wire G = extended_shift[30];
wire R = extended_shift[29];
wire S = |extended_shift[28:0]; // Sticky is the logical OR of ALL remaining bits

// Construct the 14-bit operands (11 main bits + 3 GRS bits)
wire [13:0] shifted_mantissa_grs = {shifted_main, G, R, S};
wire [13:0] other_mantissa_grs   = {larger_mantissa, 3'b000}; // Unshifted gets 000

reg [14:0] add_sub_mantissa;

always @(*) begin
    if (add_sub == 0) begin // Addition
        if (a_sign == b_sign) begin
           o_sign = a_sign; // same sign, result has that sign
           add_sub_mantissa = other_mantissa_grs + shifted_mantissa_grs; // add mant     
            // Perform addition of mantissas
        end else begin
            add_sub_mantissa = other_mantissa_grs - shifted_mantissa_grs; 
            o_sign = a_is_larger ? a_sign : b_sign; // sign of larger
            // Perform subtraction of mantissas
        end
    end else begin // Subtraction
        if (a_sign != b_sign) begin
              o_sign = a_sign; // different signs, result has sign of a
                add_sub_mantissa = other_mantissa_grs + shifted_mantissa_grs; // add mant
            // Perform addition of mantissas
        end else begin
            add_sub_mantissa = other_mantissa_grs - shifted_mantissa_grs; // subtract smaller from larger
            o_sign = a_is_larger ? a_sign : ~b_sign; // if same sign, sign of larger, but if we are doing subtraction,
            //  we flip the sign of b, so if a and b have same sign, we want the result to have the opposite sign
             
            // Perform subtraction of mantissas
        end
    end
end

// =======================================================================
    // STAGE 4: NORMALIZATION (Leading Zero Counter & Shifter)
    // =======================================================================
    reg [3:0]  lzc;
    reg [13:0] norm_mant;
    reg [4:0]  norm_exp;
    wire       is_zero;

    // Leading Zero Counter
    always @(*) begin
        if      (add_sub_mantissa[14]) lzc = 4'd0;  // Carry out
        else if (add_sub_mantissa[13]) lzc = 4'd0;  // Already normalized
        else if (add_sub_mantissa[12]) lzc = 4'd1;
        else if (add_sub_mantissa[11]) lzc = 4'd2;
        else if (add_sub_mantissa[10]) lzc = 4'd3;
        else if (add_sub_mantissa[9])  lzc = 4'd4;
        else if (add_sub_mantissa[8])  lzc = 4'd5;
        else if (add_sub_mantissa[7])  lzc = 4'd6;
        else if (add_sub_mantissa[6])  lzc = 4'd7;
        else if (add_sub_mantissa[5])  lzc = 4'd8;
        else if (add_sub_mantissa[4])  lzc = 4'd9;
        else if (add_sub_mantissa[3])  lzc = 4'd10;
        else if (add_sub_mantissa[2])  lzc = 4'd11;
        else if (add_sub_mantissa[1])  lzc = 4'd12;
        else                           lzc = 4'd15; // Completely zero
    end

    assign is_zero = (add_sub_mantissa == 15'd0) || (lzc == 4'd15);

    // Barrel Shifter for Normalization
    always @(*) begin
        if (is_zero) begin
            norm_mant = 14'd0;
            norm_exp  = 5'd0;
        end else if (add_sub_mantissa[14] == 1'b1) begin
            // Addition Overflow: Shift Right by 1
            // Sticky bit absorbs the old Round bit
            norm_mant = {add_sub_mantissa[14:2], add_sub_mantissa[1] | add_sub_mantissa[0]};
            norm_exp  = o_exponent + 5'd1;
        end else begin
            // Subtraction Cancellation: Shift Left by LZC
            reg [14:0] shifted_temp;
            shifted_temp = add_sub_mantissa << lzc;
            norm_mant = shifted_temp[13:0]; 
            norm_exp  = o_exponent - {1'b0, lzc};
        end
    end 

    // =======================================================================
    // STAGE 5: ROUNDING
    // =======================================================================
    wire norm_L = norm_mant[3];
    wire norm_G = norm_mant[2];
    wire norm_R = norm_mant[1];
    wire norm_S = norm_mant[0];
    
    reg round_up;

    // RISC-V Rounding Modes
    always @(*) begin
        case (rm)
            3'b000: round_up = (norm_G & (norm_R | norm_S)) | (norm_G & ~norm_R & ~norm_S & norm_L); // RNE
            3'b001: round_up = 1'b0; // RTZ
            3'b010: round_up = o_sign & (norm_G | norm_R | norm_S); // RDN
            3'b011: round_up = ~o_sign & (norm_G | norm_R | norm_S); // RUP
            3'b100: round_up = norm_G; // RMM
            default: round_up = 1'b0;
        endcase
    end

    // Add round bit to fraction (12 bits to catch post-rounding overflow)
    wire [11:0] rounded_frac = {1'b0, norm_mant[13:3]} + round_up;

    reg [9:0] final_frac;
    reg [4:0] final_exp;

    // Post-Rounding Overflow Check
    always @(*) begin
        if (is_zero) begin
            final_frac = 10'd0;
            final_exp  = 5'd0;
        end else if (rounded_frac[11] == 1'b1) begin
            // Post-rounding overflow (e.g., 1.1111 rounded up to 10.0000)
            final_frac = 10'd0; 
            final_exp  = norm_exp + 5'd1;
        end else begin
            final_frac = rounded_frac[9:0];
            final_exp  = norm_exp;
        end
    end

    // =======================================================================
    // FINAL OUTPUT PACKING
    // =======================================================================
    assign result = {o_sign, final_exp, final_frac};

endmodule