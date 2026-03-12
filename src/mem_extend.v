module mem_extend(
    input  [31:0] in,
    input  [2:0]  loadbits,
    output reg [31:0] out
);
    always @(*)
        case(loadbits)
            3'b000: out = {{24{in[7]}}, in[7:0]};   // LB
            3'b001: out = {{16{in[15]}}, in[15:0]}; // LH
            3'b010: out = in;                       // LW
            3'b100: out = {24'b0, in[7:0]};        // LBU
            3'b101: out = {16'b0, in[15:0]};        // LHU
            default: out = 32'bx;
        endcase
endmodule