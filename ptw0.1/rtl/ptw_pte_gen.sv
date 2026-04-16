// Code your design here
`timescale 1ns/1ps

module ptw_pte_gen #(
    parameter int VPN_WIDTH  = 32,
    parameter int PPN_WIDTH  = 32,
    parameter int PA_WIDTH   = 48
)(
    input  logic [VPN_WIDTH-1:0] vpn_i,
    input  logic [1:0]           level_i,
    input  logic [PPN_WIDTH-1:0] base_ppn_i,
    input  logic [1:0]           page_size_i,

    output logic [PA_WIDTH-1:0]  pte_pa_o,
    output logic [1:0]           next_level_o,
    output logic                 address_fault_o  // NEW: Fault flag
);

    logic [8:0]  vpn_idx;
    logic [47:0] base_addr;

    // ---------------------------
    // 1. Next Level Tracker (0 -> 1 -> 2 -> 3)
    // ---------------------------
    always_comb begin
        case (level_i)
            2'b00: next_level_o = 2'b01;
            2'b01: next_level_o = 2'b10;
            2'b10: next_level_o = 2'b11;
            2'b11: next_level_o = 2'b11; // Stay at leaf
            default: next_level_o = 2'b11;
        endcase
    end

    // ---------------------------
    // 2. Base Address Shift (MODIFIED FOR SAFETY)
    // ---------------------------
    always_comb begin
        case (page_size_i)
            // Explicitly cast to 48 bits BEFORE shifting to prevent truncation
            2'd0: base_addr = 48'(base_ppn_i) << 16; // 64KB
            2'd1: base_addr = 48'(base_ppn_i) << 21; // 2MB
            default: base_addr = 48'(base_ppn_i) << 16;
        endcase
    end

    // ---------------------------
    // 3. VPN Index Slicer
    // ---------------------------
    always_comb begin
        vpn_idx = '0; // Default to prevent latches

        if (page_size_i == 2'd0) begin // 64KB Page Size
            case (level_i)
                2'b00: vpn_idx = vpn_i[31:23];
                2'b01: vpn_idx = vpn_i[22:14];
                2'b10: vpn_idx = vpn_i[13:5];
                2'b11: vpn_idx = {4'b0, vpn_i[4:0]}; // Zero-extend 5 bits
            endcase
        end else begin // 2MB Page Size
            case (level_i)
                2'b01: vpn_idx = vpn_i[31:23];
                2'b10: vpn_idx = vpn_i[22:14];
                2'b11: vpn_idx = vpn_i[13:5];
                default: vpn_idx = '0;
            endcase
        end
    end

    // ---------------------------
    // 4. Final Physical Address
    // ---------------------------
    // Shift index by 3 (multiply by 8 bytes) and add to base
    assign pte_pa_o = base_addr + (48'(vpn_idx) << 3);

    // ---------------------------
    // 5. Overflow Fault Checker
    // ---------------------------
    always_comb begin
        address_fault_o = 1'b0; // Default to safe

        // If 2MB mode, shifting by 21 means top 5 bits MUST be zero.
        // 32 (PPN width) - (48 (PA Width) - 21 (Shift)) = 5 bits overflow
        if (page_size_i == 2'd1) begin
            if (base_ppn_i[31:27] != 5'b0) begin
                address_fault_o = 1'b1; // Trigger the fault!
            end
        end
    end

endmodule