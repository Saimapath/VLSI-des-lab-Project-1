module csr_hazard(
    input        CsrE, CsrM, CsrW,         // Enable signals from each stage
    input [11:0] WriteAddrE, WriteAddrM, WriteAddrW,
    input [11:0] ReadAddr,
    output reg [1:0] ForwardCSR,
    output reg [1:0] ForwardCSR_mepc,
    output reg [1:0] ForwardCSR_mstatus,
    output reg [1:0] ForwardCSR_mtvec
);

    always @(*) begin
        // Priority logic: Younger instructions (Execute) must override older ones
        if (CsrE && (ReadAddr == WriteAddrE)) begin
            ForwardCSR = 2'b11; // Forwarding from Execute
        end
        else if (CsrM && (ReadAddr == WriteAddrM)) begin
            ForwardCSR = 2'b10; // Forwarding from Memory
        end
        else if (CsrW && (ReadAddr == WriteAddrW)) begin
            ForwardCSR = 2'b01; // Forwarding from Writeback
        end
        else begin
            ForwardCSR = 2'b00; // No hazard, use original CSR read data
        end


        //for mstatus update
        if (CsrE && (12'h300 == WriteAddrE)) begin
            ForwardCSR_mstatus = 2'b11; // Forwarding from Execute
        end
        else if (CsrM && (12'h300 == WriteAddrM)) begin
            ForwardCSR_mstatus = 2'b10; // Forwarding from Memory
        end
        else if (CsrW && (12'h300 == WriteAddrW)) begin
            ForwardCSR_mstatus = 2'b01; // Forwarding from Writeback
        end
        else begin
            ForwardCSR_mstatus = 2'b00; // No hazard, use original CSR read data
        end


        //for mepc update
        if (CsrE && (12'h341 == WriteAddrE)) begin
            ForwardCSR_mepc = 2'b11; // Forwarding from Execute
        end
        else if (CsrM && (12'h341 == WriteAddrM)) begin
            ForwardCSR_mepc = 2'b10; // Forwarding from Memory
        end
        else if (CsrW && (12'h341 == WriteAddrW)) begin
            ForwardCSR_mepc = 2'b01; // Forwarding from Writeback
        end
        else begin
            ForwardCSR_mepc = 2'b00; // No hazard, use original CSR read data
        end


        //for mtvec update
        if (CsrE && (12'h305 == WriteAddrE)) begin
            ForwardCSR_mtvec = 2'b11; // Forwarding from Execute
        end
        else if (CsrM && (12'h305 == WriteAddrM)) begin
            ForwardCSR_mtvec = 2'b10; // Forwarding from Memory
        end
        else if (CsrW && (12'h305 == WriteAddrW)) begin
            ForwardCSR_mtvec = 2'b01; // Forwarding from Writeback
        end
        else begin
            ForwardCSR_mtvec = 2'b00; // No hazard, use original CSR read data
        end        
    end
    
endmodule