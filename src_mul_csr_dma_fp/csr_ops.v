module csr_ops(
    input      [31:0] csr, rs1,
    input      [1:0]  op,
    output reg [31:0] csr_new  // Added 'reg' to allow procedural assignment
);

    always @(*) begin
        case(op)
            2'b01 :  csr_new = rs1;          // CSRRW (Write)
            2'b10 :  csr_new = csr | rs1;     // CSRRS (Set)
            2'b11 :  csr_new = csr & (~rs1);  // CSRRC (Clear)
            default: csr_new = csr;          // Maintain current value if no op
        endcase
    end

endmodule