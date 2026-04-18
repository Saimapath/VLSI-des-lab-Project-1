`timescale 1ns / 1ps

module DMA (
    input  wire        clk,
    input  wire        reset,

    // ── Co-Processor Interface ──────────────────────────────
    input  wire        enable,          
    input  wire [31:0] addr_A,          
    input  wire [31:0] addr_B,          
    output wire        dma_busy,        
    output reg         dma_done,        
    output wire        dma_source_safe, // ---> NEW: Early lock release flag

    // ── Memory Interface (256-bit wide) ───────────────────────
    output reg         mem_req,         
    output reg         mem_we,          
    output wire  [29:0] mem_addr,        
    output reg  [255:0] mem_wdata,      
    input  wire [255:0] mem_data,       

    // ── Systolic Array Interface ──────────────────────────────
    output reg  [15:0] A0, A1, A2, A3, B0, B1, B2, B3,
    output reg         sa_start,
    input  wire        sa_done,
    input  wire [15:0] C00, C01, C02, C03, C10, C11, C12, C13,
    input  wire [15:0] C20, C21, C22, C23, C30, C31, C32, C33
);


reg [31:0]mem_addr_full;
assign mem_addr=mem_addr_full[31:2];

    localparam [3:0]
        S_IDLE       = 4'd0,
        S_REQ_A      = 4'd1,
        S_REQ_B      = 4'd2,
        S_WAIT_A     = 4'd3, 
        S_WAIT_B     = 4'd4,
        S_FEED       = 4'd5,
        S_WAIT       = 4'd6,
        S_WRITEBACK  = 4'd7,
        S_DONE       = 4'd8;

    reg [3:0] state;

    assign dma_busy = (state != S_IDLE);
    
    // ---> NEW: It is safe to overwrite Source B once we reach S_FEED
    assign dma_source_safe = (state >= S_FEED); 

    reg [255:0] mat_A, mat_B, mat_C;
    reg [1:0]   feed_cnt;
    reg [31:0]  latch_addr_A, latch_addr_B;

    wire [15:0] a00=mat_A[15:0],   a01=mat_A[31:16],  a02=mat_A[47:32],   a03=mat_A[63:48];
    wire [15:0] a10=mat_A[79:64],  a11=mat_A[95:80],  a12=mat_A[111:96],  a13=mat_A[127:112];
    wire [15:0] a20=mat_A[143:128],a21=mat_A[159:144],a22=mat_A[175:160], a23=mat_A[191:176];
    wire [15:0] a30=mat_A[207:192],a31=mat_A[223:208],a32=mat_A[239:224], a33=mat_A[255:240];

    wire [15:0] b00=mat_B[15:0],   b10=mat_B[31:16],  b20=mat_B[47:32],   b30=mat_B[63:48];
    wire [15:0] b01=mat_B[79:64],  b11=mat_B[95:80],  b21=mat_B[111:96],  b31=mat_B[127:112];
    wire [15:0] b02=mat_B[143:128],b12=mat_B[159:144],b22=mat_B[175:160], b32=mat_B[191:176];
    wire [15:0] b03=mat_B[207:192],b13=mat_B[223:208],b23=mat_B[239:224], b33=mat_B[255:240];

    wire [255:0] c_packed;
    assign c_packed = {
        C33, C32, C31, C30,
        C23, C22, C21, C20,
        C13, C12, C11, C10,
        C03, C02, C01, C00
    };

    always @(posedge clk) begin
        if (!reset) begin
            state <= S_IDLE;
            mat_A <= 0; mat_B <= 0; mat_C <= 0; feed_cnt <= 0;
            latch_addr_A <= 0; latch_addr_B <= 0;
            mem_req <= 0; mem_we <= 0; mem_addr_full <= 0; mem_wdata <= 0; sa_start <= 0;
            A0<=0; A1<=0; A2<=0; A3<=0; B0<=0; B1<=0; B2<=0; B3<=0;
            dma_done <= 0;
        end else begin
            dma_done <= 1'b0; 
            mem_req <= 0; mem_we <= 0; sa_start <= 0;
            A0<=0; A1<=0; A2<=0; A3<=0; B0<=0; B1<=0; B2<=0; B3<=0;

            case (state)
                S_IDLE: begin
                    feed_cnt <= 2'd0;
                    if (enable) begin
                        latch_addr_A <= addr_A;
                        latch_addr_B <= addr_B; 
                        state        <= S_REQ_A;
                    end
                end

                S_REQ_A: begin
                    mem_req  <= 1'b1;
                    mem_addr_full <= latch_addr_A;
                    state    <= S_REQ_B;
                end

                S_REQ_B: begin
                    mem_req  <= 1'b1;
                    mem_addr_full <= latch_addr_B;
                    state    <= S_WAIT_A; 
                end

                S_WAIT_A: begin
                    mat_A    <= mem_data; 
                    state    <= S_WAIT_B;
                end

                S_WAIT_B: begin
                    mat_B    <= mem_data; 
                    state    <= S_FEED;
                end

                S_FEED: begin
                    sa_start <= 1'b1;
                    case (feed_cnt)
                        2'd0: begin A0<=a00; A1<=a10; A2<=a20; A3<=a30; B0<=b00; B1<=b01; B2<=b02; B3<=b03; end
                        2'd1: begin A0<=a01; A1<=a11; A2<=a21; A3<=a31; B0<=b10; B1<=b11; B2<=b12; B3<=b13; end
                        2'd2: begin A0<=a02; A1<=a12; A2<=a22; A3<=a32; B0<=b20; B1<=b21; B2<=b22; B3<=b23; end
                        2'd3: begin A0<=a03; A1<=a13; A2<=a23; A3<=a33; B0<=b30; B1<=b31; B2<=b32; B3<=b33; end
                    endcase

                    feed_cnt <= feed_cnt + 1'b1;
                    if (feed_cnt == 2'd3) state <= S_WAIT;
                end

                S_WAIT: begin
                    sa_start <= 1'b1;
                    if (sa_done) begin
                        mat_C <= c_packed;
                        state <= S_WRITEBACK;
                    end
                end

                S_WRITEBACK: begin
                    mem_req   <= 1'b1;       // <--- ADD THIS LINE!
                    mem_we    <= 1'b1;
                    mem_addr_full  <= latch_addr_A;
                    mem_wdata <= mat_C;
                    state     <= S_DONE;
                end

                S_DONE: begin
                    dma_done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule