module fp_convert (
    // Inputs
    input  wire [15:0] f_in,       // Floating-point input (for F2I)
    input  wire [31:0] i_in,       // Integer input (for I2F)
    input  wire        is_signed,  // 1 for signed (W), 0 for unsigned (WU)
    
    // Outputs
    output reg  [31:0] i_out,      // Integer output (Result of F2I)
    output reg  [15:0] f_out       // Floating-point output (Result of I2F)
);

    // =======================================================================
    // PATH 1: FLOAT TO INTEGER (FCVT.W.H / FCVT.WU.H)
    // =======================================================================
    wire        f_sign = f_in[15];
    wire [4:0]  f_exp  = f_in[14:10];
    wire [10:0] f_mant = (f_exp == 5'd0) ? {1'b0, f_in[9:0]} : {1'b1, f_in[9:0]};
    
    // True exponent (Unbiased)
    wire signed [6:0] true_exp = {2'b00, f_exp} - 7'sd15;
    
    reg [31:0] raw_int;

    always @(*) begin
        // 1. Handle Zeroes, Subnormals, and small fractions (< 1.0)
        if (true_exp < 0) begin
            raw_int = 32'd0; // Rounds towards zero (RTZ) by default for standard C-casts
            
        // 2. Handle Overflow (Exponent too large for 32-bit integer)
        end else if (true_exp >= 31) begin
            // RISC-V Standard: Overflow clamps to maximum/minimum possible integer
            if (is_signed)
                raw_int = f_sign ? 32'h8000_0000 : 32'h7FFF_FFFF;
            else
                raw_int = f_sign ? 32'h0000_0000 : 32'hFFFF_FFFF;
                
        // 3. Normal Conversion (Shift the mantissa into integer position)
        end else begin
            // The mantissa has 10 fractional bits.
            // If true_exp > 10, we must shift left to grow the integer.
            // If true_exp < 10, we must shift right to chop off fractional bits.
            if (true_exp >= 10) begin
                raw_int = {21'd0, f_mant} << (true_exp - 10);
            end else begin
                raw_int = {21'd0, f_mant} >> (10 - true_exp);
            end
            
            // Apply 2's Complement if the float was negative and we are doing a signed cast
            if (f_sign && is_signed) begin
                raw_int = ~raw_int + 1;
            end else if (f_sign && !is_signed) begin
                raw_int = 32'd0; // Negative float to Unsigned Int clamps to 0 in RISC-V
            end
        end
        
        i_out = raw_int;
    end

    // =======================================================================
    // PATH 2: INTEGER TO FLOAT (FCVT.H.W / FCVT.H.WU)
    // =======================================================================
    // 1. Determine Sign and Absolute Value
    wire i_sign = is_signed & i_in[31];
    wire [31:0] abs_i = (i_sign) ? (~i_in + 1) : i_in;
    
    // 2. Priority Encoder (Find the Most Significant '1')
    reg [4:0] msb_pos;
    always @(*) begin
        if (abs_i[31]) msb_pos = 31;
        else if (abs_i[30]) msb_pos = 30;
        else if (abs_i[29]) msb_pos = 29;
        else if (abs_i[28]) msb_pos = 28;
        else if (abs_i[27]) msb_pos = 27;
        else if (abs_i[26]) msb_pos = 26;
        else if (abs_i[25]) msb_pos = 25;
        else if (abs_i[24]) msb_pos = 24;
        else if (abs_i[23]) msb_pos = 23;
        else if (abs_i[22]) msb_pos = 22;
        else if (abs_i[21]) msb_pos = 21;
        else if (abs_i[20]) msb_pos = 20;
        else if (abs_i[19]) msb_pos = 19;
        else if (abs_i[18]) msb_pos = 18;
        else if (abs_i[17]) msb_pos = 17;
        else if (abs_i[16]) msb_pos = 16;
        else if (abs_i[15]) msb_pos = 15;
        else if (abs_i[14]) msb_pos = 14;
        else if (abs_i[13]) msb_pos = 13;
        else if (abs_i[12]) msb_pos = 12;
        else if (abs_i[11]) msb_pos = 11;
        else if (abs_i[10]) msb_pos = 10;
        else if (abs_i[9])  msb_pos = 9;
        else if (abs_i[8])  msb_pos = 8;
        else if (abs_i[7])  msb_pos = 7;
        else if (abs_i[6])  msb_pos = 6;
        else if (abs_i[5])  msb_pos = 5;
        else if (abs_i[4])  msb_pos = 4;
        else if (abs_i[3])  msb_pos = 3;
        else if (abs_i[2])  msb_pos = 2;
        else if (abs_i[1])  msb_pos = 1;
        else                msb_pos = 0;
    end

    // 3. Shift and Pack the Float
    reg [4:0]  out_exp;
    reg [9:0]  out_frac;

    always @(*) begin
        if (abs_i == 32'd0) begin
            out_exp  = 5'd0;
            out_frac = 10'd0;
        end else begin
            // Exponent is Bias (15) + MSB Position
            out_exp = 5'd15 + msb_pos;
            
            // Align the MSB to the hidden bit position
            // If MSB is >= 10, we shift right and truncate (or round).
            // If MSB < 10, we shift left to pad with zeros.
            if (msb_pos >= 10) begin
                out_frac = abs_i >> (msb_pos - 10);
            end else begin
                out_frac = abs_i << (10 - msb_pos);
            end
        end
        
        f_out = {i_sign, out_exp, out_frac};
    end

endmodule