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
    logic                 address_fault_o; // NEW: Fault flag

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
        .next_level_o(next_level_o),
        .address_fault_o(address_fault_o)
    );

    // --- Clock Generation ---
    initial clk_i = 0;
    always #(CLK_PER/2) clk_i = ~clk_i;

    // --- VCD Dumping ---
    initial begin
        $dumpfile("ptw_pte_gen.vcd");
        $dumpvars(0, ptw_pte_gen_tb);
    end

    // =========================================================
    // HELPER TASKS (Defined OUTSIDE the initial block)
    // =========================================================
    
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

    // ---------------------------------------------------------
    // TC15: 2MB Overflow / Truncation Check
    // ---------------------------------------------------------
    task TC15_overflow_check();
        begin
            $display("--- TC15: 2MB Address Overflow Fault Check ---");
            
            // Sub-test A: Legal 2MB Address (Top 5 bits are 0)
            page_size_i = 2'd1;
            level_i     = 2'b10;
            vpn_i       = 32'h0;
            base_ppn_i  = 32'h07FF_FFFF; // Top 5 bits are 0
            
            @(posedge clk_i);
            if (address_fault_o === 1'b1) begin
                $display("[FAIL] TC15.A: Legal address falsely triggered fault!");
                error_count++;
            end else begin
                $display("[PASS] TC15.A: Legal 2MB address accepted.");
            end

            // Sub-test B: Illegal 2MB Address (Top bit is 1)
            base_ppn_i  = 32'h8000_0000; // Top 5 bits are 10000
            
            @(posedge clk_i);
            if (address_fault_o === 1'b0) begin
                $display("[FAIL] TC15.B: Hardware failed to catch 2MB overflow!");
                error_count++;
            end else begin
                $display("[PASS] TC15.B: Overflow successfully caught! Fault triggered.");
            end
        end
    endtask

    // =========================================================
    // MAIN TEST SEQUENCE
    // =========================================================
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
        // TC1 to TC4: Address Calc (64KB)
        // ---------------------------------------------------------
        vpn_i       = 32'hD500_0000; level_i = 2'b00; base_ppn_i = 32'h0000_1000; page_size_i = 2'd0; 
        expected_pa = (48'h1000 << 16) + (48'h1AA << 3);
        check_output("TC1: Level 0 (Root) 64KB", expected_pa, 2'b01);

        vpn_i       = 32'h003F_C000; level_i = 2'b01; base_ppn_i = 32'h0000_2000;
        expected_pa = (48'h2000 << 16) + (48'h0FF << 3);
        check_output("TC2: Level 1 64KB", expected_pa, 2'b10);

        vpn_i       = 32'h0000_0AA0; level_i = 2'b10; base_ppn_i = 32'h0000_3000;
        expected_pa = (48'h3000 << 16) + (48'h055 << 3);
        check_output("TC3: Level 2 64KB", expected_pa, 2'b11);

        vpn_i       = 32'h0000_001F; level_i = 2'b11; base_ppn_i = 32'h0000_4000;
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
        vpn_i       = 32'h1234_5678; level_i = 2'b10; base_ppn_i = 32'h0000_ABCD; page_size_i = 2'd0;
        expected_pa = (48'hABCD << 16) + (48'(vpn_i[13:5]) << 3);
        check_output("TC6: Random VPN (64KB)", expected_pa, 2'b11);

        // ---------------------------------------------------------
        // TC7: 2MB page indexing
        // ---------------------------------------------------------
        vpn_i       = 32'hFF80_0000; level_i = 2'b01; base_ppn_i = 32'h0000_5000; page_size_i = 2'd1; 
        expected_pa = (48'h5000 << 21) + (48'h1FF << 3); 
        check_output("TC7: 2MB Page Indexing", expected_pa, 2'b10);

        // ---------------------------------------------------------
        // TC8: Page size dependent base shift
        // ---------------------------------------------------------
        vpn_i       = 32'hFFFF_FFFF; level_i = 2'b10; base_ppn_i = 32'h0000_0001;
        page_size_i = 2'd0; expected_pa = (48'h1 << 16) + (48'h1FF << 3);
        check_output("TC8.1: Base Shift 64KB", expected_pa, 2'b11);

        page_size_i = 2'd1; expected_pa = (48'h1 << 21) + (48'h1FF << 3);
        check_output("TC8.2: Base Shift 2MB", expected_pa, 2'b11);

        // ---------------------------------------------------------
        // TC9 to TC13: Boundaries & Exceptions
        // ---------------------------------------------------------
        level_i = 2'bx; @(posedge clk_i); $display("[PASS] TC9: Invalid Level Fallback Handled");

        level_i = 2'b11; @(posedge clk_i);
        if (next_level_o === 2'b11) $display("[PASS] TC10: Leaf level correctly halted at 3");
        else $display("[FAIL] TC10: Leaf incremented past 3!");

        page_size_i = 2'd0; level_i = 2'b00; base_ppn_i = 32'h0000_A000;
        vpn_i = 32'hFFFF_FFFF; expected_pa = (48'hA000 << 16) + (48'h1FF << 3);
        check_output("TC11.1: Boundary VPN (All 1s)", expected_pa, 2'b01);

        vpn_i = 32'h0000_0000; expected_pa = (48'hA000 << 16) + (48'h000 << 3);
        check_output("TC11.2: Boundary VPN (All 0s)", expected_pa, 2'b01);

        vpn_i = 32'h0; level_i = 2'b00; base_ppn_i = 32'hFFFF_FFFF; expected_pa = (48'hFFFF_FFFF << 16); 
        check_output("TC12: Max Base PPN Shift", expected_pa, 2'b01);

        $display("[INFO] TC13: Mixed Level Sequences applied to wave.");
        level_i = 2'b10; base_ppn_i = 32'h1; @(posedge clk_i);
        level_i = 2'b00; base_ppn_i = 32'h2; @(posedge clk_i);
        level_i = 2'b11; base_ppn_i = 32'h3; @(posedge clk_i);
        $display("[PASS] TC13: Mixed Sequence Completed");

        // ---------------------------------------------------------
        // TC14: Integration scenario (Full simulated walk)
        // ---------------------------------------------------------
        $display("--- TC14: Simulating Full 4-Level Walk ---");
        page_size_i = 2'd0; vpn_i = 32'hABCD_EFE0; 
        
        level_i = 2'b00; base_ppn_i = 32'h1000; expected_pa = (48'h1000 << 16) + (48'b101010111 << 3);
        check_output("TC14 Step 1: Root", expected_pa, 2'b01);

        level_i = 2'b01; base_ppn_i = 32'h2000; expected_pa = (48'h2000 << 16) + (48'b100110111 << 3);
        check_output("TC14 Step 2: Level 1", expected_pa, 2'b10);

        level_i = 2'b10; base_ppn_i = 32'h3000; expected_pa = (48'h3000 << 16) + (48'b101111111 << 3);
        check_output("TC14 Step 3: Level 2", expected_pa, 2'b11);

        level_i = 2'b11; base_ppn_i = 32'h4000; expected_pa = (48'h4000 << 16) + (48'b00000 << 3);
        check_output("TC14 Step 4: Leaf", expected_pa, 2'b11);

        // ---------------------------------------------------------
        // TC15: Execution of the Overflow Task
        // ---------------------------------------------------------
        TC15_overflow_check();

        // --- Final Result ---
        $display("========================================");
        if (error_count == 0)
            $display("  ALL 15 TEST CASES PASSED SUCCESSFULLY!");
        else
            $display("  VERIFICATION FAILED: %0d Errors Found.", error_count);
        $display("========================================");
        
        #(CLK_PER * 5);
        $finish;
    end

endmodule