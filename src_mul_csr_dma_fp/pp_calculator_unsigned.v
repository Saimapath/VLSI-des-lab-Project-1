module pp_calculator_unsigned(
    input [15:0] A,
    input B,
    output [15:0] PP
);
    and U1[15:0] (PP[15:0], A[15:0], B);
endmodule