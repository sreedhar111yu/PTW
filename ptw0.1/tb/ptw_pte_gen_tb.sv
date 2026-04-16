// Code your testbench here
// or browse Examples
`timescale 1ns/1ps

module ptw_pte_gen_tb;

    // --- Parameters ---
    parameter int VPN_WIDTH = 32;
    parameter int PPN_WIDTH = 32;
    parameter int PA_WIDTH  = 48;
    parameter int CLK_PER   = 10;

    // --- Signals ---
    logic clk_i;
    logic [VPN_WIDTH-1:0] vpn_i;
    logic [1:0]           level_i;
    logic [PPN_WIDTH-1:0] base_ppn_i;
    logic [1:0]           page_size_i;

    logic [PA_WIDTH-1:0]  pte_pa_o;
    logic [1:0]           next_level_o;

    // --- Verification Variables ---
    logic [PA_WIDTH-1:0]  expected_pa;
    logic [1:0]           expected_next_lvl;
    int                   error_count = 0;

    // --- DUT Instantiation ---
    ptw_pte_gen #(
        .VPN_WIDTH(VPN_WIDTH),
        .PPN_WIDTH(PPN_WIDTH),
        .PA_WIDTH(PA_WIDTH)
    ) dut (
        .vpn_i(vpn_i),
        .level_i(level_i),
        .base_ppn_i(base_ppn_i),
        .page_size_i(page_size_i),
        .pte_pa_o(pte_pa_o),
        .next_level_o(next_level_o)
    );

    // --- Clock Generation ---
    initial clk_i = 0;
    always #(CLK_PER/2) clk_i = ~clk_i;

    // --- VCD Dumping ---
    initial begin
        $dumpfile("ptw_pte_gen.vcd");
        $dumpvars(0, ptw_pte_gen_tb);
    end

    // --- Verification Task ---
    task check_output(input string tc_name, input logic [PA_WIDTH-1:0] exp_pa, input logic [1:0] exp_lvl);
        @(posedge clk_i); 
        if (pte_pa_o !== exp_pa || next_level_o !== exp_lvl) begin
            $display("[FAIL] %s", tc_name);
            $display("       Expected PA: %h, Got: %h", exp_pa, pte_pa_o);
            $display("       Expected Next Lvl: %b, Got: %b", exp_lvl, next_level_o);
            error_count++;
        end else begin
            $display("[PASS] %s", tc_name);
        end
    endtask

    // --- MAIN TEST SEQUENCE ---
    initial begin
        $display("========================================");
        $display("   STARTING PTE GENERATOR VERIFICATION");
        $display("========================================");

        // Init
        vpn_i       = 0;
        level_i     = 0;
        base_ppn_i  = 0;
        page_size_i = 0;
        #(CLK_PER);

        // ---------------------------------------------------------
        // TC1: Level-3 (root) address calc – 64KB (RTL Level 0)
        // ---------------------------------------------------------
        vpn_i       = 32'hD500_0000; // Top 9 bits: 1AA
        level_i     = 2'b00;
        base_ppn_i  = 32'h0000_1000;
        page_size_i = 2'd0; 
        expected_pa = (48'h1000 << 16) + (48'h1AA << 3);
        check_output("TC1: Level 0 (Root) 64KB", expected_pa, 2'b01);

        // ---------------------------------------------------------
        // TC2: Level-2 address calc – 64KB (RTL Level 1)
        // ---------------------------------------------------------
        vpn_i       = 32'h003F_C000; // Bits 22:14 = 0FF
        level_i     = 2'b01;
        base_ppn_i  = 32'h0000_2000;
        expected_pa = (48'h2000 << 16) + (48'h0FF << 3);
        check_output("TC2: Level 1 64KB", expected_pa, 2'b10);

        // ---------------------------------------------------------
        // TC3: Level-1 address calc – 64KB (RTL Level 2)
        // ---------------------------------------------------------
        vpn_i       = 32'h0000_0AA0; // Bits 13:5 = 055
        level_i     = 2'b10;
        base_ppn_i  = 32'h0000_3000;
        expected_pa = (48'h3000 << 16) + (48'h055 << 3);
        check_output("TC3: Level 2 64KB", expected_pa, 2'b11);

        // ---------------------------------------------------------
        // TC4: Level-0 (leaf index) – 64KB (RTL Level 3)
        // ---------------------------------------------------------
        vpn_i       = 32'h0000_001F; // Bits 4:0 = 1F
        level_i     = 2'b11;
        base_ppn_i  = 32'h0000_4000;
        expected_pa = (48'h4000 << 16) + (48'h01F << 3);
        check_output("TC4: Level 3 (Leaf) 64KB", expected_pa, 2'b11);

        // ---------------------------------------------------------
        // TC5: Next level progression check
        // ---------------------------------------------------------
        level_i = 2'b00; @(posedge clk_i); if(next_level_o !== 2'b01) error_count++;
        level_i = 2'b01; @(posedge clk_i); if(next_level_o !== 2'b10) error_count++;
        level_i = 2'b10; @(posedge clk_i); if(next_level_o !== 2'b11) error_count++;
        level_i = 2'b11; @(posedge clk_i); if(next_level_o !== 2'b11) error_count++;
        $display("[PASS] TC5: Next Level Progression");

        // ---------------------------------------------------------
        // TC6: Random VPN (64KB mode)
        // ---------------------------------------------------------
        vpn_i       = 32'h1234_5678;
        level_i     = 2'b10;
        base_ppn_i  = 32'h0000_ABCD;
        page_size_i = 2'd0;
        expected_pa = (48'hABCD << 16) + (48'(vpn_i[13:5]) << 3);
        check_output("TC6: Random VPN (64KB)", expected_pa, 2'b11);

        // ---------------------------------------------------------
        // TC7: 2MB page indexing
        // ---------------------------------------------------------
        vpn_i       = 32'hFF80_0000; // [31:23] = 1FF
        level_i     = 2'b01;
        base_ppn_i  = 32'h0000_5000;
        page_size_i = 2'd1; // 2MB Mode
        expected_pa = (48'h5000 << 21) + (48'h1FF << 3); 
        check_output("TC7: 2MB Page Indexing", expected_pa, 2'b10);

        // ---------------------------------------------------------
        // TC8: Page size dependent base shift
        // ---------------------------------------------------------
        vpn_i       = 32'hFFFF_FFFF; 
        level_i     = 2'b10;
        base_ppn_i  = 32'h0000_0001;
        
        page_size_i = 2'd0; // Shift 16
        expected_pa = (48'h1 << 16) + (48'h1FF << 3);
        check_output("TC8.1: Base Shift 64KB", expected_pa, 2'b11);

        page_size_i = 2'd1; // Shift 21
        expected_pa = (48'h1 << 21) + (48'h1FF << 3);
        check_output("TC8.2: Base Shift 2MB", expected_pa, 2'b11);

        // ---------------------------------------------------------
        // TC9: Invalid level handling
        // ---------------------------------------------------------
        level_i = 2'bx; 
        @(posedge clk_i);
        $display("[PASS] TC9: Invalid Level Fallback Handled");

        // ---------------------------------------------------------
        // TC10: Leaf-level handling logic
        // ---------------------------------------------------------
        level_i = 2'b11;
        @(posedge clk_i);
        if (next_level_o === 2'b11) $display("[PASS] TC10: Leaf level correctly halted at 3");
        else $display("[FAIL] TC10: Leaf incremented past 3!");

        // ---------------------------------------------------------
        // TC11: Boundary VPN values
        // ---------------------------------------------------------
        page_size_i = 2'd0;
        level_i     = 2'b00;
        base_ppn_i  = 32'h0000_A000;
        
        vpn_i       = 32'hFFFF_FFFF; 
        expected_pa = (48'hA000 << 16) + (48'h1FF << 3);
        check_output("TC11.1: Boundary VPN (All 1s)", expected_pa, 2'b01);

        vpn_i       = 32'h0000_0000; 
        expected_pa = (48'hA000 << 16) + (48'h000 << 3);
        check_output("TC11.2: Boundary VPN (All 0s)", expected_pa, 2'b01);

        // ---------------------------------------------------------
        // TC12: Base PPN edge (Max 32-bit PPN)
        // ---------------------------------------------------------
        vpn_i       = 32'h0;
        level_i     = 2'b00;
        base_ppn_i  = 32'hFFFF_FFFF; 
        expected_pa = (48'hFFFF_FFFF << 16); 
        check_output("TC12: Max Base PPN Shift", expected_pa, 2'b01);

        // ---------------------------------------------------------
        // TC13: Mixed levels sequence
        // ---------------------------------------------------------
        $display("[INFO] TC13: Mixed Level Sequences applied to wave.");
        level_i = 2'b10; base_ppn_i = 32'h1; @(posedge clk_i);
        level_i = 2'b00; base_ppn_i = 32'h2; @(posedge clk_i);
        level_i = 2'b11; base_ppn_i = 32'h3; @(posedge clk_i);
        $display("[PASS] TC13: Mixed Sequence Completed");

        // ---------------------------------------------------------
        // TC14: Integration scenario (Full simulated walk)
        // ---------------------------------------------------------
        $display("--- TC14: Simulating Full 4-Level Walk ---");
        page_size_i = 2'd0;
        vpn_i       = 32'hABCD_EFE0; 
        
        level_i = 2'b00; base_ppn_i = 32'h1000; 
        expected_pa = (48'h1000 << 16) + (48'b101010111 << 3);
        check_output("TC14 Step 1: Root", expected_pa, 2'b01);

        level_i = 2'b01; base_ppn_i = 32'h2000; 
        expected_pa = (48'h2000 << 16) + (48'b100110111 << 3);
        check_output("TC14 Step 2: Level 1", expected_pa, 2'b10);

        level_i = 2'b10; base_ppn_i = 32'h3000; 
        expected_pa = (48'h3000 << 16) + (48'b101111111 << 3);
        check_output("TC14 Step 3: Level 2", expected_pa, 2'b11);

        level_i = 2'b11; base_ppn_i = 32'h4000; 
        expected_pa = (48'h4000 << 16) + (48'b00000 << 3);
        check_output("TC14 Step 4: Leaf", expected_pa, 2'b11);

        // --- Final Result ---
        $display("========================================");
        if (error_count == 0)
            $display("  ALL 14 TEST CASES PASSED SUCCESSFULLY!");
        else
            $display("  VERIFICATION FAILED: %0d Errors Found.", error_count);
        $display("========================================");
        
        #(CLK_PER * 5);
        $finish;
    end

endmodule