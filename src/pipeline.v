// =====================================================================
// HIGH-SPEED PIPELINE REGISTER (Forces Hardware Control Pins)
// =====================================================================
module pipe_reg #(parameter WIDTH = 8) (
    input wire clk, 
    input wire reset, 
    input wire en, 
    input wire clear,
    input wire [WIDTH-1:0] d,
    output reg [WIDTH-1:0] q
);
    // Xilinx Pragma: Forces Vivado to bypass the combinational D-LUTs 
    // and wire directly into the silicon's dedicated Set/Reset and Enable pins!
    (* direct_reset = "true" *)  wire hw_clear = (!reset || clear);
    (* direct_enable = "true" *) wire hw_en = en;

    always @(posedge clk) begin
        if (hw_clear) 
            q <= 0;
        else if (hw_en) 
            q <= d;
    end
endmodule