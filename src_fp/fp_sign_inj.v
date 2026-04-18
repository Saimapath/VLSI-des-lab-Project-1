module fp_sign_inject (
    input  wire [15:0] rs1,
    input  wire [15:0] rs2,
    input  wire [2:0]  funct3, // Used to decode which sign injection to perform
    output reg  [15:0] result
);

    wire [14:0] magnitude = rs1[14:0]; // The bottom 15 bits always come from rs1
    wire sign_rs1 = rs1[15];
    wire sign_rs2 = rs2[15];

    always @(*) begin
        case (funct3)
            3'b000: // FSGNJ (Sign Inject): Result gets the sign of rs2
                result = {sign_rs2, magnitude};
                
            3'b001: // FSGNJN (Sign Inject Negate): Result gets the opposite sign of rs2
                result = {~sign_rs2, magnitude};
                
            3'b010: // FSGNJX (Sign Inject XOR): Result gets the XOR of both signs
                result = {sign_rs1 ^ sign_rs2, magnitude};
                
            default: 
                result = 16'd0; // Should never hit this in a valid decode
        endcase
    end

endmodule