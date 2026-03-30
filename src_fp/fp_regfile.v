module fp_regfile (
    input         clk,
    input         we4,
    input  [4:0]  a1, a2, a3,a4,
    input  [15:0] wd4,
    output [15:0] rd1, rd2,rd3
);
    reg [15:0] rf [15:1];

    always @(posedge clk) begin
        if (we4 && (a4 != 5'b0))
            rf[a4] <= wd4;
    end

    // INTERNAL FORWARDING: 
    // If reading the same register that is currently being written, 
    // bypass the array and output the write data (wd4) directly.
    assign rd1 = (a1 == 5'b0) ? 32'b0 : 
                 (we4 && (a1 == a4)) ? wd4 : 
                 rf[a1];

    assign rd2 = (a2 == 5'b0) ? 32'b0 : 
                 (we4 && (a2 == a4)) ? wd4 : 
                 rf[a2];
                 
    assign rd3 = (a3 == 5'b0) ? 32'b0 : 
                 (we4 && (a3 == a4)) ? wd4 :
                    rf[a3];
endmodule