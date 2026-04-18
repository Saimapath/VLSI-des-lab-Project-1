module half_adder(
    input a,
    input b,
    output sum,
    output carry
);
    xor U1(sum, a, b);
    and U2(carry, a, b);
endmodule