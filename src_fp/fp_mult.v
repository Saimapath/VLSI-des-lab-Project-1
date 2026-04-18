module fp16_multiplier (
    input  wire        clk,     // ---> ADDED CLOCK
    input  wire        rst_n,   // ---> ADDED RESET
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [2:0]  rm,      
    output wire [15:0] result
);

    // =======================================================================
    // STAGE 1: UNPACK & MULTIPLY (Combinational)
    // =======================================================================
    wire a_sign = a[15];
    wire b_sign = b[15];
    wire [4:0] a_exp = a[14:10];
    wire [4:0] b_exp = b[14:10];
    
    wire a_is_zero = (a_exp == 5'd0);
    wire b_is_zero = (b_exp == 5'd0);
    wire next_result_is_zero = a_is_zero | b_is_zero;

    wire [10:0] a_mant = a_is_zero ? 11'd0 : {1'b1, a[9:0]};
    wire [10:0] b_mant = b_is_zero ? 11'd0 : {1'b1, b[9:0]};
    wire next_o_sign = a_sign ^ b_sign;

    // The raw math
    wire [21:0] next_raw_product = a_mant * b_mant; 
    wire signed [6:0] next_raw_exp = {2'b00, a_exp} + {2'b00, b_exp} - 7'sd15;

    // =======================================================================
    // INTERNAL PIPELINE REGISTER (Forces Vivado to use DSP48 Registers!)
    // =======================================================================
    reg [21:0] raw_product;
    reg signed [6:0] raw_exp;
    reg o_sign;
    reg result_is_zero;
    reg [2:0] rm_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            raw_product    <= 22'd0;
            raw_exp        <= 7'sd0;
            o_sign         <= 1'b0;
            result_is_zero <= 1'b0;
            rm_reg         <= 3'd0;
        end else begin
            raw_product    <= next_raw_product; // LATCHED!
            raw_exp        <= next_raw_exp;
            o_sign         <= next_o_sign;
            result_is_zero <= next_result_is_zero;
            rm_reg         <= rm;
        end
    end

    // =======================================================================
    // STAGE 2: NORMALIZE & ROUND (Uses the Latched Data)
    // =======================================================================
    wire is_norm = raw_product[21]; 

    wire [9:0] norm_frac = is_norm ? raw_product[20:11] : raw_product[19:10];
    wire G = is_norm ? raw_product[10] : raw_product[9];
    wire R = is_norm ? raw_product[9]  : raw_product[8];

    wire S_base = |raw_product[7:0];
    wire S = is_norm ? (S_base | raw_product[8]) : S_base;

    wire signed [6:0] norm_exp = raw_exp + {6'd0, is_norm};

    // --- Rounding ---
    wire L = norm_frac[0];
    reg round_up;

    always @(*) begin
        case (rm_reg) // Use registered rounding mode!
            3'b000: round_up = (G & (R | S)) | (G & ~R & ~S & L); // RNE
            3'b001: round_up = 1'b0; // RTZ
            3'b010: round_up = o_sign & (G | R | S); // RDN
            3'b011: round_up = ~o_sign & (G | R | S); // RUP
            3'b100: round_up = G; // RMM
            default: round_up = 1'b0;
        endcase
    end

    wire [10:0] rounded_frac = {1'b0, norm_frac} + round_up;
    wire post_round_overflow = rounded_frac[10];

    // --- Exception Handling ---
    wire signed [6:0] final_exp_calc = norm_exp + {6'd0, post_round_overflow};

    wire is_underflow = result_is_zero || (norm_exp <= 7'sd0);
    wire is_overflow  = (!is_underflow) && (final_exp_calc >= 7'sd31);

    wire [4:0] final_exp  = is_underflow ? 5'd0 :
                            is_overflow  ? 5'd31 :
                            final_exp_calc[4:0];

    wire [9:0] final_frac = (is_underflow || is_overflow || post_round_overflow) ? 10'd0 : rounded_frac[9:0];

    assign result = {o_sign, final_exp, final_frac};

endmodule