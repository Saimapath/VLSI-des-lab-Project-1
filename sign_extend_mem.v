module extend_mem (
    input  [31:0] memdata,
    input  [2:0]  loadtype,
    output reg [31:0] memext
);
    always @(*) begin
        case (loadtype)
            3'b000: memext = {{24{memdata[7]}}, memdata[7:0]};
            3'b001: memext = {{16{memdata[15]}}, memdata[15:0]};
            3'b010: memext = memdata; // For LW, we just take the whole word as is
            3'b100: memext = {24'd0, memdata[7:0]};
            3'b101: memext = {16'd0, memdata[15:0]};
            default: memext = memdata;
        endcase
    end
endmodule