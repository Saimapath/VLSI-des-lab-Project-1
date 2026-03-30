
module hazard_unit(
    input  [4:0] rs1d, rs2d, rs1e, rs2e, rde, rdm, rdw,
    input        regwritem, regwritew, pcsrc_e,
    input  [1:0] resultsrce,
    input        valide, validm, validw,
    input        fp_lwstall,
    output reg [1:0] forwardae, forwardbe,
    output       stallf, stalld, flushe, flushd
);
    // --- Forwarding Logic ---
    // Forwarding handles Data Hazards (RAW) by bypassing values from MEM or WB
    always @(*) begin
        // Forward A (rs1)
        if (validm && ((rs1e == rdm) && regwritem) && (rs1e != 0)) forwardae = 2'b10; 
        else if (validw && ((rs1e == rdw) && regwritew) && (rs1e != 0)) forwardae = 2'b01; 
        else                                                  forwardae = 2'b00; // No forwarding
  // Forward B (rs2)
        if (validm && ((rs2e == rdm) && regwritem) && (rs2e != 0))      
            forwardbe = 2'b10;
        else if (validw && ((rs2e == rdw) && regwritew) && (rs2e != 0)) 
            forwardbe = 2'b01;
        else                                                  
            forwardbe = 2'b00;
    end

    // --- Stall and Flush Logic ---
    // Handles Load-Use hazards and Control hazards (Branching)
    // wire lwstall = resultsrce0 && ((rs1d == rde) || (rs2d == rde));
    wire lwstall = valide && (resultsrce == 2'b01) && (rde != 5'd0) && ((rs1d == rde) || (rs2d == rde));
    
    assign stallf = lwstall | fp_lwstall;              // Freeze PC
    assign stalld = lwstall | fp_lwstall;              // Freeze Decode
    assign flushd = pcsrc_e ;                          // Flush Decode on branch
    assign flushe = pcsrc_e || lwstall || fp_lwstall;  // Flush Execute on branch or load-stall
endmodule