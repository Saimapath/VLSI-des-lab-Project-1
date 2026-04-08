module multiplier_32bit (
    input [31:0] A, B,
    input [1:0]  funct3_low2, 
    input        clk, reset, start,
    output reg   busy,
    output reg [31:0] result_out
);
    reg [31:0] A_reg, B_reg;
    reg [63:0] Accumulator;
    reg [15:0] Mult_A, Mult_B;
    reg [1:0]  Mult_sign;
    wire [31:0] Mult_result;

    reg [1:0] sign_pipe1, sign_pipe2;
    wire active_sign_is_signed = sign_pipe2[0]; 

    // Reduced state count by merging accumulation and loading
    localparam IDLE   = 3'd0, 
               LL     = 3'd1, 
               HL     = 3'd2, 
               LH     = 3'd3, 
               HH     = 3'd4, 
               FINISH = 3'd5, 
               DONE   = 3'd6;

    reg [2:0] state;

    wire [47:0] add_slice;
    assign add_slice = Accumulator[63:16] + {{16{active_sign_is_signed & Mult_result[31]}}, Mult_result};

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state <= IDLE;
            busy <= 1'b0;
            Accumulator <= 64'd0;
            result_out <= 32'd0;
            sign_pipe1 <= 2'b00;
            sign_pipe2 <= 2'b00;
            A_reg <= 32'd0;
            B_reg <= 32'd0;
        end else begin
            sign_pipe1 <= Mult_sign;
            sign_pipe2 <= sign_pipe1;
            

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        Accumulator <= 64'd0;
                        busy <= 1'b1;
                        state <= LL;
                        // Load LL
                        Mult_A <= A[15:0];
                        Mult_B <= B[15:0];
                        Mult_sign <= 2'b00;
                        A_reg <= A;
                        B_reg <= B;
                    end
                end

                LL: begin
                    // Multiplier is working on LL...
                    // Load HL
                    Mult_A <= A_reg[31:16];
                    Mult_B <= B_reg[15:0];
                    Mult_sign <= (funct3_low2 == 2'b01 || funct3_low2 == 2'b10) ? 2'b01 : 2'b00;
                    state <= HL;
                end

                HL: begin
                    // Multiplier is working on HL... 
                    // LL result is still deep in the 16x16 pipeline.
                    // Load LH
                    if (funct3_low2 == 2'b01) begin
                        Mult_A <= B_reg[31:16]; 
                        Mult_B <= A_reg[15:0];  
                        Mult_sign <= 2'b01;
                    end else begin
                        Mult_A <= A_reg[15:0];
                        Mult_B <= B_reg[31:16];
                        Mult_sign <= 2'b00;
                    end
                    state <= LH;
                end

                LH: begin
                    // LL RESULT IS NOW READY (after 2 pipe stages)
                    Accumulator <= {32'd0, Mult_result}; 
                    
                    // Load HH
                    Mult_A <= A_reg[31:16];
                    Mult_B <= B_reg[31:16];
                    Mult_sign <= (funct3_low2 == 2'b01) ? 2'b11 : 
                                 (funct3_low2 == 2'b10) ? 2'b01 : 2'b00;
                    state <= HH;
                end

                HH: begin
                    // HL RESULT IS NOW READY
                    Accumulator[63:16] <= add_slice;
                    state <= FINISH;
                end

                FINISH: begin
                    // LH RESULT IS NOW READY
                    Accumulator[63:16] <= add_slice;
                    state <= DONE;
                end

                DONE: begin
                    // HH RESULT IS NOW READY
                    Accumulator[63:32] <= Accumulator[63:32] + Mult_result;
                    
                    // Assign output based on RISC-V rules
                    // We use the updated Accumulator value immediately here
                    if (funct3_low2 == 2'b00)
                        result_out <= Accumulator[31:0]; 
                    else
                        result_out <= Accumulator[63:32] + Mult_result;

                    busy <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end

    multiplier_16x16_signed U1 (
        .clk(clk), .reset(reset),
        .A(Mult_A), .B(Mult_B), .sign(Mult_sign),
        .PRODUCT(Mult_result)
    );
endmodule