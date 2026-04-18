module multiplier_16x16_signed(
    input clk, reset,
    input [1:0] sign,// 11 for signed, 00 for unsigned, 01 for signed A and unsigned B, 10 unused
    input [15:0] A,
    input [15:0] B,
    output reg [31:0] PRODUCT
);
wire [15:0] PP [15:0];

wire [15:0] s0_dots [31:0]; // Stage 0: 32 Columns, Max Height 16
wire [12:0] s1_dots [31:0]; // Stage 1: 32 Columns, Max Height 13
wire [8:0]  s2_dots [31:0]; // Stage 2: 32 Columns, Max Height 9
wire [5:0]  s3_dots [31:0]; // Stage 3: 32 Columns, Max Height 6
wire [3:0]  s4_dots [31:0]; // Stage 4: 32 Columns, Max Height 4
wire [2:0]  s5_dots [31:0]; // Stage 5: 32 Columns, Max Height 3
wire [1:0]  s6_dots [31:0]; // Stage 6: 32 Columns, Max Height 2


genvar i;
generate
    for (i = 0; i < 16; i = i + 1) begin : GEN_SMART_PP
        // Procedural results for each mode
        wire [15:0] row_signed;
        wire [15:0] row_unsigned;
        wire [15:0] row_mixed;

        // Mode 1: Signed Logic (11)
        if (i < 15) begin : SIGNED_NORMAL
            pp_calculator U_PP_SIGNED (.A(A), .B(B[i]), .PP(row_signed)); // 
        end else begin : SIGNED_LAST
            pp_lastbit    U_PP_SIGNED (.A(A), .B(B[i]), .PP(row_signed)); // [cite: 5, 6]
        end

        // Mode 2: Unsigned Logic (00)
        pp_calculator_unsigned U_PP_UNSIGNED (.A(A), .B(B[i]), .PP(row_unsigned)); // [cite: 3, 4]

        // Mode 3: Mixed Logic (01)
        pp_calculator U_PP_MIXED (.A(A), .B(B[i]), .PP(row_mixed)); // 

        // OPTIMIZATION: Flattened Multiplexer
        // This 'assign' maps to a single LUT level in FPGA hardware
        assign PP[i] = (sign == 2'b00) ? row_unsigned :
                       (sign == 2'b11) ? row_signed   :
                       (sign == 2'b01) ? row_mixed    : 16'b0;
    end
endgenerate
// generate 
//     for (i=0; i<32; i=i+1) begin : GEN_STAGE0_LAST
//         assign brent_input_A[i] = s6_dots[i][0];
//         assign brent_input_B[i] = s6_dots[i][1];
//     end
// endgenerate

// always @(*) begin
//     if(sign==2'b01) PRODUCT<=brent_input_A+brent_input_B+32'd32768;
//     else PRODUCT<=brent_input_A+brent_input_B;
// end

    reg [31:0] pipe_brent_A, pipe_brent_B;
    reg [1:0]  pipe_sign;
    integer k;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            pipe_brent_A <= 32'd0;
            pipe_brent_B <= 32'd0;
            pipe_sign    <= 2'b00;
        end else begin
            // Capture the wires from s6_dots
            for (k = 0; k < 32; k = k + 1) begin
                pipe_brent_A[k] <= s6_dots[k][0];
                pipe_brent_B[k] <= s6_dots[k][1];
            end
            pipe_sign <= sign;
        end
    end

    // The final addition now happens in the SECOND cycle of the 16x16 block
    always @(posedge clk or negedge reset) begin
        if (!reset) PRODUCT <= 32'd0;
        else begin
            if (pipe_sign == 2'b01) 
                PRODUCT <= pipe_brent_A + pipe_brent_B + 32'd32768;
            else 
                PRODUCT <= pipe_brent_A + pipe_brent_B;
        end
    end




wire [31:0] s0_dots_pseudo [15:0];

    genvar j;

    // ---------------------------------------------------------
    // BLOCK 1: Alignment (Shift) & Constant Insertion
    // ---------------------------------------------------------
    generate
        for (i = 0; i < 16; i = i + 1) begin : ROWS
            for (j = 0; j < 32; j = j + 1) begin : BITS
                
                // Case 1: Partial Product Data (The Shifted Window)
                if (j >= i && j < (i + 16)) begin
                    assign s0_dots_pseudo[i][j] = PP[i][j - i];
                end 
                
                // Case 2: Hardcoded '1's (Correction/Sign bits)
                // Row 0 @ Bit 16  AND  Row 15 @ Bit 31
                else if (i == 0 && j == 16) begin
                    // Bit 16 and 31 needs a 1 for BOTH Signed (11) and Mixed (01)
                    assign s0_dots_pseudo[i][j] = (sign == 2'b11) ? 1'b1 : 1'b0;
                end
                else if (i == 15 && j == 15) begin
                    assign s0_dots_pseudo[i][j] = (sign == 2'b01) ? 1'b1 : 1'b0;
                end
                else if (i == 15 && j == 31) begin
                    // Bit 16 and 31 needs a 1 for BOTH Signed (11) and Mixed (01)
                    assign s0_dots_pseudo[i][j] = (sign == 2'b11 || sign == 2'b01) ? 1'b1 : 1'b0;
                end

                // Case 3: Zero Padding (Everything else)
                else begin
                    assign s0_dots_pseudo[i][j] = 1'b0;
                end
                
            end
        end
    endgenerate

    // ---------------------------------------------------------
    // BLOCK 2: Transpose (Rows to Columns)
    // ---------------------------------------------------------
    generate
        for (j = 0; j < 32; j = j + 1) begin : COLUMNS
            for (i = 0; i < 16; i = i + 1) begin : HEIGHTS
                assign s0_dots[j][i] = s0_dots_pseudo[i][j];
            end
        end
    endgenerate
////////////////////stage_0 end//////////////////////
////////////////////stage_1//////////////////////
    generate
        for (j = 0; j < 13; j = j + 1) begin : COLUMNS_0
            for (i = 0; i < 13; i = i + 1) begin : HEIGHTS_0
                assign s1_dots[j][i] = s0_dots[j][i];
            end
        end
    endgenerate
    generate
        for (j = 0; j < 13; j = j + 1) begin : COLUMNS_1
            for (i = 20; i < 32; i = i + 1) begin : HEIGHTS_1
                assign s1_dots[i][12 - j] = s0_dots[i][15 - j];
            end
        end 
    endgenerate
    generate 
        for (j = 0; j < 12; j = j + 1) begin : COLUMNS_2
            assign s1_dots[19][12 - j] = s0_dots[19][15 - j];
        end
    endgenerate

    //Column 13
    half_adder HA1 (
        .a(s0_dots[13][0]),
        .b(s0_dots[13][1]),
        .sum(s1_dots[13][0]),
        .carry(s1_dots[14][0])
    );
    assign s1_dots[13][12:1] = s0_dots[13][13:2];
    //Column 14
    full_adder FA1 (
        .a(s0_dots[14][0]),
        .b(s0_dots[14][1]),
        .c(s0_dots[14][2]),
        .sum(s1_dots[14][1]),
        .carry(s1_dots[15][0])
    );
    half_adder FA2 (
        .a(s0_dots[14][3]),
        .b(s0_dots[14][4]),
        .sum(s1_dots[14][2]),
        .carry(s1_dots[15][1])
    );
    assign s1_dots[14][12:3] = s0_dots[14][14:5];
    //Column 15
    full_adder FA3 (
        .a(s0_dots[15][0]),
        .b(s0_dots[15][1]),
        .c(s0_dots[15][2]),
        .sum(s1_dots[15][2]),
        .carry(s1_dots[16][0])
    );
    full_adder FA4 (
        .a(s0_dots[15][3]),
        .b(s0_dots[15][4]),
        .c(s0_dots[15][5]),
        .sum(s1_dots[15][3]),
        .carry(s1_dots[16][1])
    );
    half_adder HA2 (
        .a(s0_dots[15][6]),
        .b(s0_dots[15][7]),
        .sum(s1_dots[15][4]),
        .carry(s1_dots[16][2])
    );
    assign s1_dots[15][12:5] = s0_dots[15][15:8];
    //Column 16
    full_adder FA5 (
        .a(s0_dots[16][0]),
        .b(s0_dots[16][1]),
        .c(s0_dots[16][2]),
        .sum(s1_dots[16][3]),
        .carry(s1_dots[17][0])
    );
    full_adder FA6 (
        .a(s0_dots[16][3]),
        .b(s0_dots[16][4]),
        .c(s0_dots[16][5]),
        .sum(s1_dots[16][4]),
        .carry(s1_dots[17][1])
    );
    full_adder FA7 (
        .a(s0_dots[16][6]),
        .b(s0_dots[16][7]),
        .c(s0_dots[16][8]),
        .sum(s1_dots[16][5]),
        .carry(s1_dots[17][2])
    );
    assign s1_dots[16][12:6] = s0_dots[16][15:9];
    //Column 17
    full_adder FA8 (
        .a(s0_dots[17][2]),
        .b(s0_dots[17][3]),
        .c(s0_dots[17][4]),
        .sum(s1_dots[17][3]),
        .carry(s1_dots[18][0])
    );
    full_adder FA9 (
        .a(s0_dots[17][5]),
        .b(s0_dots[17][6]),
        .c(s0_dots[17][7]),
        .sum(s1_dots[17][4]),
        .carry(s1_dots[18][1])
    );
    assign s1_dots[17][12:5] = s0_dots[17][15:8];
    //Column 18
    full_adder FA10 (
        .a(s0_dots[18][3]),
        .b(s0_dots[18][4]),
        .c(s0_dots[18][5]),
        .sum(s1_dots[18][2]),
        .carry(s1_dots[19][0])
    );
    assign s1_dots[18][12:3] = s0_dots[18][15:6];
////////////////////stage_1 end//////////////////////
////////////////////stage_2//////////////////////
    generate
        for (j = 0; j < 9; j = j + 1) begin : COLUMNS_3
            for (i = 0; i < 9; i = i + 1) begin : HEIGHTS_3
                assign s2_dots[j][i] = s1_dots[j][i];
            end
        end
    endgenerate
    generate
        for (i = 24; i < 32; i = i + 1) begin : COLUMNS_4
            for (j = 0; j < 9; j = j + 1) begin : HEIGHTS_4
                assign s2_dots[i][8 - j] = s1_dots[i][12 - j];
            end
        end 
    endgenerate
    generate
        for (i = 0; i < 8; i = i + 1) begin : HEIGHT_5
            assign s2_dots[23][8 - i] = s1_dots[23][12 - i];
        end
    endgenerate

    //Column 9
    half_adder FA1_stage2 (
        .a(s1_dots[9][0]),
        .b(s1_dots[9][1]),
        .sum(s2_dots[9][0]),
        .carry(s2_dots[10][0])
    );
    assign s2_dots[9][8:1] = s1_dots[9][9:2];
    //Column 10
    full_adder FA2_stage2 (
        .a(s1_dots[10][0]),
        .b(s1_dots[10][1]),
        .c(s1_dots[10][2]),
        .sum(s2_dots[10][1]),
        .carry(s2_dots[11][0])
    );
    half_adder FA3_stage2 (
        .a(s1_dots[10][3]),
        .b(s1_dots[10][4]),
        .sum(s2_dots[10][2]),
        .carry(s2_dots[11][1])
    );
    assign s2_dots[10][8:3] = s1_dots[10][10:5];
    //Column 11
    full_adder FA4_stage2 (
        .a(s1_dots[11][0]),
        .b(s1_dots[11][1]),
        .c(s1_dots[11][2]),
        .sum(s2_dots[11][2]),
        .carry(s2_dots[12][0])
    );
    full_adder FA5_stage2 (
        .a(s1_dots[11][3]),
        .b(s1_dots[11][4]),
        .c(s1_dots[11][5]),
        .sum(s2_dots[11][3]),
        .carry(s2_dots[12][1])
    );
    half_adder FA6_stage2 (
        .a(s1_dots[11][6]),
        .b(s1_dots[11][7]),
        .sum(s2_dots[11][4]),
        .carry(s2_dots[12][2])
    );
    assign s2_dots[11][8:5] = s1_dots[11][11:8];
    //Column 12
    full_adder FA7_stage2 (
        .a(s1_dots[12][0]),
        .b(s1_dots[12][1]),
        .c(s1_dots[12][2]),
        .sum(s2_dots[12][3]),
        .carry(s2_dots[13][0])
    );
    full_adder FA8_stage2 (
        .a(s1_dots[12][3]),
        .b(s1_dots[12][4]),
        .c(s1_dots[12][5]),
        .sum(s2_dots[12][4]),
        .carry(s2_dots[13][1])
    );
    full_adder FA9_stage2 (
        .a(s1_dots[12][6]),
        .b(s1_dots[12][7]),
        .c(s1_dots[12][8]),
        .sum(s2_dots[12][5]),
        .carry(s2_dots[13][2])
    );
    half_adder FA10_stage2 (
        .a(s1_dots[12][9]),
        .b(s1_dots[12][10]),
        .sum(s2_dots[12][6]),
        .carry(s2_dots[13][3])
    );
    assign s2_dots[12][8:7] = s1_dots[12][12:11];
    //Column 13
    full_adder FA11_stage2 (
        .a(s1_dots[13][0]),
        .b(s1_dots[13][1]),
        .c(s1_dots[13][2]),
        .sum(s2_dots[13][4]),
        .carry(s2_dots[14][0])
    );
    full_adder FA12_stage2 (
        .a(s1_dots[13][3]),
        .b(s1_dots[13][4]),
        .c(s1_dots[13][5]),
        .sum(s2_dots[13][5]),
        .carry(s2_dots[14][1])
    );
    full_adder FA13_stage2 (
        .a(s1_dots[13][6]),
        .b(s1_dots[13][7]),
        .c(s1_dots[13][8]),
        .sum(s2_dots[13][6]),
        .carry(s2_dots[14][2])
    );
    full_adder FA14_stage2 (
        .a(s1_dots[13][9]),
        .b(s1_dots[13][10]),
        .c(s1_dots[13][11]),
        .sum(s2_dots[13][7]),
        .carry(s2_dots[14][3])
    );
    assign s2_dots[13][8] = s1_dots[13][12];
    //Column 14
    full_adder FA15_stage2 (
        .a(s1_dots[14][0]),
        .b(s1_dots[14][1]),
        .c(s1_dots[14][2]),
        .sum(s2_dots[14][4]),
        .carry(s2_dots[15][0])
    );
    full_adder FA16_stage2 (
        .a(s1_dots[14][3]),
        .b(s1_dots[14][4]),
        .c(s1_dots[14][5]),
        .sum(s2_dots[14][5]),
        .carry(s2_dots[15][1])
    );
    full_adder FA17_stage2 (
        .a(s1_dots[14][6]),
        .b(s1_dots[14][7]),
        .c(s1_dots[14][8]),
        .sum(s2_dots[14][6]),
        .carry(s2_dots[15][2])
    );
    full_adder FA18_stage2 (
        .a(s1_dots[14][9]),
        .b(s1_dots[14][10]),
        .c(s1_dots[14][11]),
        .sum(s2_dots[14][7]),
        .carry(s2_dots[15][3])
    );
    assign s2_dots[14][8] = s1_dots[14][12];
    //Column 15
    full_adder FA19_stage2 (
        .a(s1_dots[15][0]),
        .b(s1_dots[15][1]),
        .c(s1_dots[15][2]),
        .sum(s2_dots[15][4]),
        .carry(s2_dots[16][0])
    );
    full_adder FA20_stage2 (
        .a(s1_dots[15][3]),
        .b(s1_dots[15][4]),
        .c(s1_dots[15][5]),
        .sum(s2_dots[15][5]),
        .carry(s2_dots[16][1])
    );
    full_adder FA21_stage2 (
        .a(s1_dots[15][6]),
        .b(s1_dots[15][7]),
        .c(s1_dots[15][8]),
        .sum(s2_dots[15][6]),
        .carry(s2_dots[16][2])
    );
    full_adder FA22_stage2 (
        .a(s1_dots[15][9]),
        .b(s1_dots[15][10]),
        .c(s1_dots[15][11]),
        .sum(s2_dots[15][7]),
        .carry(s2_dots[16][3])
    );
    assign s2_dots[15][8] = s1_dots[15][12];
    //Column 16
    full_adder FA23_stage2 (
        .a(s1_dots[16][0]),
        .b(s1_dots[16][1]),
        .c(s1_dots[16][2]),
        .sum(s2_dots[16][4]),
        .carry(s2_dots[17][0])
    );
    full_adder FA24_stage2 (
        .a(s1_dots[16][3]),
        .b(s1_dots[16][4]),
        .c(s1_dots[16][5]),
        .sum(s2_dots[16][5]),
        .carry(s2_dots[17][1])
    );
    full_adder FA25_stage2 (
        .a(s1_dots[16][6]),
        .b(s1_dots[16][7]),
        .c(s1_dots[16][8]),
        .sum(s2_dots[16][6]),
        .carry(s2_dots[17][2])
    );
    full_adder FA26_stage2 (
        .a(s1_dots[16][9]),
        .b(s1_dots[16][10]),
        .c(s1_dots[16][11]),
        .sum(s2_dots[16][7]),
        .carry(s2_dots[17][3])
    );
    assign s2_dots[16][8] = s1_dots[16][12];
    //Column 17
    full_adder FA27_stage2 (
        .a(s1_dots[17][0]),
        .b(s1_dots[17][1]),
        .c(s1_dots[17][2]),
        .sum(s2_dots[17][4]),
        .carry(s2_dots[18][0])
    );
    full_adder FA28_stage2 (
        .a(s1_dots[17][3]),
        .b(s1_dots[17][4]),
        .c(s1_dots[17][5]),
        .sum(s2_dots[17][5]),
        .carry(s2_dots[18][1])
    );
    full_adder FA29_stage2 (
        .a(s1_dots[17][6]),
        .b(s1_dots[17][7]),
        .c(s1_dots[17][8]),
        .sum(s2_dots[17][6]),
        .carry(s2_dots[18][2])
    );
    full_adder FA30_stage2 (
        .a(s1_dots[17][9]),
        .b(s1_dots[17][10]),
        .c(s1_dots[17][11]),
        .sum(s2_dots[17][7]),
        .carry(s2_dots[18][3])
    );
    assign s2_dots[17][8] = s1_dots[17][12];
    //Column 18
    full_adder FA31_stage2 (
        .a(s1_dots[18][0]),
        .b(s1_dots[18][1]),
        .c(s1_dots[18][2]),
        .sum(s2_dots[18][4]),
        .carry(s2_dots[19][0])
    );
    full_adder FA32_stage2 (
        .a(s1_dots[18][3]),
        .b(s1_dots[18][4]),
        .c(s1_dots[18][5]),
        .sum(s2_dots[18][5]),
        .carry(s2_dots[19][1])
    );
    full_adder FA33_stage2 (
        .a(s1_dots[18][6]),
        .b(s1_dots[18][7]),
        .c(s1_dots[18][8]),
        .sum(s2_dots[18][6]),
        .carry(s2_dots[19][2])
    );
    full_adder FA34_stage2 (
        .a(s1_dots[18][9]),
        .b(s1_dots[18][10]),
        .c(s1_dots[18][11]),
        .sum(s2_dots[18][7]),
        .carry(s2_dots[19][3])
    );
    assign s2_dots[18][8] = s1_dots[18][12];

    //Column 19
    full_adder FA35_stage2 (
        .a(s1_dots[19][0]),
        .b(s1_dots[19][1]),
        .c(s1_dots[19][2]),
        .sum(s2_dots[19][4]),
        .carry(s2_dots[20][0])
    );
    full_adder FA36_stage2 (
        .a(s1_dots[19][3]),
        .b(s1_dots[19][4]),
        .c(s1_dots[19][5]),
        .sum(s2_dots[19][5]),
        .carry(s2_dots[20][1])
    );
    full_adder FA37_stage2 (
        .a(s1_dots[19][6]),
        .b(s1_dots[19][7]),
        .c(s1_dots[19][8]),
        .sum(s2_dots[19][6]),
        .carry(s2_dots[20][2])
    );
    full_adder FA38_stage2 (
        .a(s1_dots[19][9]),
        .b(s1_dots[19][10]),
        .c(s1_dots[19][11]),
        .sum(s2_dots[19][7]),
        .carry(s2_dots[20][3])
    );
    assign s2_dots[19][8] = s1_dots[19][12];
    //Column 20
    full_adder FA39_stage2 (
        .a(s1_dots[20][2]),
        .b(s1_dots[20][3]),
        .c(s1_dots[20][4]),
        .sum(s2_dots[20][4]),
        .carry(s2_dots[21][0])
    );
    full_adder FA40_stage2 (
        .a(s1_dots[20][5]),
        .b(s1_dots[20][6]),
        .c(s1_dots[20][7]),
        .sum(s2_dots[20][5]),
        .carry(s2_dots[21][1])
    );
    full_adder FA41_stage2 (
        .a(s1_dots[20][8]),
        .b(s1_dots[20][9]),
        .c(s1_dots[20][10]),
        .sum(s2_dots[20][6]),
        .carry(s2_dots[21][2])
    );
    assign s2_dots[20][8:7] = s1_dots[20][12:11];
    //Column 21
    full_adder FA42_stage2 (
        .a(s1_dots[21][3]),
        .b(s1_dots[21][4]),
        .c(s1_dots[21][5]),
        .sum(s2_dots[21][3]),
        .carry(s2_dots[22][0])
    );
    full_adder FA43_stage2 (
        .a(s1_dots[21][6]),
        .b(s1_dots[21][7]),
        .c(s1_dots[21][8]),
        .sum(s2_dots[21][4]),
        .carry(s2_dots[22][1])
    );
    assign s2_dots[21][8:5] = s1_dots[21][12:9];
    //Column 22
    full_adder FA44_stage2 (
        .a(s1_dots[22][4]),
        .b(s1_dots[22][5]),
        .c(s1_dots[22][6]),
        .sum(s2_dots[22][2]),
        .carry(s2_dots[23][0])
    );
    assign s2_dots[22][8:3] = s1_dots[22][12:7];
//////////////////////stage_2 end//////////////////////
////////////////////stage_3//////////////////////
    generate
        for (j = 0; j < 6; j = j + 1) begin : COLUMNS_6
            for (i = 0; i < 6; i = i + 1) begin : HEIGHTS_6
                assign s3_dots[j][i] = s2_dots[j][i];
            end
        end
    endgenerate
    generate
        for (i = 27; i < 32; i = i + 1) begin : COLUMNS_7
            for (j = 0; j < 6; j = j + 1) begin : HEIGHTS_7
                assign s3_dots[i][5 - j] = s2_dots[i][8 - j];
            end
        end 
    endgenerate
    generate
        for (i = 0; i < 5; i = i + 1) begin : HEIGHT_8
            assign s3_dots[26][5 - i] = s2_dots[26][8 - i];
        end
    endgenerate
    //Column 6
    half_adder FA1_stage3 (
        .a(s2_dots[6][0]),
        .b(s2_dots[6][1]),
        .sum(s3_dots[6][0]),
        .carry(s3_dots[7][0])
    );
    assign s3_dots[6][5:1] = s2_dots[6][6:2];
    //Column 7
    full_adder FA2_stage3 (
        .a(s2_dots[7][0]),
        .b(s2_dots[7][1]),
        .c(s2_dots[7][2]),
        .sum(s3_dots[7][1]),
        .carry(s3_dots[8][0])
    );
    half_adder FA3_stage3 (
        .a(s2_dots[7][3]),
        .b(s2_dots[7][4]),
        .sum(s3_dots[7][2]),
        .carry(s3_dots[8][1])
    );
    assign s3_dots[7][5:3] = s2_dots[7][7:5];
    //Column 8
    full_adder FA4_stage3 (
        .a(s2_dots[8][0]),
        .b(s2_dots[8][1]),
        .c(s2_dots[8][2]),
        .sum(s3_dots[8][2]),
        .carry(s3_dots[9][0])
    );
    full_adder FA5_stage3 (
        .a(s2_dots[8][3]),
        .b(s2_dots[8][4]),
        .c(s2_dots[8][5]),
        .sum(s3_dots[8][3]),
        .carry(s3_dots[9][1])
    );
    half_adder FA6_stage3 (
        .a(s2_dots[8][6]),
        .b(s2_dots[8][7]),
        .sum(s3_dots[8][4]),
        .carry(s3_dots[9][2])
    );
    assign s3_dots[8][5] = s2_dots[8][8];
    //Column 9
    full_adder FA7_stage3 (
        .a(s2_dots[9][0]),
        .b(s2_dots[9][1]),
        .c(s2_dots[9][2]),
        .sum(s3_dots[9][3]),
        .carry(s3_dots[10][0])
    );
    full_adder FA8_stage3 (
        .a(s2_dots[9][3]),
        .b(s2_dots[9][4]),
        .c(s2_dots[9][5]),
        .sum(s3_dots[9][4]),
        .carry(s3_dots[10][1])
    );
    full_adder FA9_stage3 (
        .a(s2_dots[9][6]),
        .b(s2_dots[9][7]),
        .c(s2_dots[9][8]),
        .sum(s3_dots[9][5]),
        .carry(s3_dots[10][2])
    );
    //Column 10
    full_adder FA10_stage3 (
        .a(s2_dots[10][0]),
        .b(s2_dots[10][1]),
        .c(s2_dots[10][2]),
        .sum(s3_dots[10][3]),
        .carry(s3_dots[11][0])
    );
    full_adder FA11_stage3 (
        .a(s2_dots[10][3]),
        .b(s2_dots[10][4]),
        .c(s2_dots[10][5]),
        .sum(s3_dots[10][4]),
        .carry(s3_dots[11][1])
    );
    full_adder FA12_stage3 (
        .a(s2_dots[10][6]),
        .b(s2_dots[10][7]),
        .c(s2_dots[10][8]),
        .sum(s3_dots[10][5]),
        .carry(s3_dots[11][2])
    );
    //Column 11
    full_adder FA13_stage3 (
        .a(s2_dots[11][0]),
        .b(s2_dots[11][1]),
        .c(s2_dots[11][2]),
        .sum(s3_dots[11][3]),
        .carry(s3_dots[12][0])
    );
    full_adder FA14_stage3 (
        .a(s2_dots[11][3]),
        .b(s2_dots[11][4]),
        .c(s2_dots[11][5]),
        .sum(s3_dots[11][4]),
        .carry(s3_dots[12][1])
    );
    full_adder FA15_stage3 (
        .a(s2_dots[11][6]),
        .b(s2_dots[11][7]),
        .c(s2_dots[11][8]),
        .sum(s3_dots[11][5]),
        .carry(s3_dots[12][2])
    );
    //Column 12
    full_adder FA16_stage3 (
        .a(s2_dots[12][0]),
        .b(s2_dots[12][1]),
        .c(s2_dots[12][2]),
        .sum(s3_dots[12][3]),
        .carry(s3_dots[13][0])
    );
    full_adder FA17_stage3 (
        .a(s2_dots[12][3]),
        .b(s2_dots[12][4]),
        .c(s2_dots[12][5]),
        .sum(s3_dots[12][4]),
        .carry(s3_dots[13][1])
    );
    full_adder FA18_stage3 (
        .a(s2_dots[12][6]),
        .b(s2_dots[12][7]),
        .c(s2_dots[12][8]),
        .sum(s3_dots[12][5]),
        .carry(s3_dots[13][2])
    );
    //Column 13
    full_adder FA19_stage3 (
        .a(s2_dots[13][0]),
        .b(s2_dots[13][1]),
        .c(s2_dots[13][2]),
        .sum(s3_dots[13][3]),
        .carry(s3_dots[14][0])
    );
    full_adder FA20_stage3 (
        .a(s2_dots[13][3]),
        .b(s2_dots[13][4]),
        .c(s2_dots[13][5]),
        .sum(s3_dots[13][4]),
        .carry(s3_dots[14][1])
    );
    full_adder FA21_stage3 (
        .a(s2_dots[13][6]),
        .b(s2_dots[13][7]),
        .c(s2_dots[13][8]),
        .sum(s3_dots[13][5]),
        .carry(s3_dots[14][2])
    );
    //Column 14
    full_adder FA22_stage3 (
        .a(s2_dots[14][0]),
        .b(s2_dots[14][1]),
        .c(s2_dots[14][2]),
        .sum(s3_dots[14][3]),
        .carry(s3_dots[15][0])
    );
    full_adder FA23_stage3 (
        .a(s2_dots[14][3]),
        .b(s2_dots[14][4]),
        .c(s2_dots[14][5]),
        .sum(s3_dots[14][4]),
        .carry(s3_dots[15][1])
    );
    full_adder FA24_stage3 (
        .a(s2_dots[14][6]),
        .b(s2_dots[14][7]),
        .c(s2_dots[14][8]),
        .sum(s3_dots[14][5]),
        .carry(s3_dots[15][2])
    );
    //Column 15
    full_adder FA25_stage3 (    
        .a(s2_dots[15][0]),
        .b(s2_dots[15][1]),
        .c(s2_dots[15][2]),
        .sum(s3_dots[15][3]),
        .carry(s3_dots[16][0])
    );
    full_adder FA26_stage3 (
        .a(s2_dots[15][3]),
        .b(s2_dots[15][4]),
        .c(s2_dots[15][5]),
        .sum(s3_dots[15][4]),
        .carry(s3_dots[16][1])
    );
    full_adder FA27_stage3 (
        .a(s2_dots[15][6]),
        .b(s2_dots[15][7]),
        .c(s2_dots[15][8]),
        .sum(s3_dots[15][5]),
        .carry(s3_dots[16][2])
    );
    //Column 16
    full_adder FA28_stage3 (
        .a(s2_dots[16][0]),
        .b(s2_dots[16][1]),
        .c(s2_dots[16][2]),
        .sum(s3_dots[16][3]),
        .carry(s3_dots[17][0])
    );
    full_adder FA29_stage3 (
        .a(s2_dots[16][3]),
        .b(s2_dots[16][4]),
        .c(s2_dots[16][5]),
        .sum(s3_dots[16][4]),
        .carry(s3_dots[17][1])
    );
    full_adder FA30_stage3 (
        .a(s2_dots[16][6]),
        .b(s2_dots[16][7]),
        .c(s2_dots[16][8]),
        .sum(s3_dots[16][5]),
        .carry(s3_dots[17][2])
    );
    //Column 17
    full_adder FA31_stage3 (
        .a(s2_dots[17][0]),
        .b(s2_dots[17][1]),
        .c(s2_dots[17][2]),
        .sum(s3_dots[17][3]),
        .carry(s3_dots[18][0])
    );
    full_adder FA32_stage3 (
        .a(s2_dots[17][3]),
        .b(s2_dots[17][4]),
        .c(s2_dots[17][5]),
        .sum(s3_dots[17][4]),
        .carry(s3_dots[18][1])
    );
    full_adder FA33_stage3 (
        .a(s2_dots[17][6]),
        .b(s2_dots[17][7]),
        .c(s2_dots[17][8]),
        .sum(s3_dots[17][5]),
        .carry(s3_dots[18][2])
    );
    //Column 18
    full_adder FA34_stage3 (
        .a(s2_dots[18][0]),
        .b(s2_dots[18][1]),
        .c(s2_dots[18][2]),
        .sum(s3_dots[18][3]),
        .carry(s3_dots[19][0])
    );
    full_adder FA35_stage3 (
        .a(s2_dots[18][3]),
        .b(s2_dots[18][4]),
        .c(s2_dots[18][5]),
        .sum(s3_dots[18][4]),
        .carry(s3_dots[19][1])
    );
    full_adder FA36_stage3 (
        .a(s2_dots[18][6]),
        .b(s2_dots[18][7]),
        .c(s2_dots[18][8]),
        .sum(s3_dots[18][5]),
        .carry(s3_dots[19][2])
    );
    //Column 19
    full_adder FA37_stage3 (
        .a(s2_dots[19][0]),
        .b(s2_dots[19][1]),
        .c(s2_dots[19][2]),
        .sum(s3_dots[19][3]),
        .carry(s3_dots[20][0])
    );
    full_adder FA38_stage3 (
        .a(s2_dots[19][3]),
        .b(s2_dots[19][4]),
        .c(s2_dots[19][5]),
        .sum(s3_dots[19][4]),
        .carry(s3_dots[20][1])
    );
    full_adder FA39_stage3 (
        .a(s2_dots[19][6]),
        .b(s2_dots[19][7]),
        .c(s2_dots[19][8]),
        .sum(s3_dots[19][5]),
        .carry(s3_dots[20][2])
    );
    //Column 20
    full_adder FA40_stage3 (
        .a(s2_dots[20][0]),
        .b(s2_dots[20][1]),
        .c(s2_dots[20][2]),
        .sum(s3_dots[20][3]),
        .carry(s3_dots[21][0])
    );
    full_adder FA41_stage3 (
        .a(s2_dots[20][3]),
        .b(s2_dots[20][4]),
        .c(s2_dots[20][5]),
        .sum(s3_dots[20][4]),
        .carry(s3_dots[21][1])
    );
    full_adder FA42_stage3 (
        .a(s2_dots[20][6]),
        .b(s2_dots[20][7]),
        .c(s2_dots[20][8]),
        .sum(s3_dots[20][5]),
        .carry(s3_dots[21][2])
    );
    //Column 21
    full_adder FA43_stage3 (
        .a(s2_dots[21][0]),
        .b(s2_dots[21][1]),
        .c(s2_dots[21][2]),
        .sum(s3_dots[21][3]),
        .carry(s3_dots[22][0])
    );
    full_adder FA44_stage3 (
        .a(s2_dots[21][3]),
        .b(s2_dots[21][4]),
        .c(s2_dots[21][5]),
        .sum(s3_dots[21][4]),
        .carry(s3_dots[22][1])
    );
    full_adder FA45_stage3 (
        .a(s2_dots[21][6]),
        .b(s2_dots[21][7]),
        .c(s2_dots[21][8]),
        .sum(s3_dots[21][5]),
        .carry(s3_dots[22][2])
    );
    //Column 22
    full_adder FA46_stage3 (
        .a(s2_dots[22][0]),
        .b(s2_dots[22][1]),
        .c(s2_dots[22][2]),
        .sum(s3_dots[22][3]),
        .carry(s3_dots[23][0])
    );
    full_adder FA47_stage3 (
        .a(s2_dots[22][3]),
        .b(s2_dots[22][4]),
        .c(s2_dots[22][5]),
        .sum(s3_dots[22][4]),
        .carry(s3_dots[23][1])
    );
    full_adder FA48_stage3 (
        .a(s2_dots[22][6]),
        .b(s2_dots[22][7]),
        .c(s2_dots[22][8]),
        .sum(s3_dots[22][5]),
        .carry(s3_dots[23][2])
    );
    //Column 23
    full_adder FA49_stage3 (
        .a(s2_dots[23][0]),
        .b(s2_dots[23][1]),
        .c(s2_dots[23][2]),
        .sum(s3_dots[23][3]),
        .carry(s3_dots[24][0])
    );
    full_adder FA50_stage3 (
        .a(s2_dots[23][3]),
        .b(s2_dots[23][4]),
        .c(s2_dots[23][5]),
        .sum(s3_dots[23][4]),
        .carry(s3_dots[24][1])
    );
    full_adder FA51_stage3 (
        .a(s2_dots[23][6]),
        .b(s2_dots[23][7]),
        .c(s2_dots[23][8]),
        .sum(s3_dots[23][5]),
        .carry(s3_dots[24][2])
    );
    //Column 24
    full_adder FA52_stage3 (
        .a(s2_dots[24][2]),
        .b(s2_dots[24][3]),
        .c(s2_dots[24][4]),
        .sum(s3_dots[24][3]),
        .carry(s3_dots[25][0])
    );
    full_adder FA53_stage3 (
        .a(s2_dots[24][5]),
        .b(s2_dots[24][6]),
        .c(s2_dots[24][7]),
        .sum(s3_dots[24][4]),
        .carry(s3_dots[25][1])
    );
    assign s3_dots[24][5] = s2_dots[24][8];
    //Column 25
    full_adder FA54_stage3 (
        .a(s2_dots[25][3]),
        .b(s2_dots[25][4]),
        .c(s2_dots[25][5]),
        .sum(s3_dots[25][2]),
        .carry(s3_dots[26][0])
    );
    assign s3_dots[25][5:3] = s2_dots[25][8:6];
////////////////////////stage_3 end//////////////////////
/////////////////////stage_4/////////////////////////
    generate
        for (j = 0; j < 4; j = j + 1) begin : COLUMNS_9
            for (i = 0; i < 4; i = i + 1) begin : HEIGHTS_9
                assign s4_dots[j][i] = s3_dots[j][i];
            end
        end
    endgenerate
    generate
        for (i = 29; i < 32; i = i + 1) begin : COLUMNS_10
            for (j = 0; j < 4; j = j + 1) begin : HEIGHTS_10
                assign s4_dots[i][3 - j] = s3_dots[i][5 - j];
            end
        end 
    endgenerate
    generate
        for (i = 0; i < 3; i = i + 1) begin : HEIGHT_11
            assign s4_dots[28][3 - i] = s3_dots[28][5 - i];
        end
    endgenerate

    //Column 4
    half_adder FA1_stage4 (
        .a(s3_dots[4][0]),
        .b(s3_dots[4][1]),
        .sum(s4_dots[4][0]),
        .carry(s4_dots[5][0])
    );
    assign s4_dots[4][3:1] = s3_dots[4][4:2];
    //Column 5
    full_adder FA2_stage4 (
        .a(s3_dots[5][0]),
        .b(s3_dots[5][1]),
        .c(s3_dots[5][2]),
        .sum(s4_dots[5][1]),
        .carry(s4_dots[6][0])
    );
    half_adder FA3_stage4 (
        .a(s3_dots[5][3]),
        .b(s3_dots[5][4]),
        .sum(s4_dots[5][2]),
        .carry(s4_dots[6][1])
    );
    assign s4_dots[5][3] = s3_dots[5][5];
    //Column 6
    full_adder FA4_stage4 (     
        .a(s3_dots[6][0]),
        .b(s3_dots[6][1]),
        .c(s3_dots[6][2]),
        .sum(s4_dots[6][2]),
        .carry(s4_dots[7][0])
    );
    full_adder FA5_stage4 (
        .a(s3_dots[6][3]),
        .b(s3_dots[6][4]),
        .c(s3_dots[6][5]),
        .sum(s4_dots[6][3]),
        .carry(s4_dots[7][1])
    );
    //Column 7
    full_adder FA6_stage4 (
        .a(s3_dots[7][0]),
        .b(s3_dots[7][1]),
        .c(s3_dots[7][2]),
        .sum(s4_dots[7][2]),
        .carry(s4_dots[8][0])
    );
    full_adder FA7_stage4 (
        .a(s3_dots[7][3]),
        .b(s3_dots[7][4]),
        .c(s3_dots[7][5]),
        .sum(s4_dots[7][3]),
        .carry(s4_dots[8][1])
    );
    //Column 8
    full_adder FA8_stage4 (
        .a(s3_dots[8][0]),
        .b(s3_dots[8][1]),
        .c(s3_dots[8][2]),
        .sum(s4_dots[8][2]),
        .carry(s4_dots[9][0])
    );
    full_adder FA9_stage4 (
        .a(s3_dots[8][3]),
        .b(s3_dots[8][4]),
        .c(s3_dots[8][5]),
        .sum(s4_dots[8][3]),
        .carry(s4_dots[9][1])
    );
    //Column 9
    full_adder FA10_stage4 (
        .a(s3_dots[9][0]),
        .b(s3_dots[9][1]),
        .c(s3_dots[9][2]),
        .sum(s4_dots[9][2]),
        .carry(s4_dots[10][0])
    );  
    full_adder FA11_stage4 (
        .a(s3_dots[9][3]),
        .b(s3_dots[9][4]),
        .c(s3_dots[9][5]),
        .sum(s4_dots[9][3]),
        .carry(s4_dots[10][1])
    );
    //Column 10
    full_adder FA12_stage4 (
        .a(s3_dots[10][0]),
        .b(s3_dots[10][1]),
        .c(s3_dots[10][2]),
        .sum(s4_dots[10][2]),
        .carry(s4_dots[11][0])
    );  
    full_adder FA13_stage4 (
        .a(s3_dots[10][3]),
        .b(s3_dots[10][4]),
        .c(s3_dots[10][5]),
        .sum(s4_dots[10][3]),
        .carry(s4_dots[11][1])
    );
    //Column 11
    full_adder FA14_stage4 (
        .a(s3_dots[11][0]),
        .b(s3_dots[11][1]),
        .c(s3_dots[11][2]),
        .sum(s4_dots[11][2]),
        .carry(s4_dots[12][0])
    );
    full_adder FA15_stage4 (
        .a(s3_dots[11][3]),
        .b(s3_dots[11][4]),
        .c(s3_dots[11][5]),
        .sum(s4_dots[11][3]),
        .carry(s4_dots[12][1])
    );
    //Column 12
    full_adder FA16_stage4 (
        .a(s3_dots[12][0]),
        .b(s3_dots[12][1]),
        .c(s3_dots[12][2]),
        .sum(s4_dots[12][2]),
        .carry(s4_dots[13][0])
    );
    full_adder FA17_stage4 (
        .a(s3_dots[12][3]),
        .b(s3_dots[12][4]),
        .c(s3_dots[12][5]),
        .sum(s4_dots[12][3]),
        .carry(s4_dots[13][1])
    );
    //Column 13
    full_adder FA18_stage4 (
        .a(s3_dots[13][0]),
        .b(s3_dots[13][1]),
        .c(s3_dots[13][2]),
        .sum(s4_dots[13][2]),
        .carry(s4_dots[14][0])
    );
    full_adder FA19_stage4 (
        .a(s3_dots[13][3]),
        .b(s3_dots[13][4]),
        .c(s3_dots[13][5]),
        .sum(s4_dots[13][3]),
        .carry(s4_dots[14][1])
    );
    //Column 14
    full_adder FA20_stage4 (
        .a(s3_dots[14][0]),
        .b(s3_dots[14][1]),
        .c(s3_dots[14][2]),
        .sum(s4_dots[14][2]),
        .carry(s4_dots[15][0])
    );
    full_adder FA21_stage4 (
        .a(s3_dots[14][3]),
        .b(s3_dots[14][4]),
        .c(s3_dots[14][5]),
        .sum(s4_dots[14][3]),
        .carry(s4_dots[15][1])
    );
    //Column 15
    full_adder FA22_stage4 (
        .a(s3_dots[15][0]),
        .b(s3_dots[15][1]),
        .c(s3_dots[15][2]),
        .sum(s4_dots[15][2]),
        .carry(s4_dots[16][0])
    );
    full_adder FA23_stage4 (
        .a(s3_dots[15][3]),
        .b(s3_dots[15][4]),
        .c(s3_dots[15][5]),
        .sum(s4_dots[15][3]),
        .carry(s4_dots[16][1])
    );
    //Column 16
    full_adder FA24_stage4 (
        .a(s3_dots[16][0]),
        .b(s3_dots[16][1]),
        .c(s3_dots[16][2]),
        .sum(s4_dots[16][2]),
        .carry(s4_dots[17][0])
    );  
    full_adder FA25_stage4 (
        .a(s3_dots[16][3]),
        .b(s3_dots[16][4]),
        .c(s3_dots[16][5]),
        .sum(s4_dots[16][3]),
        .carry(s4_dots[17][1])
    );
    //Column 17
    full_adder FA26_stage4 (
        .a(s3_dots[17][0]),
        .b(s3_dots[17][1]),
        .c(s3_dots[17][2]),
        .sum(s4_dots[17][2]),
        .carry(s4_dots[18][0])
    );
    full_adder FA27_stage4 (
        .a(s3_dots[17][3]),
        .b(s3_dots[17][4]),
        .c(s3_dots[17][5]),
        .sum(s4_dots[17][3]),
        .carry(s4_dots[18][1])
    );
    //Column 18
    full_adder FA28_stage4 (
        .a(s3_dots[18][0]),
        .b(s3_dots[18][1]),
        .c(s3_dots[18][2]),
        .sum(s4_dots[18][2]),
        .carry(s4_dots[19][0])
    );
    full_adder FA29_stage4 (
        .a(s3_dots[18][3]),
        .b(s3_dots[18][4]),
        .c(s3_dots[18][5]),
        .sum(s4_dots[18][3]),
        .carry(s4_dots[19][1])
    );
    //Column 19
    full_adder FA30_stage4 (
        .a(s3_dots[19][0]),
        .b(s3_dots[19][1]),
        .c(s3_dots[19][2]),
        .sum(s4_dots[19][2]),
        .carry(s4_dots[20][0])
    );
    full_adder FA31_stage4 (
        .a(s3_dots[19][3]),
        .b(s3_dots[19][4]),
        .c(s3_dots[19][5]),
        .sum(s4_dots[19][3]),
        .carry(s4_dots[20][1])
    );
    //Column 20
    full_adder FA32_stage4 (
        .a(s3_dots[20][0]),
        .b(s3_dots[20][1]),
        .c(s3_dots[20][2]),
        .sum(s4_dots[20][2]),
        .carry(s4_dots[21][0])
    );
    full_adder FA33_stage4 (
        .a(s3_dots[20][3]),
        .b(s3_dots[20][4]),
        .c(s3_dots[20][5]),
        .sum(s4_dots[20][3]),
        .carry(s4_dots[21][1])
    );
    //Column 21
    full_adder FA34_stage4 (
        .a(s3_dots[21][0]),
        .b(s3_dots[21][1]),
        .c(s3_dots[21][2]),
        .sum(s4_dots[21][2]),
        .carry(s4_dots[22][0])
    );
    full_adder FA35_stage4 (
        .a(s3_dots[21][3]),
        .b(s3_dots[21][4]),
        .c(s3_dots[21][5]),
        .sum(s4_dots[21][3]),
        .carry(s4_dots[22][1])
    );
    //Column 22
    full_adder FA36_stage4 (
        .a(s3_dots[22][0]),
        .b(s3_dots[22][1]),
        .c(s3_dots[22][2]),
        .sum(s4_dots[22][2]),
        .carry(s4_dots[23][0])
    );
    full_adder FA37_stage4 (
        .a(s3_dots[22][3]),
        .b(s3_dots[22][4]),
        .c(s3_dots[22][5]),
        .sum(s4_dots[22][3]),
        .carry(s4_dots[23][1])
    );
    //Column 23
    full_adder FA38_stage4 (
        .a(s3_dots[23][0]),
        .b(s3_dots[23][1]),
        .c(s3_dots[23][2]),
        .sum(s4_dots[23][2]),
        .carry(s4_dots[24][0])
    );
    full_adder FA39_stage4 (
        .a(s3_dots[23][3]),
        .b(s3_dots[23][4]),
        .c(s3_dots[23][5]),
        .sum(s4_dots[23][3]),
        .carry(s4_dots[24][1])
    );
    //Column 24
    full_adder FA40_stage4 (
        .a(s3_dots[24][0]),
        .b(s3_dots[24][1]),
        .c(s3_dots[24][2]),
        .sum(s4_dots[24][2]),
        .carry(s4_dots[25][0])
    );
    full_adder FA41_stage4 (
        .a(s3_dots[24][3]),
        .b(s3_dots[24][4]),
        .c(s3_dots[24][5]),
        .sum(s4_dots[24][3]),
        .carry(s4_dots[25][1])
    );
    //Column 25
    full_adder FA42_stage4 (
        .a(s3_dots[25][0]),
        .b(s3_dots[25][1]),
        .c(s3_dots[25][2]),
        .sum(s4_dots[25][2]),
        .carry(s4_dots[26][0])
    );
    full_adder FA43_stage4 (
        .a(s3_dots[25][3]),
        .b(s3_dots[25][4]),
        .c(s3_dots[25][5]),
        .sum(s4_dots[25][3]),
        .carry(s4_dots[26][1])
    );
    //Column 26
    full_adder FA44_stage4 (
        .a(s3_dots[26][0]),
        .b(s3_dots[26][1]),
        .c(s3_dots[26][2]),
        .sum(s4_dots[26][2]),
        .carry(s4_dots[27][0])
    );
    full_adder FA45_stage4 (
        .a(s3_dots[26][3]),
        .b(s3_dots[26][4]),
        .c(s3_dots[26][5]),
        .sum(s4_dots[26][3]),
        .carry(s4_dots[27][1])
    );
    //Column 27
    full_adder FA46_stage4 (
        .a(s3_dots[27][2]),
        .b(s3_dots[27][3]),
        .c(s3_dots[27][4]),
        .sum(s4_dots[27][2]),
        .carry(s4_dots[28][0])
    );
    assign s4_dots[27][3] = s3_dots[27][5];
//////////////////////////stage_4 end//////////////////////
////////////////////////stage_5/////////////////////////
    generate
        for (j = 0; j < 3; j = j + 1) begin : COLUMNS_12
            for (i = 0; i < 3; i = i + 1) begin : HEIGHTS_12
                assign s5_dots[j][i] = s4_dots[j][i];
            end
        end
    endgenerate
    generate
        for (i = 30; i < 32; i = i + 1) begin : COLUMNS_13
            for (j = 0; j < 3; j = j + 1) begin : HEIGHTS_13
                assign s5_dots[i][2 - j] = s4_dots[i][3 - j];
            end
        end 
    endgenerate
    generate
        for (i = 0; i < 2; i = i + 1) begin : HEIGHT_14
            assign s5_dots[29][2 - i] = s4_dots[29][3 - i];
        end
    endgenerate
    //Column 3
    half_adder FA1_stage5 (
        .a(s4_dots[3][0]),
        .b(s4_dots[3][1]),
        .sum(s5_dots[3][0]),
        .carry(s5_dots[4][0])
    );  
    assign s5_dots[3][2:1] = s4_dots[3][3:2];
    //Column 4
    full_adder FA2_stage5 (
        .a(s4_dots[4][0]),
        .b(s4_dots[4][1]),
        .c(s4_dots[4][2]),
        .sum(s5_dots[4][1]),
        .carry(s5_dots[5][0])
    );
    assign s5_dots[4][2] = s4_dots[4][3];
    //Column 5
    full_adder FA3_stage5 (
        .a(s4_dots[5][0]),
        .b(s4_dots[5][1]),
        .c(s4_dots[5][2]),
        .sum(s5_dots[5][1]),
        .carry(s5_dots[6][0])
    );
    assign s5_dots[5][2] = s4_dots[5][3];
    //Column 6
    full_adder FA4_stage5 (     
        .a(s4_dots[6][0]),
        .b(s4_dots[6][1]),
        .c(s4_dots[6][2]),
        .sum(s5_dots[6][1]),
        .carry(s5_dots[7][0])
    );
    assign s5_dots[6][2] = s4_dots[6][3];
    //Column 7
    full_adder FA5_stage5 (
        .a(s4_dots[7][0]),
        .b(s4_dots[7][1]),
        .c(s4_dots[7][2]),
        .sum(s5_dots[7][1]),
        .carry(s5_dots[8][0])
    );
    assign s5_dots[7][2] = s4_dots[7][3];
    //Column 8
    full_adder FA6_stage5 (
        .a(s4_dots[8][0]),
        .b(s4_dots[8][1]),
        .c(s4_dots[8][2]),
        .sum(s5_dots[8][1]),
        .carry(s5_dots[9][0])
    );
    assign s5_dots[8][2] = s4_dots[8][3];
    //Column 9
    full_adder FA7_stage5 (
        .a(s4_dots[9][0]),
        .b(s4_dots[9][1]),
        .c(s4_dots[9][2]),
        .sum(s5_dots[9][1]),
        .carry(s5_dots[10][0])
    );
    assign s5_dots[9][2] = s4_dots[9][3];
    //Column 10
    full_adder FA8_stage5 (
        .a(s4_dots[10][0]),
        .b(s4_dots[10][1]),
        .c(s4_dots[10][2]),
        .sum(s5_dots[10][1]),
        .carry(s5_dots[11][0])
    );
    assign s5_dots[10][2] = s4_dots[10][3];
    //Column 11
    full_adder FA9_stage5 (
        .a(s4_dots[11][0]),
        .b(s4_dots[11][1]),
        .c(s4_dots[11][2]),
        .sum(s5_dots[11][1]),
        .carry(s5_dots[12][0])
    );
    assign s5_dots[11][2] = s4_dots[11][3];
    //Column 12
    full_adder FA10_stage5 (
        .a(s4_dots[12][0]),
        .b(s4_dots[12][1]),
        .c(s4_dots[12][2]),
        .sum(s5_dots[12][1]),
        .carry(s5_dots[13][0])
    );
    assign s5_dots[12][2] = s4_dots[12][3];
    //Column 13
    full_adder FA11_stage5 (
        .a(s4_dots[13][0]),
        .b(s4_dots[13][1]),
        .c(s4_dots[13][2]),
        .sum(s5_dots[13][1]),
        .carry(s5_dots[14][0])
    );
    assign s5_dots[13][2] = s4_dots[13][3];
    //Column 14
    full_adder FA12_stage5 (
        .a(s4_dots[14][0]),
        .b(s4_dots[14][1]),
        .c(s4_dots[14][2]),
        .sum(s5_dots[14][1]),
        .carry(s5_dots[15][0])
    );
    assign s5_dots[14][2] = s4_dots[14][3];
    //Column 15
    full_adder FA13_stage5 (
        .a(s4_dots[15][0]),
        .b(s4_dots[15][1]),
        .c(s4_dots[15][2]),
        .sum(s5_dots[15][1]),
        .carry(s5_dots[16][0])
    );
    assign s5_dots[15][2] = s4_dots[15][3];
    //Column 16
    full_adder FA14_stage5 (
        .a(s4_dots[16][0]),
        .b(s4_dots[16][1]),
        .c(s4_dots[16][2]),
        .sum(s5_dots[16][1]),
        .carry(s5_dots[17][0])
    );
    assign s5_dots[16][2] = s4_dots[16][3];
    //Column 17
    full_adder FA15_stage5 (
        .a(s4_dots[17][0]),
        .b(s4_dots[17][1]),
        .c(s4_dots[17][2]),
        .sum(s5_dots[17][1]),
        .carry(s5_dots[18][0])
    );
    assign s5_dots[17][2] = s4_dots[17][3];
    //Column 18
    full_adder FA16_stage5 (
        .a(s4_dots[18][0]),
        .b(s4_dots[18][1]),
        .c(s4_dots[18][2]),
        .sum(s5_dots[18][1]),
        .carry(s5_dots[19][0])
    );
    assign s5_dots[18][2] = s4_dots[18][3];
    //Column 19
    full_adder FA17_stage5 (
        .a(s4_dots[19][0]),
        .b(s4_dots[19][1]),
        .c(s4_dots[19][2]),
        .sum(s5_dots[19][1]),
        .carry(s5_dots[20][0])
    );
    assign s5_dots[19][2] = s4_dots[19][3];
    //Column 20
    full_adder FA18_stage5 (
        .a(s4_dots[20][0]),
        .b(s4_dots[20][1]),
        .c(s4_dots[20][2]),
        .sum(s5_dots[20][1]),
        .carry(s5_dots[21][0])
    );
    assign s5_dots[20][2] = s4_dots[20][3];
    //Column 21
    full_adder FA19_stage5 (
        .a(s4_dots[21][0]),
        .b(s4_dots[21][1]),
        .c(s4_dots[21][2]),
        .sum(s5_dots[21][1]),
        .carry(s5_dots[22][0])
    );
    assign s5_dots[21][2] = s4_dots[21][3];
    //Column 22
    full_adder FA20_stage5 (
        .a(s4_dots[22][0]),
        .b(s4_dots[22][1]),
        .c(s4_dots[22][2]),
        .sum(s5_dots[22][1]),
        .carry(s5_dots[23][0])
    );
    assign s5_dots[22][2] = s4_dots[22][3];
    //Column 23
    full_adder FA21_stage5 (
        .a(s4_dots[23][0]),
        .b(s4_dots[23][1]),
        .c(s4_dots[23][2]),
        .sum(s5_dots[23][1]),
        .carry(s5_dots[24][0])
    );
    assign s5_dots[23][2] = s4_dots[23][3];
    //Column 24
    full_adder FA22_stage5 (
        .a(s4_dots[24][0]),
        .b(s4_dots[24][1]),
        .c(s4_dots[24][2]),
        .sum(s5_dots[24][1]),
        .carry(s5_dots[25][0])
    );
    assign s5_dots[24][2] = s4_dots[24][3];
    //Column 25
    full_adder FA23_stage5 (
        .a(s4_dots[25][0]),
        .b(s4_dots[25][1]),
        .c(s4_dots[25][2]),
        .sum(s5_dots[25][1]),
        .carry(s5_dots[26][0])
    );
    assign s5_dots[25][2] = s4_dots[25][3];
    //Column 26
    full_adder FA24_stage5 (
        .a(s4_dots[26][0]),
        .b(s4_dots[26][1]),
        .c(s4_dots[26][2]),
        .sum(s5_dots[26][1]),
        .carry(s5_dots[27][0])
    );
    assign s5_dots[26][2] = s4_dots[26][3];
    //Column 27
    full_adder FA25_stage5 (
        .a(s4_dots[27][0]),
        .b(s4_dots[27][1]),
        .c(s4_dots[27][2]),
        .sum(s5_dots[27][1]),
        .carry(s5_dots[28][0])
    );
    assign s5_dots[27][2] = s4_dots[27][3];
        full_adder FA26_stage5 (
        .a(s4_dots[28][0]),
        .b(s4_dots[28][1]),
        .c(s4_dots[28][2]),
        .sum(s5_dots[28][1]),
        .carry(s5_dots[29][0])
    );
    assign s5_dots[28][2] = s4_dots[28][3];
//////////////////////////stage_5 end//////////////////////
///////////////////////////stage_6/////////////////////////
    generate
        for (j = 0; j < 2; j = j + 1) begin : COLUMNS_15
            for (i = 0; i < 2; i = i + 1) begin : HEIGHTS_15
                assign s6_dots[j][i] = s5_dots[j][i];
            end
        end
    endgenerate
    generate
        for (i = 31; i < 32; i = i + 1) begin : COLUMNS_16
            for (j = 0; j < 2; j = j + 1) begin : HEIGHTS_16
                assign s6_dots[i][1 - j] = s5_dots[i][2 - j];
            end
        end 
    endgenerate
    generate
        for (i = 0; i < 1; i = i + 1) begin : HEIGHT_17
            assign s6_dots[30][1 - i] = s5_dots[30][2 - i];
        end
    endgenerate
    //Column 2
    half_adder FA1_stage6 (
        .a(s5_dots[2][0]),
        .b(s5_dots[2][1]),
        .sum(s6_dots[2][0]),
        .carry(s6_dots[3][0])
    );
    assign s6_dots[2][1] = s5_dots[2][2];
    //Column 3
    full_adder FA2_stage6 (
        .a(s5_dots[3][0]),
        .b(s5_dots[3][1]),
        .c(s5_dots[3][2]),
        .sum(s6_dots[3][1]),
        .carry(s6_dots[4][0])
    );
    //Column 4
    full_adder FA3_stage6 (     
        .a(s5_dots[4][0]),
        .b(s5_dots[4][1]),
        .c(s5_dots[4][2]),
        .sum(s6_dots[4][1]),
        .carry(s6_dots[5][0])
    );
    //Column 5
    full_adder FA4_stage6 (     
        .a(s5_dots[5][0]),
        .b(s5_dots[5][1]),
        .c(s5_dots[5][2]),
        .sum(s6_dots[5][1]),
        .carry(s6_dots[6][0])
    );
    //Column 6
    full_adder FA5_stage6 (
        .a(s5_dots[6][0]),
        .b(s5_dots[6][1]),
        .c(s5_dots[6][2]),
        .sum(s6_dots[6][1]),
        .carry(s6_dots[7][0])
    );
    //Column 7
    full_adder FA6_stage6 (
        .a(s5_dots[7][0]),
        .b(s5_dots[7][1]),
        .c(s5_dots[7][2]),
        .sum(s6_dots[7][1]),
        .carry(s6_dots[8][0])
    );
    //Column 8
    full_adder FA7_stage6 (
        .a(s5_dots[8][0]),
        .b(s5_dots[8][1]),
        .c(s5_dots[8][2]),
        .sum(s6_dots[8][1]),
        .carry(s6_dots[9][0])
    );
    //Column 9
    full_adder FA8_stage6 (
        .a(s5_dots[9][0]),
        .b(s5_dots[9][1]),
        .c(s5_dots[9][2]),
        .sum(s6_dots[9][1]),
        .carry(s6_dots[10][0])
    );
    //Column 10
    full_adder FA9_stage6 (
        .a(s5_dots[10][0]),
        .b(s5_dots[10][1]),
        .c(s5_dots[10][2]),
        .sum(s6_dots[10][1]),
        .carry(s6_dots[11][0])
    );
    //Column 11
    full_adder FA10_stage6 (
        .a(s5_dots[11][0]),
        .b(s5_dots[11][1]),
        .c(s5_dots[11][2]),
        .sum(s6_dots[11][1]),
        .carry(s6_dots[12][0])
    );
    //Column 12
    full_adder FA11_stage6 (
        .a(s5_dots[12][0]),
        .b(s5_dots[12][1]),
        .c(s5_dots[12][2]),
        .sum(s6_dots[12][1]),
        .carry(s6_dots[13][0])
    );
    //Column 13
    full_adder FA12_stage6 (
        .a(s5_dots[13][0]),
        .b(s5_dots[13][1]),
        .c(s5_dots[13][2]),
        .sum(s6_dots[13][1]),
        .carry(s6_dots[14][0])
    );
    //Column 14
    full_adder FA13_stage6 (
        .a(s5_dots[14][0]),
        .b(s5_dots[14][1]),
        .c(s5_dots[14][2]),
        .sum(s6_dots[14][1]),
        .carry(s6_dots[15][0])
    );
    //Column 15
    full_adder FA14_stage6 (
        .a(s5_dots[15][0]),
        .b(s5_dots[15][1]),
        .c(s5_dots[15][2]),
        .sum(s6_dots[15][1]),
        .carry(s6_dots[16][0])
    );
    //Column 16
    full_adder FA15_stage6 (
        .a(s5_dots[16][0]),
        .b(s5_dots[16][1]),
        .c(s5_dots[16][2]),
        .sum(s6_dots[16][1]),
        .carry(s6_dots[17][0])
    );
    //Column 17
    full_adder FA16_stage6 (    
        .a(s5_dots[17][0]),
        .b(s5_dots[17][1]),
        .c(s5_dots[17][2]),
        .sum(s6_dots[17][1]),
        .carry(s6_dots[18][0])
    );
    //Column 18
    full_adder FA17_stage6 (
        .a(s5_dots[18][0]),
        .b(s5_dots[18][1]),
        .c(s5_dots[18][2]),
        .sum(s6_dots[18][1]),
        .carry(s6_dots[19][0])
    );
    //Column 19
    full_adder FA18_stage6 (
        .a(s5_dots[19][0]),
        .b(s5_dots[19][1]),
        .c(s5_dots[19][2]),
        .sum(s6_dots[19][1]),
        .carry(s6_dots[20][0])
    );
    //Column 20
    full_adder FA19_stage6 (
        .a(s5_dots[20][0]),
        .b(s5_dots[20][1]),
        .c(s5_dots[20][2]),
        .sum(s6_dots[20][1]),
        .carry(s6_dots[21][0])
    );
    //Column 21
    full_adder FA20_stage6 (
        .a(s5_dots[21][0]),
        .b(s5_dots[21][1]),
        .c(s5_dots[21][2]),
        .sum(s6_dots[21][1]),
        .carry(s6_dots[22][0])
    );
    //Column 22
    full_adder FA21_stage6 (
        .a(s5_dots[22][0]),
        .b(s5_dots[22][1]),
        .c(s5_dots[22][2]),
        .sum(s6_dots[22][1]),
        .carry(s6_dots[23][0])
    );
    //Column 23
    full_adder FA22_stage6 (
        .a(s5_dots[23][0]),
        .b(s5_dots[23][1]),
        .c(s5_dots[23][2]),
        .sum(s6_dots[23][1]),
        .carry(s6_dots[24][0])
    );
    //Column 24
    full_adder FA23_stage6 (
        .a(s5_dots[24][0]),
        .b(s5_dots[24][1]),
        .c(s5_dots[24][2]),
        .sum(s6_dots[24][1]),
        .carry(s6_dots[25][0])
    );
    //Column 25
    full_adder FA24_stage6 (
        .a(s5_dots[25][0]),
        .b(s5_dots[25][1]),
        .c(s5_dots[25][2]),
        .sum(s6_dots[25][1]),
        .carry(s6_dots[26][0])
    );
    //Column 26
    full_adder FA25_stage6 (
        .a(s5_dots[26][0]),
        .b(s5_dots[26][1]),
        .c(s5_dots[26][2]),
        .sum(s6_dots[26][1]),
        .carry(s6_dots[27][0])
    );
    //Column 27
    full_adder FA26_stage6 (
        .a(s5_dots[27][0]),
        .b(s5_dots[27][1]),
        .c(s5_dots[27][2]),
        .sum(s6_dots[27][1]),
        .carry(s6_dots[28][0])
    );
    //Column 28
    full_adder FA27_stage6 (
        .a(s5_dots[28][0]),
        .b(s5_dots[28][1]),
        .c(s5_dots[28][2]),
        .sum(s6_dots[28][1]),
        .carry(s6_dots[29][0])
    );
    //Column 29
    full_adder FA28_stage6 (
        .a(s5_dots[29][0]),
        .b(s5_dots[29][1]),
        .c(s5_dots[29][2]),
        .sum(s6_dots[29][1]),
        .carry(s6_dots[30][0])
    );

//////////////////////////stage_6 end//////////////////////

endmodule