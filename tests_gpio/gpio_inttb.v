`timescale 1ns / 1ps

module gpio_tb();

reg clk;
reg reset;

reg [31:0] addr;
reg [31:0] write_data;
reg mem_write;
reg gpio_sel;

wire [31:0] read_data;

reg  [7:0] gpio_in;
wire [7:0] gpio_out;
wire [7:0] gpio_oe;

// New: interrupt wire to observe
wire intr;

//////////////////////////////////////////////////////
// Instantiate GPIO
//////////////////////////////////////////////////////

gpio_peripheral DUT
(
    .clk(clk),
    .reset(reset),

    .addr(addr),
    .write_data(write_data),
    .mem_write(mem_write),
    .gpio_sel(gpio_sel),

    .read_data(read_data),

    .gpio_in(gpio_in),
    .gpio_out(gpio_out),
    .gpio_oe(gpio_oe),

    // New: connect interrupt port
    .intr(intr)
);

//////////////////////////////////////////////////////
// Clock generation
//////////////////////////////////////////////////////

initial
begin
    clk = 0;
    forever #5 clk = ~clk;
end

//////////////////////////////////////////////////////
// Test sequence
//////////////////////////////////////////////////////

initial
begin

    $display("Starting GPIO Testbench");

    reset = 1;
    mem_write = 0;
    gpio_sel = 0;
    addr = 0;
    write_data = 0;
    gpio_in = 0;

    #50
    reset = 0;

//////////////////////////////////////////////////////
// Test 1: Configure GPIO as outputs
//////////////////////////////////////////////////////

    $display("Test 1: Configure direction register");

    gpio_sel = 1;
    addr = 32'h00000004; // DIR register offset 4 -> addr[4:2] = 001
    write_data = 32'h000000FF;
    mem_write = 1;

    #80
    mem_write = 0;

//////////////////////////////////////////////////////
// Test 2: Write to DATA register
//////////////////////////////////////////////////////

    $display("Test 2: Write to DATA register");

    addr = 32'h00000000; // DATA register offset 0 -> addr[4:2] = 000
    write_data = 32'h000000AA;
    mem_write = 1;

    #60
    mem_write = 0;

//////////////////////////////////////////////////////
// Test 3: Read DATA register
//////////////////////////////////////////////////////

    $display("Test 3: Read DATA register");

    addr = 32'h00000000;

    #60
    $display("Read Data = %h (expect aa)", read_data);

//////////////////////////////////////////////////////
// Test 4: SET register
//////////////////////////////////////////////////////

    $display("Test 4: Set bits");

    addr = 32'h00000008; // SET register offset 8 -> addr[4:2] = 010
    write_data = 32'h00000005;
    mem_write = 1;

    #40
    mem_write = 0;

//////////////////////////////////////////////////////
// Test 5: CLEAR register
//////////////////////////////////////////////////////

    $display("Test 5: Clear bits");

    addr = 32'h0000000C; // CLEAR register offset 12 -> addr[4:2] = 011
    write_data = 32'h00000002;
    mem_write = 1;

    #10
    mem_write = 0;

//////////////////////////////////////////////////////
// Test 6: Input mode test
//////////////////////////////////////////////////////

    $display("Test 6: Switch some pins to input");

    addr = 32'h00000004; // DIR register
    write_data = 32'h000000F0; // upper 4 pins = output, lower 4 pins = input
    mem_write = 1;

    #40
    mem_write = 0;

    gpio_in = 8'b10100000;

    addr = 32'h00000000;

    #40
    $display("Read pin state = %h", read_data);

//////////////////////////////////////////////////////
// Test 7: Enable interrupts on lower 4 pins (inputs)
// INT_EN register is at offset 16 -> addr[4:2] = 100
//////////////////////////////////////////////////////

    $display("Test 7: Enable interrupts on lower 4 pins");

    addr = 32'h00000010; // INT_EN register
    write_data = 32'h0000000F; // enable pins 0,1,2,3
    mem_write = 1;

    #10
    mem_write = 0;

    // Read back INT_EN to confirm it was written correctly
    addr = 32'h00000010;
    #10
    $display("INT_EN = %h (expect 0f)", read_data);

//////////////////////////////////////////////////////
// Test 8: Trigger a rising edge on pin 0 (input pin)
// pin 0 goes 0 -> 1
// This should set int_status_reg[0] and raise intr
//////////////////////////////////////////////////////

    $display("Test 8: Rising edge on pin 0");

    gpio_in[0] = 1; // 0 -> 1 on pin 0

    // Wait 3 cycles:
    // cycle 1: gpio_sync1 captures it
    // cycle 2: gpio_sync2 captures it (synchronized)
    // cycle 3: any_edge is computed, int_status_reg is set
    #30

    $display("intr = %b (expect 1)", intr);

    // Read INT_STATUS to see which pin fired
    // INT_STATUS register is at offset 20 -> addr[4:2] = 101
    addr = 32'h00000014; // INT_STATUS register
    #10
    $display("INT_STATUS = %h (expect 01, pin 0 fired)", read_data);

//////////////////////////////////////////////////////
// Test 9: Trigger a falling edge on pin 1 (input pin)
// pin 1 goes 0 -> 1 -> 0, we check the falling edge
//////////////////////////////////////////////////////

    $display("Test 9: Falling edge on pin 1");

    gpio_in[1] = 1; // first bring it high
    #30             // wait for sync + edge to settle
    gpio_in[1] = 0; // now bring it low -> falling edge
    #30

    $display("intr = %b (expect 1)", intr);

    addr = 32'h00000014; // INT_STATUS
    #10
    $display("INT_STATUS = %h (expect 03, pins 0 and 1 fired)", read_data);

//////////////////////////////////////////////////////
// Test 10: CPU acknowledges interrupt on pin 0
// CPU writes 1 to INT_CLEAR for pin 0
// INT_CLEAR register is at offset 24 -> addr[4:2] = 110
//////////////////////////////////////////////////////

    $display("Test 10: Clear interrupt on pin 0");

    addr = 32'h00000018; // INT_CLEAR register
    write_data = 32'h00000001; // clear only pin 0
    mem_write = 1;

    #10
    mem_write = 0;

    // Check INT_STATUS: pin 0 should be cleared, pin 1 should still be pending
    addr = 32'h00000014; // INT_STATUS
    #10
    $display("INT_STATUS = %h (expect 02, only pin 1 still pending)", read_data);
    $display("intr = %b (expect 1, pin 1 still pending)", intr);

//////////////////////////////////////////////////////
// Test 11: CPU acknowledges interrupt on pin 1
// Now all interrupts are cleared, intr should go low
//////////////////////////////////////////////////////

    $display("Test 11: Clear interrupt on pin 1");

    addr = 32'h00000018; // INT_CLEAR register
    write_data = 32'h00000002; // clear only pin 1
    mem_write = 1;

    #10
    mem_write = 0;

    addr = 32'h00000014; // INT_STATUS
    #10
    $display("INT_STATUS = %h (expect 00, all cleared)", read_data);
    $display("intr = %b (expect 0, all interrupts cleared)", intr);

//////////////////////////////////////////////////////
// Test 12: Edge on a disabled pin should NOT interrupt
// Pin 2 is in input direction but we will disable its interrupt
//////////////////////////////////////////////////////

    $display("Test 12: Edge on pin 2 with interrupt disabled");

    // Disable pin 2 interrupt, keep pins 0 and 1 enabled only
    addr = 32'h00000010; // INT_EN
    write_data = 32'h00000003; // only pins 0 and 1 enabled, pin 2 now masked
    mem_write = 1;

    #10
    mem_write = 0;

    gpio_in[2] = 1; // edge on pin 2
    #30

    $display("intr = %b (expect 0, pin 2 is masked)", intr);

    addr = 32'h00000014; // INT_STATUS
    #10
    $display("INT_STATUS = %h (expect 00, pin 2 edge was ignored)", read_data);

//////////////////////////////////////////////////////

    #50
    $display("Simulation Finished");
    $finish;

end

endmodule
```

---

## What to Expect in the Output
```
Starting GPIO Testbench
Test 1: Configure direction register
Test 2: Write to DATA register
Test 3: Read DATA register
Read Data = aa (expect aa)
Test 4: Set bits
Test 5: Clear bits
Test 6: Switch some pins to input
Read pin state = a0
Test 7: Enable interrupts on lower 4 pins
INT_EN = 0000000f (expect 0f)
Test 8: Rising edge on pin 0
intr = 1 (expect 1)
INT_STATUS = 00000001 (expect 01, pin 0 fired)
Test 9: Falling edge on pin 1
intr = 1 (expect 1)
INT_STATUS = 00000003 (expect 03, pins 0 and 1 fired)
Test 10: Clear interrupt on pin 0
INT_STATUS = 00000002 (expect 02, only pin 1 still pending)
intr = 1 (expect 1, pin 1 still pending)
Test 11: Clear interrupt on pin 1
INT_STATUS = 00000000 (expect 00, all cleared)
intr = 0 (expect 0, all interrupts cleared)
Test 12: Edge on pin 2 with interrupt disabled
intr = 0 (expect 0, pin 2 is masked)
INT_STATUS = 00000000 (expect 00, pin 2 edge was ignored)
Simulation Finished