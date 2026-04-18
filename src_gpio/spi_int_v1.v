`timescale 1ns / 1ps

module spi_module(

    input  wire        clk,
    input  wire        reset,

    // Memory interface
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    input  wire        mem_write,
    input  wire        spi_sel,

    output reg  [31:0] read_data,

    // SPI pins
    input  wire        miso,
    output reg         mosi,
    output reg         sclk,
    output reg         cs_n,

    // Interrupt output
    // goes HIGH when transfer is done AND interrupts are enabled
    output wire        intr
);

//////////////////////////////////////////////////////
// Memory Map
//   Base + 0x00  TXDATA   [7:0]   write byte to send
//   Base + 0x04  RXDATA   [7:0]   read received byte (reading clears spif)
//   Base + 0x08  STATUS   [2]=spif  [1]=rx_valid  [0]=busy
//   Base + 0x0C  CONTROL  [1]=spie (interrupt enable)  [0]=start (self-clearing)
//   Base + 0x10  CLKDIV   [7:0]   SCLK = clk / (2 * clkdiv)
//////////////////////////////////////////////////////

wire [2:0] reg_sel = addr[4:2];

localparam REG_TXDATA  = 3'd0;
localparam REG_RXDATA  = 3'd1;
localparam REG_STATUS  = 3'd2;
localparam REG_CONTROL = 3'd3;
localparam REG_CLKDIV  = 3'd4;

localparam IDLE     = 2'd0;
localparam TRANSFER = 2'd1;
localparam DONE     = 2'd2;

//////////////////////////////////////////////////////
// Registers
//////////////////////////////////////////////////////

reg [7:0] tx_reg;
reg [7:0] rx_reg;
reg [7:0] clk_div;

reg       busy;
reg       rx_valid;
reg       start;

// Interrupt registers
reg       spie;   // interrupt enable  — CPU writes 1 to arm
reg       spif;   // interrupt flag    — set when done, cleared when CPU reads RXDATA

//////////////////////////////////////////////////////
// Write Logic
//////////////////////////////////////////////////////

always @(posedge clk)
begin
    if (!reset)
    begin
        tx_reg  <= 8'h00;
        clk_div <= 8'd10;
        start   <= 1'b0;
        spie    <= 1'b0;    // interrupts disabled at reset
    end
    else
    begin
        start <= 1'b0;      // auto-clear every cycle

        if (mem_write && spi_sel)
        begin
            case (reg_sel)
                REG_TXDATA:  tx_reg <= write_data[7:0];
                REG_CLKDIV:  clk_div <= write_data[7:0];
                REG_CONTROL:
                begin
                    start <= write_data[0];   // bit 0 = start
                    spie  <= write_data[1];   // bit 1 = interrupt enable
                end
                default: ;
            endcase
        end
    end
end

//////////////////////////////////////////////////////
// SPIF Flag Logic
// SET   — when FSM enters DONE state
// CLEAR — when CPU reads RXDATA
//////////////////////////////////////////////////////

always @(posedge clk)
begin
    if (!reset)
        spif <= 1'b0;
    else if (state == DONE)
        spif <= 1'b1;                                        // transfer finished
    else if (spi_sel && !mem_write && reg_sel == REG_RXDATA)
        spif <= 1'b0;                                        // CPU read RXDATA
end

// interrupt fires only when enabled AND pending
assign intr = spie & spif;

//////////////////////////////////////////////////////
// Read Logic
//////////////////////////////////////////////////////

always @(*)
begin
    read_data = 32'b0;
    if (spi_sel)
    begin
        case (reg_sel)
            REG_RXDATA: read_data = {24'b0, rx_reg};
            REG_STATUS: read_data = {29'b0, spif, rx_valid, busy};
            default:    read_data = 32'b0;
        endcase
    end
end

//////////////////////////////////////////////////////
// SPI FSM
//////////////////////////////////////////////////////

reg [1:0]  state;
reg [7:0]  tx_shreg;
reg [7:0]  rx_shreg;
reg [3:0]  bit_cnt;
reg [7:0]  clk_cnt;

always @(posedge clk)
begin
    if (!reset)
    begin
        state    <= IDLE;
        sclk     <= 1'b1;
        cs_n     <= 1'b1;
        mosi     <= 1'b0;
        busy     <= 1'b0;
        rx_valid <= 1'b0;
        bit_cnt  <= 4'd0;
        clk_cnt  <= 8'd0;
        tx_shreg <= 8'h00;
        rx_shreg <= 8'h00;
        rx_reg   <= 8'h00;
    end
    else
    begin
        case (state)

        ////////////////////////////////////////////////
        // IDLE: wait for start pulse
        ////////////////////////////////////////////////
        IDLE:
        begin
            sclk <= 1'b1;
            cs_n <= 1'b1;
            busy <= 1'b0;

            if (start)
            begin
                tx_shreg <= tx_reg;
                mosi     <= tx_reg[7];  // pre-drive MSB before first edge
                rx_shreg <= 8'h00;
                bit_cnt  <= 4'd8;       // counts 8 falling edges
                clk_cnt  <= 8'd0;
                cs_n     <= 1'b0;
                busy     <= 1'b1;
                rx_valid <= 1'b0;
                state    <= TRANSFER;
            end
        end

        ////////////////////////////////////////////////
        // TRANSFER: generate SCLK, shift bits in/out
        // YOUR corrected logic kept exactly as-is:
        //   falling edge (sclk was 1) → shift MOSI out, decrement counter
        //   rising  edge (sclk was 0) → sample MISO in, check if done
        ////////////////////////////////////////////////
        TRANSFER:
        begin
            clk_cnt <= clk_cnt + 8'd1;

            if (clk_cnt == clk_div - 1)
            begin
                clk_cnt <= 8'd0;
                sclk    <= ~sclk;

                // Falling edge (sclk was 1, going to 0):
                // shift out next MOSI bit, decrement counter
                if (sclk == 1'b1)
                begin
                    tx_shreg <= {tx_shreg[6:0], 1'b0};
                    bit_cnt  <= bit_cnt - 4'd1;
                    if (bit_cnt != 4'd1)    // stop driving mosi after last bit
                        mosi <= tx_shreg[6];
                end

                // Rising edge (sclk was 0, going to 1):
                // sample MISO, check if all 8 bits done
                else
                begin
                    rx_shreg <= {rx_shreg[6:0], miso};
                    if (bit_cnt == 4'd0)    // all bits shifted out, transfer complete
                        state <= DONE;
                end
            end
        end

        ////////////////////////////////////////////////
        // DONE: latch RX result, release bus
        // spif gets set by its own always block watching state == DONE
        ////////////////////////////////////////////////
        DONE:
        begin
            rx_reg   <= rx_shreg;   // latch completed byte
            rx_valid <= 1'b1;       // data ready for CPU
            cs_n     <= 1'b1;
            sclk     <= 1'b0;
            busy     <= 1'b0;
            state    <= IDLE;
        end

        default: state <= IDLE;

        endcase
    end
end

endmodule