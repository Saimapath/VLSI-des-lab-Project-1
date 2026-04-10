module hazard_unit(
    input  [4:0] rs1d, rs2d, rs1e, rs2e, rde, rdm, rdw, 
    input        regwritee, regwritem, regwritew, 
    input        pcsrc_e,
    input  [1:0] resultsrce, resultsrcm,
    input        valide, validm, validw,
    output reg [1:0] forwardad, forwardbd,
    
    // Split stalld into two separate outputs to crush fanout
    output       stallf, stalld_pc, stalld_pc4, flushe, flushd
);

    // --- 1. PRE-COMPUTE BOOLEAN MATCHES (DECODE STAGE FORWARDING) ---
    // Doing this outside the always block allows Vivado to evaluate all 
    // of these conditions simultaneously in parallel LUTs.
    
    // Rs1 Matches (Comparing Decode registers to downstream pipeline registers)
    wire match_1_e = valide && regwritee && (rs1d != 0) && (rs1d == rde);
    wire match_1_m = validm && regwritem && (rs1d != 0) && (rs1d == rdm);
    wire match_1_w = validw && regwritew && (rs1d != 0) && (rs1d == rdw);
    
    // Rs2 Matches
    wire match_2_e = valide && regwritee && (rs2d != 0) && (rs2d == rde);
    wire match_2_m = validm && regwritem && (rs2d != 0) && (rs2d == rdm);
    wire match_2_w = validw && regwritew && (rs2d != 0) && (rs2d == rdw);

    // --- 2. FLATTENED FORWARDING MUX ---
    // Priority logic evaluates a single boolean flag, shrinking logic depth.
    always @(*) begin
        // Forward A
        if      (match_1_e) forwardad = 2'b11; // Forward from Execute
        else if (match_1_m) forwardad = 2'b10; // Forward from Memory
        else if (match_1_w) forwardad = 2'b01; // Forward from Writeback
        else                forwardad = 2'b00; // Normal RegFile
        
        // Forward B
        if      (match_2_e) forwardbd = 2'b11;
        else if (match_2_m) forwardbd = 2'b10;
        else if (match_2_w) forwardbd = 2'b01;
        else                forwardbd = 2'b00;
    end

    // --- Stall and Flush Logic (With LUT Cloning) ---
    // Standard Load-Use stall detection
    wire lwstall_e = valide && (resultsrce == 2'b01) && (rde != 5'd0) && ((rs1d == rde) || (rs2d == rde));
    wire lwstall_m = validm && (resultsrcm == 2'b01) && (rdm != 5'd0) && ((rs1d == rdm) || (rs2d == rdm));
    
    // Manual LUT replication to defeat the 100+ high-fanout routing delay
    (* keep = "true" *) wire stall_req_F   = lwstall_e || lwstall_m;
    (* keep = "true" *) wire stall_req_D1  = lwstall_e || lwstall_m;
    (* keep = "true" *) wire stall_req_D2  = lwstall_e || lwstall_m;
    (* keep = "true" *) wire stall_req_E   = lwstall_e || lwstall_m;
    
    assign stallf     = stall_req_F;              
    assign stalld_pc  = stall_req_D1;             
    assign stalld_pc4 = stall_req_D2;             
    assign flushe     = pcsrc_e || stall_req_E;   
    assign flushd     = pcsrc_e;               

endmodule