module fp_adder_sub (
    input  wire        clk,      
    input  wire        rst_n,    
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        add_sub, 
    input  wire [2:0]  rm,      
    output wire [15:0] result
);

    // =======================================================================
    // STAGE 1: COMPARE, ALIGN, AND ADD
    // =======================================================================
    wire [4:0] a_exp = a[14:10];
    wire [4:0] b_exp = b[14:10];
    wire a_exp_larger = (a_exp >= b_exp);
    wire [4:0] diff_exponent = a_exp_larger ? (a_exp - b_exp) : (b_exp - a_exp); 

    wire a_is_larger = (a[14:0] >= b[14:0]);
    wire L_sign       = a_is_larger ? a[15]   : b[15];
    wire S_sign       = a_is_larger ? b[15]   : a[15];

    wire [10:0] a_mant = (a_exp == 0) ? {1'b0, a[9:0]} : {1'b1, a[9:0]};
    wire [10:0] b_mant = (b_exp == 0) ? {1'b0, b[9:0]} : {1'b1, b[9:0]};
    
    wire [10:0] L_mant = a_is_larger ? a_mant : b_mant;
    wire [10:0] S_mant = a_is_larger ? b_mant : a_mant;

    wire o_sign = (add_sub == 0) ? L_sign : (a_is_larger ? a[15] : ~b[15]);
    wire signs_match = (L_sign == S_sign);
    wire do_subtract = (add_sub == 0) ? !signs_match : signs_match;
    wire [4:0] L_exp = a_is_larger ? a_exp : b_exp;

    wire [3:0] shift_amt = (diff_exponent > 5'd14) ? 4'd15 : diff_exponent[3:0];
    wire [25:0] extended_shift = {S_mant, 15'b0} >> shift_amt;

    wire [10:0] shifted_main = extended_shift[25:15];
    wire G = extended_shift[14];
    wire R = extended_shift[13];
    wire S = (|extended_shift[12:0]) | (diff_exponent > 5'd14); 

    wire [13:0] S_mant_grs = {shifted_main, G, R, S};
    wire [13:0] L_mant_grs = {L_mant, 3'b000}; 

    wire [13:0] b_operand = do_subtract ? ~S_mant_grs : S_mant_grs;
    wire [14:0] raw_add_result = L_mant_grs + b_operand + {14'd0, do_subtract};

    // =======================================================================
    // PIPELINE WALL 1 (End of Add)
    // =======================================================================
    reg [14:0] reg_raw_add_result;
    reg        reg_do_subtract;
    reg        reg_o_sign;
    reg [4:0]  reg_L_exp;
    reg [2:0]  reg_rm;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_raw_add_result <= 15'd0; reg_do_subtract <= 1'b0;
            reg_o_sign <= 1'b0; reg_L_exp <= 5'd0; reg_rm <= 3'd0;
        end else begin
            reg_raw_add_result <= raw_add_result; reg_do_subtract <= do_subtract;
            reg_o_sign <= o_sign; reg_L_exp <= L_exp; reg_rm <= rm;
        end
    end

    // =======================================================================
    // STAGE 2: NORMALIZE 
    // =======================================================================
    wire add_overflow = (!reg_do_subtract && reg_raw_add_result[14]);

    reg [3:0]  lzc;
    always @(*) begin
        casez (reg_raw_add_result[13:0])
            14'b1_????_????_????_?: lzc = 4'd0;  
            14'b0_1???_????_????_?: lzc = 4'd1;
            14'b0_01??_????_????_?: lzc = 4'd2;
            14'b0_001?_????_????_?: lzc = 4'd3;
            14'b0_0001_????_????_?: lzc = 4'd4;
            14'b0_0000_1???_????_?: lzc = 4'd5;
            14'b0_0000_01??_????_?: lzc = 4'd6;
            14'b0_0000_001?_????_?: lzc = 4'd7;
            14'b0_0000_0001_????_?: lzc = 4'd8;
            14'b0_0000_0000_1???_?: lzc = 4'd9;
            14'b0_0000_0000_01??_?: lzc = 4'd10;
            14'b0_0000_0000_001?_?: lzc = 4'd11;
            14'b0_0000_0000_0001_?: lzc = 4'd12;
            14'b0_0000_0000_0000_1: lzc = 4'd13;
            default:                lzc = 4'd15;
        endcase
    end

    wire is_zero = (!add_overflow) && (lzc == 4'd15);
    
    wire [13:0] norm_mant = add_overflow ? 
                            {reg_raw_add_result[14:2], reg_raw_add_result[1] | reg_raw_add_result[0]} : 
                            (reg_raw_add_result[13:0] << lzc);

    wire [4:0]  norm_exp  = add_overflow ? 
                            (reg_L_exp + 5'd1) : 
                            (reg_L_exp - {1'b0, lzc});

    // =======================================================================
    // PIPELINE WALL 2 (The DFF you requested! End of Normalize)
    // =======================================================================
    reg [13:0] reg_norm_mant;
    reg [4:0]  reg_norm_exp;
    reg        reg_is_zero;
    reg        reg_final_sign;
    reg [2:0]  reg_final_rm;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_norm_mant <= 14'd0; reg_norm_exp <= 5'd0; reg_is_zero <= 1'b0;
            reg_final_sign <= 1'b0; reg_final_rm <= 3'd0;
        end else begin
            reg_norm_mant <= norm_mant; reg_norm_exp <= norm_exp; reg_is_zero <= is_zero;
            reg_final_sign <= reg_o_sign; reg_final_rm <= reg_rm;
        end
    end

    // =======================================================================
    // STAGE 3: ROUND AND PACK
    // =======================================================================
    wire norm_L = reg_norm_mant[3];
    wire norm_G = reg_norm_mant[2];
    wire norm_R = reg_norm_mant[1];
    wire norm_Sticky = reg_norm_mant[0];
    
    reg round_up;
    always @(*) begin
        case (reg_final_rm)
            3'b000: round_up = (norm_G & (norm_R | norm_Sticky)) | (norm_G & ~norm_R & ~norm_Sticky & norm_L); 
            3'b001: round_up = 1'b0; 
            3'b010: round_up = reg_final_sign & (norm_G | norm_R | norm_Sticky); 
            3'b011: round_up = ~reg_final_sign & (norm_G | norm_R | norm_Sticky); 
            3'b100: round_up = norm_G; 
            default: round_up = 1'b0;
        endcase
    end

    wire [10:0] frac_base = reg_norm_mant[13:3];
    wire [11:0] frac_plus_1 = {1'b0, frac_base} + 12'd1;

    wire [11:0] rounded_frac = round_up ? frac_plus_1 : {1'b0, frac_base};
    wire post_round_overflow = rounded_frac[11];

    wire [4:0] final_exp = reg_is_zero ? 5'd0 :
                           post_round_overflow ? (reg_norm_exp + 5'd1) :
                           reg_norm_exp;

    wire [9:0] final_frac = (reg_is_zero || post_round_overflow) ? 10'd0 : rounded_frac[9:0];

    assign result = {reg_final_sign, final_exp, final_frac};

endmodule