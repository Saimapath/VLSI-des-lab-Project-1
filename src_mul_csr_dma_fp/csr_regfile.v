module csr_regfile(
    input         clk, reset,
    
    // Standard Read/Write Ports
    input  [11:0] read_addr,
    output [31:0] read_data,
    input  [11:0] write_addr,
    input  [31:0] write_data,
    input         we,

    // Performance Counter Increment Signals
    input         instr_retired, 

    // Hardware Trap/MRET Interface
    input         trap_taken,    
    input  [31:0] trap_pc,       
    input         is_mret,       
    output [31:0] mepc_out,      
    output [31:0] mtvec_out,     
    output [31:0] mstatus_out
);

    reg [31:0] mepc, mtvec, mstatus;
    reg [63:0] mcycle, minstret;

    assign mepc_out    = mepc;
    assign mtvec_out   = mtvec;
    assign mstatus_out = mstatus;

    // Read Logic
    assign read_data = (read_addr == 12'h341) ? mepc :
                       (read_addr == 12'h305) ? mtvec :
                       (read_addr == 12'h300) ? mstatus :
                       (read_addr == 12'hB00) ? mcycle[31:0] :
                       (read_addr == 12'hB02) ? minstret[31:0] : 32'b0;

    // Internal "next" wires to satisfy L-value requirements
    reg [31:0] mstatus_next;
    reg [31:0] mepc_next;

// Replace the always @(*) block in csr_regfile.v [cite: 118-124] with this:
    always @(*) begin
        // Start with current state
        mstatus_next = mstatus;
        mepc_next    = mepc;

        // --- Priority 1: Hardware Traps (Atomic) ---
        if (trap_taken) begin
            mstatus_next[3] = 1'b0; // Force MIE = 0
            mepc_next       = trap_pc;
        end 
        // --- Priority 2: MRET (Atomic) ---
        else if (is_mret) begin
            mstatus_next[3] = 1'b1; // Force MIE = 1
        end
        // --- Priority 3: Software Instruction Writes ---
        else if (we) begin
            if (write_addr == 12'h300) mstatus_next = write_data;
            if (write_addr == 12'h341) mepc_next    = write_data;
        end
    end

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            mepc     <= 32'b0;
            mtvec    <= 32'b0;
            mstatus  <= 32'h0;
            mcycle   <= 64'b0;
            minstret <= 64'b0;
        end else begin
            mcycle <= mcycle + 1;
            if (instr_retired) minstret <= minstret + 1;

            // Single assignments to satisfy compiler
            mepc    <= mepc_next;
            mstatus <= mstatus_next;

            // mtvec is simple software write
            if (we && (write_addr == 12'h305)) 
                mtvec <= write_data;
        end
    end
endmodule