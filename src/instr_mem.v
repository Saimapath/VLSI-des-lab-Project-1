module bram_imem (
    input clk,
    input [31:0] addr,
    input en,
    output reg [31:0] dout
);
    // --- RISC-V Opcode & Funct3 Parameters for Readability ---
    localparam [6:0] OP_R      = 7'b0110011;
    localparam [6:0] OP_I_ALU  = 7'b0010011;
    localparam [6:0] OP_LW     = 7'b0000011;
    localparam [6:0] OP_SW     = 7'b0100011;
    localparam [2:0] F3_ADD    = 3'b000;
    localparam [2:0] F3_LW     = 3'b010;
    localparam [2:0] F3_SW     = 3'b010;

    // Helper function to assemble I-type instructions in-line
    function [31:0] i_type(input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
        i_type = {imm, rs1, f3, rd, op};
    endfunction

    // Helper function to assemble R-type
    function [31:0] r_type(input [6:0] f7, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
        r_type = {f7, rs2, rs1, f3, rd, op};
    endfunction

    reg [31:0] ram [0:1023];

    // initial begin
    //     // Example Program:
    //     // 1. addi x1, x0, 10  (Load 10 into x1)
    //     ram[0] = i_type(12'd10, 5'd0, F3_ADD, 5'd1, OP_I_ALU);
        
    //     // 2. addi x2, x0, 20  (Load 20 into x2)
    //     ram[1] = i_type(12'd20, 5'd0, F3_ADD, 5'd2, OP_I_ALU);
        
    //     // 3. add  x3, x1, x2  (x3 = 10 + 20 = 30)
    //     ram[2] = r_type(7'b0000000, 5'd2, 5'd1, F3_ADD, 5'd3, OP_R);
        
    //     // 4. sw   x3, 100(x0) (Store 30 at address 100)
    //     // S-type is {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode}
    //     ram[3] = {7'd3, 5'd3, 5'd0, F3_SW, 5'd4, OP_SW}; 

    //     // Fill remaining with NOPs (addi x0, x0, 0)
    //     for (integer i = 4; i < 1024; i = i + 1) ram[i] = 32'h00000013;
    // end

    always @(posedge clk) begin
        if (en) dout <= ram[addr[31:2]]; // Word aligned access
    end
       
endmodule