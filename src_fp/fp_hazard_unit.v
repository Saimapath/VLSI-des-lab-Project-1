module fp_hazard_unit(
    // Decode Stage Sources
    input  wire [4:0] rs1d,
    input  wire [4:0] rs2d,
    input  wire [4:0] rs3d,

    // Execute Stage Sources/Destinations
    input  wire [4:0] rs1e, // Kept for lwstall consistency
    input  wire [4:0] rs2e, 
    input  wire [4:0] rs3e, 
    input  wire [4:0] rde,  
    
    // Memory and Writeback Destinations
    input  wire [4:0] rdm,  
    input  wire [4:0] rdw,
    
    // Control Signals
    input  wire       fp_regwritee, // ---> ADDED: Need Execute write-enable
    input  wire       fp_regwritem, 
    input  wire       fp_regwritew,
    input  wire       fp_mem_read_e, 
    input  wire       fp_requires_d, 
    
    // Hazard Outputs
    output reg  [1:0] forwarda_fp, 
    output reg  [1:0] forwardb_fp, 
    output reg  [1:0] forwardc_fp,
    output wire       fp_lwstall     
);

    // --- Forwarding for FP RS1 (DECODE STAGE) ---
    always @(*) begin
        // Note: f0 is not hardwired to zero in FP, so we don't check != 0
        if      (fp_regwritee && (rde == rs1d)) forwarda_fp = 2'b11; // Forward from Execute
        else if (fp_regwritem && (rdm == rs1d)) forwarda_fp = 2'b10; // Forward from Memory
        else if (fp_regwritew && (rdw == rs1d)) forwarda_fp = 2'b01; // Forward from Writeback
        else                                    forwarda_fp = 2'b00; // Normal RegFile
    end

    // --- Forwarding for FP RS2 (DECODE STAGE) ---
    always @(*) begin
        if      (fp_regwritee && (rde == rs2d)) forwardb_fp = 2'b11;
        else if (fp_regwritem && (rdm == rs2d)) forwardb_fp = 2'b10;
        else if (fp_regwritew && (rdw == rs2d)) forwardb_fp = 2'b01;
        else                                    forwardb_fp = 2'b00;
    end

    // --- Forwarding for FP RS3 (DECODE STAGE) ---
    always @(*) begin
        if      (fp_regwritee && (rde == rs3d)) forwardc_fp = 2'b11;
        else if (fp_regwritem && (rdm == rs3d)) forwardc_fp = 2'b10;
        else if (fp_regwritew && (rdw == rs3d)) forwardc_fp = 2'b01;
        else                                    forwardc_fp = 2'b00;
    end

    // --- FP Load-Use Stall Detection ---
    assign fp_lwstall = fp_mem_read_e && fp_requires_d && 
                        ((rs1d == rde) || (rs2d == rde) || (rs3d == rde));

endmodule