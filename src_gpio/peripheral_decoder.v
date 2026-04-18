module peripheral_decoder(
    // inputs from pipeline
    input  [29:0] ALUResultM_out,
    input  [3:0]  MemWriteM,
    input         MemEnM,

    // read data from all three peripherals
    input  [31:0] bram_read_data,
    input  [31:0] gpio_read_data,
    input  [31:0] spi_read_data,

    // select signals going TO peripherals
    output        gpio_sel,
    output        spi_sel,

    // write strobes going TO peripherals
    output        mem_write_gpio,
    output        mem_write_spi,

    // gated write enable going TO data BRAM
    output [3:0]  bram_we,

    // read data MUX output going back TO pipeline
    output [31:0] ReadDataM,

    // full address going TO gpio and spi
    output [31:0] data_addr_full,

    // word address going TO data BRAM
    output [12:0] bram_addr
);

    // reconstruct full 32-bit byte address
    wire [31:0] data_addr;
    assign data_addr = {ALUResultM_out, 2'b00};

    //////////////////////////////////////////////////////
    // Address Map
    // 0x00000000 - 0x00003FFF  →  BRAM
    // 0x40000000 - 0x4000001F  →  GPIO
    // 0x50000000 - 0x5000001F  →  SPI
    //////////////////////////////////////////////////////

    assign gpio_sel = (data_addr[31:16] == 16'h4000);
    assign spi_sel  = (data_addr[31:16] == 16'h5000);

    // write strobes — only assert when enabled, writing, and correct peripheral
    assign mem_write_gpio = MemEnM && (MemWriteM != 4'b0000) && gpio_sel;
    assign mem_write_spi  = MemEnM && (MemWriteM != 4'b0000) && spi_sel;

    // block BRAM writes when any peripheral is selected
    assign bram_we = (gpio_sel || spi_sel) ? 4'b0000 : MemWriteM;

    // read data MUX — pick who responds based on address
    assign ReadDataM = gpio_sel ? gpio_read_data :
                       spi_sel  ? spi_read_data  :
                       bram_read_data;

    assign data_addr_full = data_addr;
    assign bram_addr      = ALUResultM_out[12:0];

endmodule