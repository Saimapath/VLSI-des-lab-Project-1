module full_adder(
    input a, b, c,
    output sum, carry
);
    wire sum1, c1, c2;

    half_adder HA1 (a, b, sum1, c1);      // First Half Adder
    half_adder HA2 (sum1, c, sum, c2);  // Second Half Adder
    or U_OR (carry, c1, c2);               // OR the carry bits
endmodule