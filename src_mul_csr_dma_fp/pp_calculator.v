module pp_calculator(
    input [15:0] A,
    input B,
    output [15:0] PP
);
    and U1[14:0] (PP[14:0], A[14:0], B);
    nand U2 (PP[15], A[15], B);
endmodule