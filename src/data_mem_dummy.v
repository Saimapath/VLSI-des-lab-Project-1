module bram_dmem (
    input clk,
    input en,                  // Chip Enable
    input [3:0] we,            // Byte-Write Enable
    input [29:0] addr,
    input [31:0] din,
    output reg [31:0] dout
);
    reg [31:0] ram [0:1023];

    always @(posedge clk) begin
        if (en) begin
            if (we[0]) ram[addr[29:0]][7:0]   <= din[7:0];
            if (we[1]) ram[addr[29:0]][15:8]  <= din[15:8];
            if (we[2]) ram[addr[29:0]][23:16] <= din[23:16];
            if (we[3]) ram[addr[29:0]][31:24] <= din[31:24];
            
            // Synchronous read (1-cycle latency)
            dout <= ram[addr[29:0]];
        end
    end
endmodule