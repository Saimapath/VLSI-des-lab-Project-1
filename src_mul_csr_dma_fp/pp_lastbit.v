module pp_lastbit(
    input [15:0] A,
    input B,
    output [15:0] PP
);
    nand U1[14:0] (PP[14:0], A[14:0], B);
    and U2 (PP[15], A[15], B);
endmodule