`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.03.2026 15:32:11
// Design Name: 
// Module Name: gpio_int
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module gpio_int(

    input  wire        clk,
    input  wire        reset,

    // Memory interface
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_write,
    input  wire        gpio_sel,

    output reg  [31:0] read_data,

    // External GPIO pins
    input  wire [7:0]  gpio_in,
    output wire [7:0]  gpio_out,
    output wire [7:0]  gpio_oe,

    // Interrupt output to CPU
    output wire        intr
);

//////////////////////////////////////////////////////
// Internal Registers
//////////////////////////////////////////////////////

reg [7:0] data_reg;       // output data
reg [7:0] dir_reg;        // direction (1=output, 0=input)
reg [7:0] int_en_reg;     // interrupt enable per pin (1=enabled, 0=masked)
reg [7:0] int_status_reg; // interrupt status per pin (1=pending, 0=none)

//////////////////////////////////////////////////////
// Input Synchronization
// Since the data might come at any time we need to synchronise it with the clock
// Two flip flops are kept so that data is never stuck at meta state
//////////////////////////////////////////////////////

reg [7:0] gpio_sync1;
reg [7:0] gpio_sync2;

always @(posedge clk)
begin
    gpio_sync1 <= gpio_in;
    gpio_sync2 <= gpio_sync1;
end

wire [7:0] gpio_input;

assign gpio_input = gpio_sync2;

//////////////////////////////////////////////////////
// Edge Detection
// We keep a copy of gpio_sync2 from the previous clock cycle
// By comparing current and previous we can detect any change (both edges)
//////////////////////////////////////////////////////

reg [7:0] gpio_sync_prev;

// Every clock, store the current synchronized value as "previous"
always @(posedge clk)
begin
    gpio_sync_prev <= gpio_sync2;
end

// A bit is 1 for exactly ONE clock cycle when that pin changes in either direction
// rising  edge: pin was 0, now is 1  ?  ~prev &  curr
// falling edge: pin was 1, now is 0  ?   prev & ~curr
// OR of both = any change on that pin
wire [7:0] any_edge;

assign any_edge = (gpio_sync2 & ~gpio_sync_prev) ;  // 0 -> 1
                // | (~gpio_sync2 & gpio_sync_prev);   // 1 -> 0

//////////////////////////////////////////////////////
// Register Select
// We now have 7 registers so we need 3 bits instead of 2
// addr[4:2] gives us 8 possible register slots
//////////////////////////////////////////////////////

wire [2:0] reg_sel;

assign reg_sel = addr[4:2];

//////////////////////////////////////////////////////
// Write Logic
//////////////////////////////////////////////////////

always @(posedge clk )
begin
    if (!reset)
    begin
        data_reg    <= 8'b0;
        dir_reg     <= 8'b0;
        int_en_reg  <= 8'b0; // all interrupts disabled at reset
    end
    else if (mem_write && gpio_sel)
    begin
        case (reg_sel)

            // DATA register
            3'b000: data_reg <= write_data[7:0];

            // DIR register
            3'b001: dir_reg <= write_data[7:0];

            // SET register (write-only)
            3'b010: data_reg <= data_reg | write_data[7:0];

            // CLEAR register (write-only)
            3'b011: data_reg <= data_reg & ~write_data[7:0];

            // INT_EN register
            // CPU writes which pins are allowed to raise interrupts
            3'b100: int_en_reg <= write_data[7:0];

            // INT_STATUS is set by hardware, not written directly by CPU
            // INT_CLEAR (address 3'b110) is handled in the status block below

        endcase
    end
end

//////////////////////////////////////////////////////
// Interrupt Status Register Logic
// This is separate from write logic because two things can happen at once:
//   - Hardware wants to SET a bit  (edge detected on an enabled pin)
//   - CPU wants to CLEAR a bit     (writing 1s to INT_CLEAR address)
// We handle both in the same clock cycle here
//////////////////////////////////////////////////////

always @(posedge clk)
begin
    if (!reset)
    begin
        int_status_reg <= 8'b0;
    end
    else
    begin
        // Step 1: Check if CPU is writing to INT_CLEAR (address 3'b110)
        // CPU writes a 1 to any bit position to clear that pending interrupt
        if (mem_write && gpio_sel && (reg_sel == 3'b110))
        begin
            // Clear bits where CPU wrote a 1, keep the rest
            // Then in the same cycle also OR in any new edges that just arrived
            int_status_reg <= (int_status_reg & ~write_data[7:0])
                            | (any_edge & int_en_reg);
        end
        else
        begin
            // No CPU clear happening, just OR in any new edges
            // any_edge & int_en_reg: only edges on pins that are enabled
            int_status_reg <= int_status_reg | (any_edge & int_en_reg);
        end
    end
end

//////////////////////////////////////////////////////
// Interrupt Output to CPU
// If ANY bit in int_status_reg is 1, we tell the CPU something is pending
// The CPU will then jump to the interrupt service routine
//////////////////////////////////////////////////////

assign intr = |int_status_reg;  // bitwise OR reduction

//////////////////////////////////////////////////////
// GPIO Output Signals
//////////////////////////////////////////////////////

assign gpio_out = data_reg;
assign gpio_oe  = dir_reg;
//assign gpio_oe = 8'hFF;
//////////////////////////////////////////////////////
// Pin State Readback
//////////////////////////////////////////////////////

wire [7:0] pin_state;

assign pin_state = (data_reg & dir_reg) | (gpio_input & ~dir_reg);

//////////////////////////////////////////////////////
// Read Logic
//////////////////////////////////////////////////////

always @(*)
begin
    if (gpio_sel)
    begin
        case (reg_sel)

            // DATA register
            3'b000: read_data = {24'b0, pin_state};

            // DIR register
            3'b001: read_data = {24'b0, dir_reg};

            // SET register returns DATA
            3'b010: read_data = {24'b0, data_reg};

            // CLEAR register returns DATA
            3'b011: read_data = {24'b0, data_reg};

            // INT_EN register
            // CPU can read back which pins have interrupts enabled
            3'b100: read_data = {24'b0, int_en_reg};

            // INT_STATUS register
            // CPU reads this to find out which pin triggered the interrupt
            3'b101: read_data = {24'b0, int_status_reg};

            // INT_CLEAR is write-only, reading returns 0
            3'b110: read_data = 32'b0;

            default: read_data = 32'b0;

        endcase
    end
    else
        read_data = 32'b0;
end
    
    
    
endmodule
