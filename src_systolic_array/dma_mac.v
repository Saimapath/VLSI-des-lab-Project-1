`timescale 1ns/1ps

module MAC(
    input      [15:0] Ain,
    input      [15:0] Bin,
    input             clk,
    input             reset,
    input             clear, 
    output reg [15:0] Aout,
    output reg [15:0] Bout,
    output     [15:0] C
);
    wire [15:0] product;
    wire [15:0] sum;
    
    wire [15:0] a, b;
    reg [15:0] product_reg;
    reg [15:0] accumulator;

    multiplier mul(.a(a), .b(b), .result(product));
    adder add(.a(product_reg), .b(accumulator), .result(sum));

    always @(posedge clk) begin
        if(!reset) begin
            product_reg <= 16'd0;
            accumulator <= 16'd0;
            Aout <= 16'd0;
            Bout <= 16'd0;
        end
        else if (clear) begin 
            product_reg <= 16'd0;
            accumulator <= 16'd0;
            Aout <= 16'd0;
            Bout <= 16'd0;
        end
        else begin
            product_reg <= product;
            accumulator <= sum; 
            Aout <= a;
            Bout <= b;
        end
    end
    
    assign a = Ain;
    assign b = Bin;
    assign C = accumulator;
endmodule

// =====================================================================
// OPTIMIZED ADDER (Identical Logic, Zero Loops, Zero Latches)
// =====================================================================
module adder(
    input  [15:0] a, b,
    output [15:0] result
);
    reg a_sign, b_sign, pre_sign;
    reg [4:0]  a_exponent, b_exponent, pre_e;
    reg [10:0] a_mantissa, b_mantissa;
    reg [11:0] pre_m;
    reg [4:0]  diff;
    reg [10:0] tmp_mantissa;

    wire [4:0] norm_e;
    wire [11:0] norm_m;

    // Normalizer sits outside the procedural block (No routing loops)
    addition_normaliser norm1 (
        .in_e(pre_e),
        .in_m(pre_m),
        .out_e(norm_e),
        .out_m(norm_m)
    );

    always @ (*) begin
        // 1. Default assignments kill all latches
        a_sign = a[15];
        b_sign = b[15];
        pre_sign = 1'b0;
        pre_e = 5'd0;
        pre_m = 12'd0;
        diff = 5'd0;
        tmp_mantissa = 11'd0;

        if(a[14:10] == 0) begin
            a_exponent = 5'b00000;
            a_mantissa = {1'b0, a[9:0]};
        end else begin
            a_exponent = a[14:10];
            a_mantissa = {1'b1, a[9:0]};
        end

        if(b[14:10] == 0) begin
            b_exponent = 5'b00000;
            b_mantissa = {1'b0, b[9:0]};
        end else begin
            b_exponent = b[14:10];
            b_mantissa = {1'b1, b[9:0]};
        end

        // 2. Math Phase (Identical to original)
        if (a_exponent == b_exponent) begin 
            pre_e = a_exponent;
            if (a_sign == b_sign) begin 
                pre_m = a_mantissa + b_mantissa;
                pre_m[11] = a_mantissa[10] || b_mantissa[10];
                pre_sign = a_sign;
            end else begin 
                if(a_mantissa > b_mantissa) begin
                    pre_m = a_mantissa - b_mantissa;
                    pre_sign = a_sign;
                end else begin
                    pre_m = b_mantissa - a_mantissa;
                    pre_sign = b_sign;
                end
            end
        end else begin 
            if (a_exponent > b_exponent) begin 
                pre_e = a_exponent;
                pre_sign = a_sign;
                diff = a_exponent - b_exponent;
                tmp_mantissa = b_mantissa >> diff;
                if (a_sign == b_sign) pre_m = a_mantissa + tmp_mantissa;
                else                  pre_m = a_mantissa - tmp_mantissa;
            end else if (a_exponent < b_exponent) begin
                pre_e = b_exponent;
                pre_sign = b_sign;
                diff = b_exponent - a_exponent;
                tmp_mantissa = a_mantissa >> diff;
                if (a_sign == b_sign) pre_m = b_mantissa + tmp_mantissa;
                else                  pre_m = b_mantissa - tmp_mantissa;
            end
        end
    end

    // 3. Resolution Phase (Replaces the sequential if/else at the end)
    wire [4:0]  final_e;
    wire [11:0] final_m;
    wire        final_s;

    assign final_e = (pre_m[11] == 1) ? pre_e + 1 :
                     ((pre_m[10] != 1) && (pre_e != 0)) ? norm_e : pre_e;

    assign final_m = (pre_m[11] == 1) ? pre_m >> 1 :
                     ((pre_m[10] != 1) && (pre_e != 0)) ? norm_m : pre_m;

    assign final_s = pre_sign;

    // Final Zero Check
    assign result = (final_m == 0) ? 16'd0 : {final_s, final_e, final_m[9:0]};

endmodule

// =====================================================================
// OPTIMIZED MULTIPLIER (Identical Logic, Zero Loops, Zero Latches)
// =====================================================================
module multiplier(
    input  [15:0] a, b,
    output [15:0] result
);
    reg a_sign, b_sign, pre_sign;
    reg [5:0] a_exponent, b_exponent;
    reg [4:0] pre_e;
    reg [10:0] a_mantissa, b_mantissa;
    reg [22:0] product;

    wire [4:0] norm_e;
    wire [22:0] norm_m;

    multiplication_normaliser norm1 (
        .in_e(pre_e),
        .in_m(product),
        .out_e(norm_e),
        .out_m(norm_m)
    );

    always @ (*) begin
        // 1. Default Assignments
        a_sign = a[15]; b_sign = b[15];
        pre_sign = a_sign ^ b_sign;
        a_exponent = 6'd0; b_exponent = 6'd0;
        a_mantissa = 11'd0; b_mantissa = 11'd0;
        pre_e = 5'd0; product = 23'd0;

        if(a[14:10] == 0) begin
            a_exponent = 6'd0;
            a_mantissa = {1'b0, a[9:0]}; 
        end else begin
            a_exponent = a[14:10];
            a_mantissa = {1'b1, a[9:0]};
        end

        if(b[14:10] == 0) begin
            b_exponent = 6'd0;
            b_mantissa = {1'b0, b[9:0]};
        end else begin
            b_exponent = b[14:10];
            b_mantissa = {1'b1, b[9:0]};
        end

        pre_e = (a_exponent + b_exponent > 15) ? (a_exponent + b_exponent - 15) : 5'b00000;
        product = a_mantissa * b_mantissa;
    end

    // 2. Resolution Phase
    wire [4:0]  final_e;
    wire [22:0] final_product;

    assign final_e = (product[21] == 1) ? pre_e + 1 :
                     ((product[20] != 1) && (pre_e != 0)) ? norm_e : pre_e;

    assign final_product = (product[21] == 1) ? product >> 1 :
                           ((product[20] != 1) && (pre_e != 0)) ? norm_m : product;

//    assign result = {pre_sign, final_e, final_product[20:10]};
    // FIXED: 1 sign + 5 exp + 10 mantissa = 16 bits perfectly aligned!
assign result = (final_product == 0) ? 16'd0 : {pre_sign, final_e, final_product[19:10]};

endmodule

// =====================================================================
// PARALLEL ADDITION NORMALIZER (casez = fast priority encoder)
// =====================================================================
module addition_normaliser(
  input  [4:0]  in_e,
  input  [11:0] in_m,
  output reg [4:0]  out_e,
  output reg [11:0] out_m
);
  always @ (*) begin
        casez (in_m[10:3])
            8'b00000001: begin out_e = in_e - 7; out_m = in_m << 7; end
            8'b0000001?: begin out_e = in_e - 6; out_m = in_m << 6; end
            8'b000001??: begin out_e = in_e - 5; out_m = in_m << 5; end
            8'b00001???: begin out_e = in_e - 4; out_m = in_m << 4; end
            8'b0001????: begin out_e = in_e - 3; out_m = in_m << 3; end
            8'b001?????: begin out_e = in_e - 2; out_m = in_m << 2; end
            8'b01??????: begin out_e = in_e - 1; out_m = in_m << 1; end
            default:     begin out_e = in_e;     out_m = in_m;      end
        endcase
  end
endmodule

// =====================================================================
// PARALLEL MULTIPLICATION NORMALIZER (casez + fixed latch)
// =====================================================================
module multiplication_normaliser(
  input  [4:0]  in_e,
  input  [22:0] in_m,
  output reg [4:0]  out_e,
  output reg [22:0] out_m
);
  always @ (*) begin
        casez (in_m[21:16])
            6'b000001: begin out_e = in_e - 5; out_m = in_m << 5; end
            6'b00001?: begin out_e = in_e - 4; out_m = in_m << 4; end
            6'b0001??: begin out_e = in_e - 3; out_m = in_m << 3; end
            6'b001???: begin out_e = in_e - 2; out_m = in_m << 2; end
            6'b01????: begin out_e = in_e - 1; out_m = in_m << 1; end
            default:   begin out_e = in_e;     out_m = in_m;      end // <- This default fixes the latch in your original code
        endcase
  end
endmodule