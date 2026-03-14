// Generic Pipeline Register Template
module pipe_reg #(parameter WIDTH = 32) (
    input clk, reset, en, clr,
    input  [WIDTH-1:0] d,
    output reg [WIDTH-1:0] q
);
    always @(posedge clk or posedge reset)
        if (reset)      q <= 0;
        else if (clr)   q <= 0;
        else if (en)    q <= d;
        // else q <= d;
endmodule