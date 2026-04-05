module mem_extend(
    input  [31:0] in,
    input  [2:0]  loadbits, // matches funct3: [2]=unsigned, [1:0]=size (00=B, 01=H, 10=W)
    output [31:0] out
);
    wire unsig = loadbits[2];
    wire [1:0] size = loadbits[1:0];

    // 1. Lower byte NEVER changes for any load instruction. (0 LUTs, pure wire)
    assign out[7:0] = in[7:0];

    // 2. Second byte: Passed through for Half/Word. Extended from in[7] for Byte.
    // TRICK: (~unsig & in[7]) -> If unsigned, it forces 0. If signed, it passes in[7].
    assign out[15:8] = (size == 2'b00) ? {8{~unsig & in[7]}} : in[15:8];

    // 3. Upper halfword: Passed through for Word. Extended from in[15] or in[7].
    wire sign_bit = (size == 2'b01) ? in[15] : in[7];
    assign out[31:16] = (size == 2'b10) ? in[31:16] : {16{~unsig & sign_bit}};

endmodule