`timescale 1ns / 1ps

module SA_Matmul(
    input clk,
    input reset,
    input sa_start,             

    input [15:0] A0, A1, A2, A3,
    input [15:0] B0, B1, B2, B3,
    
    output [15:0] C00, C01, C02, C03,
    output [15:0] C10, C11, C12, C13,
    output [15:0] C20, C21, C22, C23,
    output [15:0] C30, C31, C32, C33,
    
    output valid
);
    // ---> NEW: Clear everything when the DMA is not actively feeding
    wire clear = ~sa_start; 
    
    wire [15:0] A_skew [0:3];
    wire [15:0] B_skew [0:3];

    // ---> Pass 'clear' to all FIFOs
    fifo_delay #(0) A0_d (.clk(clk), .reset(reset), .clear(clear), .din(A0), .dout(A_skew[0]));
    fifo_delay #(1) A1_d (.clk(clk), .reset(reset), .clear(clear), .din(A1), .dout(A_skew[1]));
    fifo_delay #(2) A2_d (.clk(clk), .reset(reset), .clear(clear), .din(A2), .dout(A_skew[2]));
    fifo_delay #(3) A3_d (.clk(clk), .reset(reset), .clear(clear), .din(A3), .dout(A_skew[3]));
    
    fifo_delay #(0) B0_d (.clk(clk), .reset(reset), .clear(clear), .din(B0), .dout(B_skew[0]));
    fifo_delay #(1) B1_d (.clk(clk), .reset(reset), .clear(clear), .din(B1), .dout(B_skew[1]));
    fifo_delay #(2) B2_d (.clk(clk), .reset(reset), .clear(clear), .din(B2), .dout(B_skew[2]));
    fifo_delay #(3) B3_d (.clk(clk), .reset(reset), .clear(clear), .din(B3), .dout(B_skew[3]));
    
    wire [15:0] A_wire [0:3][0:4];
    wire [15:0] B_wire [0:4][0:3];
    
    assign A_wire[0][0] = A_skew[0];
    assign A_wire[1][0] = A_skew[1];
    assign A_wire[2][0] = A_skew[2];
    assign A_wire[3][0] = A_skew[3];
    
    assign B_wire[0][0] = B_skew[0];
    assign B_wire[0][1] = B_skew[1];
    assign B_wire[0][2] = B_skew[2];
    assign B_wire[0][3] = B_skew[3];
    
    // ---> Pass 'clear' to all MACs
    MAC PE00 (.Ain(A_wire[0][0]),.Bin(B_wire[0][0]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[0][1]),.Bout(B_wire[1][0]),.C(C00));
    MAC PE01 (.Ain(A_wire[0][1]),.Bin(B_wire[0][1]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[0][2]),.Bout(B_wire[1][1]),.C(C01));
    MAC PE02 (.Ain(A_wire[0][2]),.Bin(B_wire[0][2]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[0][3]),.Bout(B_wire[1][2]),.C(C02));
    MAC PE03 (.Ain(A_wire[0][3]),.Bin(B_wire[0][3]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[0][4]),.Bout(B_wire[1][3]),.C(C03));
    
    MAC PE10 (.Ain(A_wire[1][0]),.Bin(B_wire[1][0]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[1][1]),.Bout(B_wire[2][0]),.C(C10));
    MAC PE11 (.Ain(A_wire[1][1]),.Bin(B_wire[1][1]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[1][2]),.Bout(B_wire[2][1]),.C(C11));
    MAC PE12 (.Ain(A_wire[1][2]),.Bin(B_wire[1][2]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[1][3]),.Bout(B_wire[2][2]),.C(C12));
    MAC PE13 (.Ain(A_wire[1][3]),.Bin(B_wire[1][3]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[1][4]),.Bout(B_wire[2][3]),.C(C13));
    
    MAC PE20 (.Ain(A_wire[2][0]),.Bin(B_wire[2][0]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[2][1]),.Bout(B_wire[3][0]),.C(C20));
    MAC PE21 (.Ain(A_wire[2][1]),.Bin(B_wire[2][1]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[2][2]),.Bout(B_wire[3][1]),.C(C21));
    MAC PE22 (.Ain(A_wire[2][2]),.Bin(B_wire[2][2]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[2][3]),.Bout(B_wire[3][2]),.C(C22));
    MAC PE23 (.Ain(A_wire[2][3]),.Bin(B_wire[2][3]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[2][4]),.Bout(B_wire[3][3]),.C(C23));
    
    MAC PE30 (.Ain(A_wire[3][0]),.Bin(B_wire[3][0]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[3][1]),.Bout(B_wire[4][0]),.C(C30));
    MAC PE31 (.Ain(A_wire[3][1]),.Bin(B_wire[3][1]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[3][2]),.Bout(B_wire[4][1]),.C(C31));
    MAC PE32 (.Ain(A_wire[3][2]),.Bin(B_wire[3][2]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[3][3]),.Bout(B_wire[4][2]),.C(C32));
    MAC PE33 (.Ain(A_wire[3][3]),.Bin(B_wire[3][3]),.clk(clk),.reset(reset),.clear(clear),.Aout(A_wire[3][4]),.Bout(B_wire[4][3]),.C(C33));

    reg [4:0] cycle_count;
    reg valid_out;

    always @(posedge clk) begin
        if (!reset) begin
            cycle_count <= 0;
            valid_out   <= 0;
        end
        else begin
            if (!sa_start) begin
                cycle_count <= 0;
                valid_out   <= 0;
            end
            else begin
                if (cycle_count < 14) begin
                    cycle_count <= cycle_count + 1;
                    valid_out   <= 0;
                end
                else begin
                    valid_out <= 1;
                end
            end
        end
    end
    assign valid = valid_out;
    
endmodule

module fifo_delay #(parameter DEPTH = 0)(
    input clk,
    input reset,
    input clear,     // ---> NEW
    input [15:0] din,
    output [15:0] dout
);
    reg [15:0] shift[0:DEPTH];
    integer i;
    always @(posedge clk) begin
        if(!reset) begin
            for(i=0;i<=DEPTH;i=i+1) begin
                shift[i] <= 16'h0000;
            end
        end else if (clear) begin // ---> NEW: Clear shift registers
            for(i=0;i<=DEPTH;i=i+1) begin
                shift[i] <= 16'h0000;
            end
        end else begin
            for (i = DEPTH; i > 0; i = i - 1) begin
                 shift[i] <= shift[i-1];
            end
            shift[0] <= din;
        end
    end

    assign dout = shift[DEPTH];
endmodule