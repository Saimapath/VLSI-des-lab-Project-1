// =============================================================================
// DMA Controller for 4x4 Systolic Array Matrix Multiplier
// =============================================================================
// Description:
//   1. CPU asserts `start` with base addresses for matrix A and B
//   2. DMA fetches all 16 elements of A (256b burst), then all 16 of B
//   3. DMA streams skewed (zero-padded) rows/cols to systolic array
//      - Each cycle: 4 row entries (A) and 4 col entries (B), each 16-bit
//      - Skewing: row i of A delayed by i cycles, col j of B delayed by j cycles
//   4. After 2N-1+N = 11 cycles of SA operation, DMA asserts `done`
//
// Interface assumptions:
//   - Memory bus: 256-bit wide (fetches entire 4x4 matrix in one transaction)
//   - Systolic array: expects sa_en, sa_row_data[63:0], sa_col_data[63:0]
//     sa_row_data = {row3[15:0], row2[15:0], row1[15:0], row0[15:0]}
//     sa_col_data = {col3[15:0], col2[15:0], col1[15:0], col0[15:0]}
// =============================================================================

module dma_controller #(
    parameter DATA_WIDTH  = 16,   // bits per matrix element
    parameter MAT_SIZE    = 4,    // NxN matrix
    parameter ADDR_WIDTH  = 32,   // memory address width
    parameter MEM_WIDTH   = 256   // memory bus width (full matrix at once)
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // --- CPU Interface ---
    input  wire                  cpu_start,       // pulse to begin
    input  wire [ADDR_WIDTH-1:0] cpu_addr_a,      // base address of matrix A
    input  wire [ADDR_WIDTH-1:0] cpu_addr_b,      // base address of matrix B
    output reg                   dma_done,        // pulse when SA is done

    // --- Memory Interface (burst: 256-bit read in one transaction) ---
    output reg                   mem_req,         // request a memory read
    output reg  [ADDR_WIDTH-1:0] mem_addr,        // address to read
    input  wire                  mem_ack,         // memory data is valid
    input  wire [MEM_WIDTH-1:0]  mem_data,        // 256-bit data back

    // --- Systolic Array Interface ---
    output reg                   sa_en,           // enable / data-valid to SA
    output reg  [63:0]           sa_row_data,     // 4 x 16-bit row entries (A)
    output reg  [63:0]           sa_col_data      // 4 x 16-bit col entries (B)
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam N          = MAT_SIZE;             // 4
    localparam TOTAL_ELEM = N * N;                // 16
    // Systolic array needs 2*N-1 + N - 1 = 2N + N - 2 = 10 cycles (0..10)
    // Last diagonal starts at cycle 2*(N-1) = 6, last PE finishes N cycles later
    // Total feed cycles = 2*N - 1 = 7, drain = N-1 extra = 3 → 10 total SA cycles
    localparam SA_CYCLES  = 2*N - 1 + N - 1;     // = 10  (cycles 0..9 inclusive)

    // FSM states
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_FETCH_A   = 3'd1,
        S_FETCH_B   = 3'd2,
        S_STREAM    = 3'd3,
        S_DONE      = 3'd4;

    // -------------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------------
    reg [2:0]  state, next_state;

    // Matrix storage: mat_a[i][j] = A[i][j], mat_b[i][j] = B[i][j]
    // Stored row-major: mat_a[row*N + col]
    reg [DATA_WIDTH-1:0] mat_a [0:TOTAL_ELEM-1];
    reg [DATA_WIDTH-1:0] mat_b [0:TOTAL_ELEM-1];

    reg [ADDR_WIDTH-1:0] addr_a_r, addr_b_r;

    // Stream counter: which SA cycle are we on (0 to SA_CYCLES)
    reg [$clog2(SA_CYCLES+2)-1:0] sa_cycle;

    integer i; // for unpack loop

    // -------------------------------------------------------------------------
    // FSM — sequential
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------------------
    // FSM — next-state logic
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:    if (cpu_start)          next_state = S_FETCH_A;
            S_FETCH_A: if (mem_ack)            next_state = S_FETCH_B;
            S_FETCH_B: if (mem_ack)            next_state = S_STREAM;
            S_STREAM:  if (sa_cycle == SA_CYCLES) next_state = S_DONE;
            S_DONE:                            next_state = S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Address latch
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_a_r <= 0;
            addr_b_r <= 0;
        end else if (cpu_start) begin
            addr_a_r <= cpu_addr_a;
            addr_b_r <= cpu_addr_b;
        end
    end

    // -------------------------------------------------------------------------
    // Memory request
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_req  <= 1'b0;
            mem_addr <= 0;
        end else begin
            mem_req  <= 1'b0;  // default de-assert
            case (state)
                S_IDLE: begin
                    if (cpu_start) begin
                        mem_req  <= 1'b1;
                        mem_addr <= cpu_addr_a;
                    end
                end
                S_FETCH_A: begin
                    if (!mem_ack) begin
                        mem_req  <= 1'b1;
                        mem_addr <= addr_a_r;
                    end else begin
                        // immediately request B
                        mem_req  <= 1'b1;
                        mem_addr <= addr_b_r;
                    end
                end
                S_FETCH_B: begin
                    if (!mem_ack) begin
                        mem_req  <= 1'b1;
                        mem_addr <= addr_b_r;
                    end
                end
                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Matrix unpack from 256-bit burst
    // mem_data layout: element[0] in bits [15:0], element[15] in bits [255:240]
    // Row-major: index = row*4 + col
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TOTAL_ELEM; i = i + 1) begin
                mat_a[i] <= 0;
                mat_b[i] <= 0;
            end
        end else begin
            if (state == S_FETCH_A && mem_ack) begin
                for (i = 0; i < TOTAL_ELEM; i = i + 1)
                    mat_a[i] <= mem_data[i*DATA_WIDTH +: DATA_WIDTH];
            end
            if (state == S_FETCH_B && mem_ack) begin
                for (i = 0; i < TOTAL_ELEM; i = i + 1)
                    mat_b[i] <= mem_data[i*DATA_WIDTH +: DATA_WIDTH];
            end
        end
    end

    // -------------------------------------------------------------------------
    // SA cycle counter
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sa_cycle <= 0;
        else if (state == S_STREAM)
            sa_cycle <= sa_cycle + 1;
        else
            sa_cycle <= 0;
    end

    // -------------------------------------------------------------------------
    // Systolic array data steering
    //
    // Skewing rule (same as the systolic array diagram):
    //   A: row i of matrix A enters at SA cycle i, i+1, i+2, i+3
    //      i.e. A[i][k] is valid when sa_cycle == i + k
    //      → for a given sa_cycle t, row i gets A[i][t-i] if 0 <= t-i < N
    //
    //   B: col j of matrix B enters at SA cycle j, j+1, j+2, j+3
    //      i.e. B[k][j] is valid when sa_cycle == j + k
    //      → for a given sa_cycle t, col j gets B[t-j][j] if 0 <= t-j < N
    //
    // sa_row_data[row] = (t-row in [0,N-1]) ? A[row][t-row] : 0
    // sa_col_data[col] = (t-col in [0,N-1]) ? B[t-col][col] : 0
    // -------------------------------------------------------------------------

    // Helper function: get A[row][k], or 0 if k out of range
    // Verilog doesn't allow functions returning 'wire' arrays easily,
    // so we use combinational always with internal variables.

    reg [DATA_WIDTH-1:0] row_val [0:N-1]; // what goes to SA row port each cycle
    reg [DATA_WIDTH-1:0] col_val [0:N-1]; // what goes to SA col port each cycle

    integer row, col, k_r, k_c;

    always @(*) begin
        for (row = 0; row < N; row = row + 1) begin
            k_r = $signed(sa_cycle) - row;
            if (k_r >= 0 && k_r < N)
                row_val[row] = mat_a[row*N + k_r];
            else
                row_val[row] = {DATA_WIDTH{1'b0}};
        end

        for (col = 0; col < N; col = col + 1) begin
            k_c = $signed(sa_cycle) - col;
            if (k_c >= 0 && k_c < N)
                col_val[col] = mat_b[k_c*N + col];
            else
                col_val[col] = {DATA_WIDTH{1'b0}};
        end
    end

    // -------------------------------------------------------------------------
    // SA output registers
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sa_en       <= 1'b0;
            sa_row_data <= 64'b0;
            sa_col_data <= 64'b0;
        end else begin
            sa_en <= (state == S_STREAM);
            if (state == S_STREAM) begin
                // Pack: sa_row_data[16*(row+1)-1 : 16*row] = row_val[row]
                sa_row_data <= {row_val[3], row_val[2], row_val[1], row_val[0]};
                sa_col_data <= {col_val[3], col_val[2], col_val[1], col_val[0]};
            end else begin
                sa_row_data <= 64'b0;
                sa_col_data <= 64'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Done signal (one-cycle pulse)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dma_done <= 1'b0;
        else
            dma_done <= (state == S_DONE);
    end

endmodule