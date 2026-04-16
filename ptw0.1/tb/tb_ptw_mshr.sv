`timescale 1ns/1ps

module ptw_mshr_tb;

    // --- Parameters ---
    parameter MSHR_ENTRIES = 8;
    parameter CLK_PERIOD   = 10; // 100 MHz

    // --- Signal Declarations ---
    logic clk_i;
    logic rst_n_i;

    // Allocation Interface
    logic        alloc_en_i;
    logic [31:0] ptw_tlb_req_vpn_i;
    logic [3:0]  ptw_tlb_req_id_i;
    logic [2:0]  ptw_tlb_req_perm_i;
    logic [1:0]  start_level_i;

    // Update Interface
    logic        update_en_i;
    logic [2:0]  update_idx_i;
    logic [1:0]  update_level_i;
    logic [47:0] update_pte_addr_i;
    logic [63:0] update_pte_data_i;

    // Deallocation & Flush
    logic        dealloc_en_i;
    logic [2:0]  dealloc_idx_i;
    logic        flush_i;

    // Outputs
    logic        mshr_free_o;
    logic        alloc_valid_o;
    logic [2:0]  alloc_idx_o;
    logic [7:0]  mshr_valid_o;
    logic [7:0][1:0]  mshr_level_o;
    logic [7:0][31:0] mshr_vpn_o;
    logic [7:0][47:0] mshr_pte_addr_o;
    logic [7:0][63:0] mshr_pte_data_o;
    logic [7:0][2:0]  mshr_perm_o;
    logic [7:0][3:0]  mshr_req_id_o;

    // --- DUT Instantiation ---
    ptw_mshr dut (.*);

    // --- Clock Generation ---
    initial clk_i = 0;
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // --- Waveform Dumping ---
    initial begin
        $dumpfile("ptw_mshr.vcd");
        $dumpvars(0, ptw_mshr_tb);
    end

    // --- Helper Tasks ---
    
    // Reset Logic
    task reset_dut();
        begin
            rst_n_i      = 0;
            alloc_en_i   = 0;
            update_en_i  = 0;
            dealloc_en_i = 0;
            flush_i      = 0;
            #(CLK_PERIOD * 2);
            rst_n_i      = 1;
            $display("DUT Reset Complete.");
        end
    endtask

    // Allocation Task
    task allocate(input [31:0] vpn, input [3:0] id, input [1:0] lvl);
        begin
            @(posedge clk_i);
            alloc_en_i        <= 1;
            ptw_tlb_req_vpn_i <= vpn;
            ptw_tlb_req_id_i  <= id;
            start_level_i     <= lvl;
            @(posedge clk_i);
            alloc_en_i        <= 0;
        end
    endtask

    // --- Test Cases ---

    task TC1_single_alloc();
        begin
            $display("TC1: Single Allocation");
            allocate(32'h1, 4'h1, 2'b00);
        end
    endtask

    task TC2_seq_alloc();
        begin
            $display("TC2: Sequential Allocation");
            for (int i=0; i<4; i++) begin
                allocate(i + 10, i + 2, 2'b00);
            end
        end
    endtask

    task TC3_dealloc();
        begin
            $display("TC3: Deallocate Index 2");
            @(posedge clk_i);
            dealloc_en_i  <= 1;
            dealloc_idx_i <= 2;
            @(posedge clk_i);
            dealloc_en_i  <= 0;
        end
    endtask

    task TC4_update();
        begin
            $display("TC4: Update Entry Index 1");
            @(posedge clk_i);
            update_en_i       <= 1;
            update_idx_i      <= 1;
            update_pte_data_i <= 64'hAAAA_BBBB_CCCC_DDDD;
            update_pte_addr_i <= 48'h1234_5678_9ABC;
            update_level_i    <= 2'b01;
            @(posedge clk_i);
            update_en_i       <= 0;
        end
    endtask

    task TC5_fill_full();
        begin
            $display("TC5: Fill MSHR to Full Capacity");
            for (int i=0; i<8; i++) begin
                allocate(32'hF00 + i, i, 2'b11);
            end
        end
    endtask

    task TC6_alloc_when_full();
        begin
            $display("TC6: Attempt Allocation when FULL");
            allocate(32'hDEAD, 4'hF, 2'b00);
            if (alloc_valid_o) $display("ERROR: Allocation occurred while full!");
        end
    endtask

    task TC7_dealloc_last();
        begin
            $display("TC7: Deallocate Boundary Index 7");
            @(posedge clk_i);
            dealloc_en_i  <= 1;
            dealloc_idx_i <= 7;
            @(posedge clk_i);
            dealloc_en_i  <= 0;
        end
    endtask

    task TC8_reuse_slot();
        begin
            $display("TC8: Verify Slot Reuse (Should hit Index 7)");
            allocate(32'hBEEF, 4'hA, 2'b10);
        end
    endtask

    task TC9_global_flush();
        begin
            $display("TC9: Global Flush Test");
            TC5_fill_full(); // Ensure it's full first
            repeat(2) @(posedge clk_i);
            
            flush_i <= 1;
            @(posedge clk_i);
            flush_i <= 0;
            
            repeat(1) @(posedge clk_i);
            if (mshr_valid_o === 8'h00) 
                $display("TC9 PASS: MSHR Global Flush Successful.");
            else 
                $display("TC9 FAIL: MSHR valid bits remain: %h", mshr_valid_o);
        end
    endtask

    // --- Main Test Execution ---
    initial begin
        // --- Initialization ---
        reset_dut();

        // --- Part 1: Functional Logic ---
        TC1_single_alloc();
        #(CLK_PERIOD);
        TC2_seq_alloc();
        #(CLK_PERIOD);
        TC3_dealloc();
        #(CLK_PERIOD);
        TC4_update();
        #(CLK_PERIOD * 5);

        // --- Part 2: Stress & Corner Cases ---
        $display("--- Starting Stress and Corner Case Tests ---");
        reset_dut(); // Fresh start for stress test

        TC5_fill_full();
        #(CLK_PERIOD);
        TC6_alloc_when_full();
        #(CLK_PERIOD);
        TC7_dealloc_last();
        #(CLK_PERIOD);
        TC8_reuse_slot();
        #(CLK_PERIOD * 5);

        // --- Part 3: Flush Control ---
        TC9_global_flush();

        // --- Cleanup ---
        #(CLK_PERIOD * 10);
        $display("==== ALL TESTS COMPLETE: VERIFICATION FINISHED ====");
        $finish;
    end

endmodule