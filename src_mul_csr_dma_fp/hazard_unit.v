module hazard_unit(
    input  [4:0] rs1d, rs2d, rs1e, rs2e, rde, rdm, rdw, 
    input        regwritee, regwritem, regwritew, 
    input        trap_taken, // NEW: Interrupt detected in Execute [cite: 291]
    input        is_mret, 
    input        pcsrc_e,
    input  [1:0] resultsrce, resultsrcm,
    input        fp_sys_stall, 
    input        execbusy,          // ---> ADDED: Multiplier busy signal
    
    output       stallf, stalld_pc, stalld_pc4, stalle, stallm, stallw,
    input        valide, validm, validw,
    input        fp_lwstall,        
    output reg [1:0] forwardad, forwardbd,
    
    output       flushe, flushd
);

    // --- 1. PRE-COMPUTE BOOLEAN MATCHES ---
    wire match_1_e = valide && regwritee && (rs1d != 0) && (rs1d == rde);
    wire match_1_m = validm && regwritem && (rs1d != 0) && (rs1d == rdm);
    wire match_1_w = validw && regwritew && (rs1d != 0) && (rs1d == rdw);
    
    wire match_2_e = valide && regwritee && (rs2d != 0) && (rs2d == rde);
    wire match_2_m = validm && regwritem && (rs2d != 0) && (rs2d == rdm);
    wire match_2_w = validw && regwritew && (rs2d != 0) && (rs2d == rdw);

    // --- 2. FLATTENED FORWARDING MUX ---
    always @(*) begin
        // Forward A
        if      (match_1_e) forwardad = 2'b11;
        else if (match_1_m) forwardad = 2'b10;
        else if (match_1_w) forwardad = 2'b01;
        else                forwardad = 2'b00;
        
        // Forward B
        if      (match_2_e) forwardbd = 2'b11;
        else if (match_2_m) forwardbd = 2'b10;
        else if (match_2_w) forwardbd = 2'b01;
        else                forwardbd = 2'b00;
    end

    // --- Stall and Flush Logic ---
    wire lwstall_e = valide && (resultsrce == 2'b01) && (rde != 5'd0) && ((rs1d == rde) || (rs2d == rde));
    wire lwstall_m = validm && (resultsrcm == 2'b01) && (rdm != 5'd0) && ((rs1d == rdm) || (rs2d == rdm));


    wire ctrl_hazard = pcsrc_e || trap_taken || is_mret;
    // Combine FP Stalls and Multiplier Stalls into a global freeze
    wire global_freeze = fp_sys_stall | execbusy;

    (* keep = "true" *) wire stall_req_F   = lwstall_e || lwstall_m || fp_lwstall;
    (* keep = "true" *) wire stall_req_D1  = lwstall_e || lwstall_m || fp_lwstall;
    (* keep = "true" *) wire stall_req_D2  = lwstall_e || lwstall_m || fp_lwstall;
    (* keep = "true" *) wire stall_req_E   = lwstall_e || lwstall_m || fp_lwstall;

    // Apply the Global freeze to EVERY stage!
    assign stallf     = stall_req_F  || global_freeze;
    assign stalld_pc  = stall_req_D1 || global_freeze;             
    assign stalld_pc4 = stall_req_D2 || global_freeze;
    assign stalle     = global_freeze;
    assign stallm     = global_freeze;
    assign stallw     = global_freeze;
    
    // CRITICAL: Do not allow a branch to flush the pipeline while math is stalling!
    assign flushe     = (ctrl_hazard || stall_req_E);
    //  && !global_freeze;
    assign flushd     = ctrl_hazard;
    //  && !global_freeze;

endmodule