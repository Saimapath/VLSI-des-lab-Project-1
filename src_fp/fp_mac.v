module fp_mac_pipelined (
    input  wire        clk,
    input  wire        rst_n,   
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [15:0] c,
    input  wire        add_sub, 
    input  wire [2:0]  rm,   
    
    output wire [15:0] mul_result,
    output reg  [15:0] result
);

    // --- MAC STAGE 1 & 2: PIPELINED MULTIPLIER ---
    wire [15:0] stage2_mul_result;
    
    fp16_multiplier u_mul (
        .clk(clk), .rst_n(rst_n),
        .a(a), .b(b), .rm(rm),
        .result(stage2_mul_result)
    );

    assign mul_result = stage2_mul_result;

    // =======================================================================
    // PIPELINE REGISTER 2 (Between Multiplier and Adder)
    // * CRITICAL: This severs the Multiplier's combinational normalization 
    //             logic from the Adder's combinational alignment logic!
    // =======================================================================
    reg [15:0] pipe_mul_res;
    reg [15:0] pipe_c;
    reg        pipe_add_sub;
    reg [2:0]  pipe_rm;

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_mul_res <= 16'd0;
            pipe_c       <= 16'd0;
            pipe_add_sub <= 1'b0;  
            pipe_rm      <= 3'd0;
        end else begin
            pipe_mul_res <= stage2_mul_result;
            pipe_c       <= c;
            pipe_add_sub <= add_sub;
            pipe_rm      <= rm;
        end
    end

    // --- MAC STAGE 3 & 4: ADDER ---
    wire [15:0] stage4_add_result;

    fp_adder_sub u_add (
        .clk(clk),              
        .rst_n(rst_n),
        .a(pipe_mul_res),       // ---> Safely registered!
        .b(pipe_c),             
        .add_sub(pipe_add_sub), 
        .rm(pipe_rm),     
        .result(stage4_add_result)
    );

    // =======================================================================
    // PIPELINE REGISTER 4 (Final Output)
    // =======================================================================
    always @(posedge clk ) begin
        if (!rst_n) begin
            result <= 16'd0;
        end else begin
            result <= stage4_add_result;
        end
    end

endmodule