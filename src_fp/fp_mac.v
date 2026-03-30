module fp_mac_pipelined (
    input  wire        clk,
    input  wire        rst_n,   // Active-low reset
    
    // Data Inputs (A * B + C)
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [15:0] c,
    
    // Control Inputs
    input  wire        add_sub, // 0 for Addition (+C), 1 for Subtraction (-C)
    input  wire [2:0]  rm,      // Rounding Mode
    
    // Pipelined Output
    output reg  [15:0] result
);

    // =======================================================================
    // STAGE 1: MULTIPLY (Combinational)
    // =======================================================================
    wire [15:0] stage1_mul_result;
    
    // Instantiate the combinational multiplier (from the previous step)
    fp16_multiplier u_mul (
        .a(a),
        .b(b),
        .rm(rm),
        .result(stage1_mul_result)
    );

    // =======================================================================
    // PIPELINE REGISTER 1 (Isolates Stage 1 from Stage 2)
    // =======================================================================
    reg [15:0] pipe_mul_res;
    reg [15:0] pipe_c;
    reg        pipe_add_sub;
    reg [2:0]  pipe_rm;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_mul_res <= 16'd0;
            pipe_c       <= 16'd0;
            pipe_add_sub <= 1'b0;
            pipe_rm      <= 3'd0;
        end else begin
            // Lock in the multiplier's result
            pipe_mul_res <= stage1_mul_result;
            
            // "Pass forward" the other inputs so they arrive at the adder 
            // at the exact same time as the multiplier's result.
            pipe_c       <= c;
            pipe_add_sub <= add_sub;
            pipe_rm      <= rm;
        end
    end

    // =======================================================================
    // STAGE 2: ADDITION (Combinational)
    // =======================================================================
    wire [15:0] stage2_add_result;

    // Instantiate your exact fp_adder_sub module here!
    fp_adder_sub u_add (
        .a(pipe_mul_res),       // The product from the pipeline register
        .b(pipe_c),             // The 'C' value from the pipeline register
        .add_sub(pipe_add_sub), 
        .rm(pipe_rm),     
        .result(stage2_add_result)
    );

    // =======================================================================
    // PIPELINE REGISTER 2 (Final Output to Writeback Stage)
    // =======================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 16'd0;
        end else begin
            // Lock in the final MAC result
            result <= stage2_add_result;
        end
    end

endmodule