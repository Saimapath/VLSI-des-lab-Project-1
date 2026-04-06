module hazard_unit(
    input  [4:0] rs1d, rs2d, rs1e, rs2e, rde, rdm, rdw, held_rd, // <-- ADDED held_rd
    input        regwritee, regwritem, regwritew, held_regwrite, // <-- ADDED held_regwrite
    input        pcsrc_e,
    input  [1:0] resultsrce, resultsrcm,
    input        valide, validm, validw,
    output reg [1:0] forwardae, forwardbe,
    output       stallf, stalld, flushe, flushd
);
    // --- Forwarding Logic (in Execute Stage) ---
    always @(*) begin
        // Forward A (rs1 in Execute)
        if (validm && ((rs1e == rdm) && regwritem) && (rs1e != 0)) 
            forwardae = 2'b10; // 1. Forward from MEM
        else if (validw && ((rs1e == rdw) && regwritew) && (rs1e != 0)) 
            forwardae = 2'b01; // 2. Forward from WB
        else if (((rs1e == held_rd) && held_regwrite) && (rs1e != 0)) 
            forwardae = 2'b11; // 3. ---> NEW: Forward from Holding DFF
        else 
            forwardae = 2'b00; // 4. RegFile
            
        // Forward B (rs2 in Execute)
        if (validm && ((rs2e == rdm) && regwritem) && (rs2e != 0))      
            forwardbe = 2'b10; // 1. Forward from MEM
        else if (validw && ((rs2e == rdw) && regwritew) && (rs2e != 0)) 
            forwardbe = 2'b01; // 2. Forward from WB
        else if (((rs2e == held_rd) && held_regwrite) && (rs2e != 0))
            forwardbe = 2'b11; // 3. ---> NEW: Forward from Holding DFF
        else                                                  
            forwardbe = 2'b00; // 4. RegFile
    end

    // --- Stall and Flush Logic ---
    // (This remains unchanged! Because you check both _e and _m, 
    // it automatically stalls the pipeline for 2 cycles, allowing the 
    // data to safely reach the Holding DFF!)
    wire lwstall_e = valide && (resultsrce == 2'b01) && (rde != 5'd0) && ((rs1d == rde) || (rs2d == rde));
    wire lwstall_m = validm && (resultsrcm == 2'b01) && (rdm != 5'd0) && ((rs1d == rdm) || (rs2d == rdm));
    
    wire stall_req = lwstall_e || lwstall_m;
    
    assign stallf = stall_req;             
    assign stalld = stall_req;             
    assign flushd = pcsrc_e;               
    assign flushe = pcsrc_e || stall_req;  
endmodule