module control_unit_checker (
    input logic clk,
    input logic reset,
    input logic [3:0] current_state, // Internal signal from control_unit
    input logic [6:0] op,
    input logic PCWrite,
    input logic IRWrite,
    input logic MemWrite,
    input logic RegWrite,
    input logic [1:0] ALUSrcA,
    input logic [1:0] ALUSrcB
);

    // ---------------------------------------------------------
    // 1. Basic State Transition Assertions
    // ---------------------------------------------------------

    // S0 (Fetch) should ALWAYS transition to S1 (Decode) on the next cycle
    property p_S0_to_S1;
        @(posedge clk) disable iff (reset)
        (current_state == 4'd0) |=> (current_state == 4'd1);
    endproperty
    assert_S0_to_S1: assert property (p_S0_to_S1) else $error("FSM Error: S0 did not go to S1");

    // Check Opcode-specific path: If Op is R-type, S1 must go to S6 (ExecuteR)
    property p_S1_to_S6_Rtype;
        @(posedge clk) disable iff (reset)
        (current_state == 4'd1 && op == 7'b0110011) |=> (current_state == 4'd6);
    endproperty
    assert_S1_to_S6: assert property (p_S1_to_S6_Rtype);

    // ---------------------------------------------------------
    // 2. Control Signal "Safety" Assertions
    // ---------------------------------------------------------

    // IRWrite should ONLY be active during Fetch (S0)
    property p_IRWrite_Safety;
        @(posedge clk) disable iff (reset)
        IRWrite |-> (current_state == 4'd0);
    endproperty
    assert_IRWrite_Safety: assert property (p_IRWrite_Safety);

    // MemWrite should ONLY be active during MemWrite state (S5)
    property p_MemWrite_Safety;
        @(posedge clk) disable iff (reset)
        MemWrite |-> (current_state == 4'd5);
    endproperty
    assert_MemWrite_Safety: assert property (p_MemWrite_Safety);

    // ---------------------------------------------------------
    // 3. Data Path Configuration Assertions
    // ---------------------------------------------------------

    // In S0 (Fetch), PC must be an operand (ALUSrcA = 00) and 4 must be the other (ALUSrcB = 10)
    property p_Fetch_ALU_Config;
        @(posedge clk) disable iff (reset)
        (current_state == 4'd0) |-> (ALUSrcA == 2'b00 && ALUSrcB == 2'b10);
    endproperty
    assert_Fetch_ALU: assert property (p_Fetch_ALU_Config);

endmodule

/*
    This SystemVerilog module is a checker for the control unit FSM of a simple RISC    
    processor. It uses assertions to verify that the FSM transitions correctly between states
    based on the opcode and that control signals are activated only in their appropriate states.

How to Bind the Template
In your testbench file (top-level), add this line to connect the checker to your existing control_unit instance:

Code snippet
bind control_unit control_unit_checker checker_inst (
    .clk(clk),
    .reset(reset),
    .current_state(current_state), // Binds to the internal reg/enum in your module
    .op(op),
    .PCWrite(PCWrite),
    .IRWrite(IRWrite),
    .MemWrite(MemWrite),
    .RegWrite(RegWrite),
    .ALUSrcA(ALUSrcA),
    .ALUSrcB(ALUSrcB)
);

Tips for Writing Your Own Assertions
Use the Implication Operator (|-> and |=>):

A |-> B: Overlapping implication. If A is true now, B must be true now. (Great for checking control signals in a specific state).

A |=> B: Non-overlapping implication. If A is true now, B must be true on the next clock edge. (Great for checking state transitions).

Check Mutual Exclusivity: Since you are using BRAM for PYNQ, write an assertion to ensure IRWrite and MemWrite are never high at the same time to prevent bus contention.

Validate the "Zero" Flag Path: Write an assertion for the BEQ state (S10) that checks if PCWrite only goes high if zero is 1.

Covergroup for Opcode Coverage: You can add cover property statements to ensure your testbench actually exercised every path in your FSM (e.g., verifying you actually hit the JAL and Load paths).
*/