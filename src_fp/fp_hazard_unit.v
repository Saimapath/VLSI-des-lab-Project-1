module fp_hazard_unit(
    // Decode Stage Sources (For Load-Use Detection)
    input  wire [4:0] rs1d,
    input  wire [4:0] rs2d,
    input  wire [4:0] rs3d,

    // Execute Stage Sources/Destinations
    input  wire [4:0] rs1e, 
    input  wire [4:0] rs2e, 
    input  wire [4:0] rs3e, // 3rd port for FMA
    input  wire [4:0] rde,  // Destination of instruction in Execute
    
    // Memory and Writeback Destinations
    input  wire [4:0] rdm, 
    input  wire [4:0] rdw,
    
    // Control Signals
    input  wire       fp_regwritem, 
    input  wire       fp_regwritew,
    input  wire       fp_mem_read_e, // 1 = FLW is currently in Execute
    input  wire       fp_requires_d, // 1 = Instruction in Decode uses FP Regs
    
    // Hazard Outputs
    output reg  [1:0] forwarda_fp, 
    output reg  [1:0] forwardb_fp, 
    output reg  [1:0] forwardc_fp,
    output wire       fp_lwstall     // ---> ADDED: Tell main CPU to freeze
);

    // --- Forwarding for FP RS1 ---
    always @(*) begin
        // Notice: No (rdm != 0) check!
        if (fp_regwritem && (rdm == rs1e)) 
            forwarda_fp = 2'b10; // Forward from Memory stage
        else if (fp_regwritew && (rdw == rs1e)) 
            forwarda_fp = 2'b01; // Forward from Writeback stage
        else 
            forwarda_fp = 2'b00; // No hazard, use regfile data
    end

    // --- Forwarding for FP RS2 ---
    always @(*) begin
        if (fp_regwritem && (rdm == rs2e)) 
            forwardb_fp = 2'b10;
        else if (fp_regwritew && (rdw == rs2e)) 
            forwardb_fp = 2'b01;
        else 
            forwardb_fp = 2'b00;
    end

    // --- Forwarding for FP RS3 ---
    always @(*) begin
        if (fp_regwritem && (rdm == rs3e)) 
            forwardc_fp = 2'b10;
        else if (fp_regwritew && (rdw == rs3e)) 
            forwardc_fp = 2'b01;
        else 
            forwardc_fp = 2'b00;
    end

    // --- FP Load-Use Stall Detection ---
    // If Execute has an FLW, and Decode has an FP instruction that needs the same register
    assign fp_lwstall = fp_mem_read_e && fp_requires_d && 
                        ((rs1d == rde) || (rs2d == rde) || (rs3d == rde));

endmodule