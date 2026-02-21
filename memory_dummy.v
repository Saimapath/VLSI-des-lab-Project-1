module memory_dummy #(
    parameter ADDR_WIDTH = 10,       // 1024 words
    parameter DATA_WIDTH = 32        // 4 bytes per word
)(
    input                     clk,   // Clock
    input                     en,    // Enable (Chip Select)
    input  [(DATA_WIDTH/8)-1:0] we,  // Byte-level Write Enable (e.g., 4'b1111)
    input  [ADDR_WIDTH-1:0]   addr,  // Address
    input  [DATA_WIDTH-1:0]   din,   // Data Input
    output reg [DATA_WIDTH-1:0] dout // Data Output
);

    // Internal memory array
    reg [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];

    // Initialize memory with a file (optional, great for testing programs)
    initial $readmemh("program_code.hex", mem);

    integer i;
    always @(negedge clk) begin
        if (en) begin
            // Byte-enable logic
            for (i = 0; i < (DATA_WIDTH/8); i = i + 1) begin
                if (we[i]) begin
                    mem[addr][(i*8) +: 8] <= din[(i*8) +: 8];
                end
            end
            
            // Synchronous Read: Output updates one cycle after addr is set
            dout <= mem[addr];
        end
    end

endmodule