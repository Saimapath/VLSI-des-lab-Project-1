module bram_imem (
    input clk,
    input [29:0] addr,
    input en,
    output reg [31:0] dout
);
    // Force Vivado to use Block RAM primitives
    (* ram_style = "block" *) reg [31:0] ram [0:1023];

    // =========================================================
    // INITIALIZATION (Loads from an external file)
    // =========================================================
    initial begin
        // Vivado will look for this file in your project directory
        // and load the hex values into the RAM array.
//        $readmemh("instr_mem.mem", ram);
                // $readmemh("gpio_checkpointing.mem", ram);

    end

    // Synchronous Read
    always @(posedge clk) begin
        if (en) dout <= ram[addr[9:0]]; // Sliced to 10 bits for 1024 depth
    end
endmodule