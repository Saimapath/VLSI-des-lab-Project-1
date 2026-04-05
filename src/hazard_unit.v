module hazard_unit(
    input  [4:0] rs1d, rs2d, rde, rdm, rdw,
    input        regwritee, regwritem, regwritew, pcsrc_e,
    input  [1:0] resultsrce, resultsrcm, // ADDED: resultsrcm to check MEM stage
    input        valide, validm, validw,
    output reg [1:0] forwardad, forwardbd,
    output       stallf, stalld, flushe, flushd
);
    // --- Forwarding Logic (in Decode Stage) ---
    // Prioritize the youngest instruction (EX > MEM > WB)
    always @(*) begin
        // Forward A (rs1 in Decode)
        if (valide && ((rs1d == rde) && regwritee) && (rs1d != 0)) 
            forwardad = 2'b11; // 1. Forward from EX (ALUResultE)
        else if (validm && ((rs1d == rdm) && regwritem) && (rs1d != 0)) 
            forwardad = 2'b10; // 2. Forward from MEM (ALUResultM)
        else if (validw && ((rs1d == rdw) && regwritew) && (rs1d != 0)) 
            forwardad = 2'b01; // 3. Forward from WB (ResultW)
        else 
            forwardad = 2'b00; // 4. RegFile
            
        // Forward B (rs2 in Decode)
        if (valide && ((rs2d == rde) && regwritee) && (rs2d != 0))      
            forwardbd = 2'b11; // 1. Forward from EX
        else if (validm && ((rs2d == rdm) && regwritem) && (rs2d != 0))      
            forwardbd = 2'b10; // 2. Forward from MEM
        else if (validw && ((rs2d == rdw) && regwritew) && (rs2d != 0)) 
            forwardbd = 2'b01; // 3. Forward from WB
        else                                                  
            forwardbd = 2'b00; // 4. RegFile
    end

    // --- Stall and Flush Logic ---
    
    // 1. If Load is in EX (requires 2 stalls to reach WB)
    wire lwstall_e = valide && (resultsrce == 2'b01) && (rde != 5'd0) && ((rs1d == rde) || (rs2d == rde));
    
    // 2. If Load is in MEM (requires 1 stall to reach WB)
    wire lwstall_m = validm && (resultsrcm == 2'b01) && (rdm != 5'd0) && ((rs1d == rdm) || (rs2d == rdm));
    
    // Combined stall condition
    wire stall_req = lwstall_e || lwstall_m;
    
    assign stallf = stall_req;             // Freeze PC
    assign stalld = stall_req;             // Freeze Decode
    assign flushd = pcsrc_e;               // Flush Decode on branch
    assign flushe = pcsrc_e || stall_req;  // Flush Execute on branch or load-stall
endmodule