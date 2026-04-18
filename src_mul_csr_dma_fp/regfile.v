module regfile (
    input         clk,
    input         reset, // Added reset input
    input         we3,
    input  [4:0]  a1, a2, a3,
    input  [31:0] wd3,
    output [31:0] rd1, rd2
);
    reg [31:0] rf [31:1];
    integer i;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            // Synchronous reset for all registers
            for (i = 1; i < 32; i = i + 1) begin
                rf[i] <= 32'b0;
            end
        end else if (we3 && (a3 != 5'b0)) begin
            rf[a3] <= wd3; 
        end
    end

    // Internal forwarding logic remains unchanged
    assign rd1 = (a1 == 5'b0) ? 32'b0 : (we3 && (a1 == a3)) ? wd3 : rf[a1];
    assign rd2 = (a2 == 5'b0) ? 32'b0 : (we3 && (a2 == a3)) ? wd3 : rf[a2];
endmodule