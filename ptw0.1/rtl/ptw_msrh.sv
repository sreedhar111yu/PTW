`timescale 1ns/1ps 

module ptw_mshr #( 

    parameter int MSHR_ENTRIES = 8, 
    parameter int VPN_WIDTH    = 32, 
    parameter int PTE_WIDTH    = 64, 
    parameter int PA_WIDTH     = 48, 
    parameter int PERM_WIDTH   = 3, 
    parameter int REQ_ID_WIDTH = 4 

)( 

    input  logic clk_i, 
    input  logic rst_n_i, 

    // --- Allocation Interface --- 

    input  logic                         alloc_en_i, 
    input  logic [VPN_WIDTH-1:0]         ptw_tlb_req_vpn_i, 
    input  logic [REQ_ID_WIDTH-1:0]      ptw_tlb_req_id_i, 
    input  logic [PERM_WIDTH-1:0]        ptw_tlb_req_perm_i, 
    input  logic [1:0]                   start_level_i, 
    output logic                         mshr_free_o, 
    output logic                         alloc_valid_o, 
    output logic [$clog2(MSHR_ENTRIES)-1:0] alloc_idx_o, 

    // --- Update Interface --- 

    input  logic                         update_en_i, 
    input  logic [$clog2(MSHR_ENTRIES)-1:0] update_idx_i, 
    input  logic [1:0]                   update_level_i, 
    input  logic [PA_WIDTH-1:0]          update_pte_addr_i, 
    input  logic [PTE_WIDTH-1:0]         update_pte_data_i, 

    // --- Deallocation Interface --- 

    input  logic                         dealloc_en_i, 
    input  logic [$clog2(MSHR_ENTRIES)-1:0] dealloc_idx_i, 

    // --- Flush MSHR ---
    input  logic flush_i,

    // --- Status/Broadside Outputs --- 

    output logic [MSHR_ENTRIES-1:0]                   mshr_valid_o, 
    output logic [MSHR_ENTRIES-1:0][1:0]              mshr_level_o, 
    output logic [MSHR_ENTRIES-1:0][VPN_WIDTH-1:0]    mshr_vpn_o, 
    output logic [MSHR_ENTRIES-1:0][PA_WIDTH-1:0]     mshr_pte_addr_o, 
    output logic [MSHR_ENTRIES-1:0][PTE_WIDTH-1:0]    mshr_pte_data_o, 
    output logic [MSHR_ENTRIES-1:0][PERM_WIDTH-1:0]   mshr_perm_o, 
    output logic [MSHR_ENTRIES-1:0][REQ_ID_WIDTH-1:0] mshr_req_id_o 

); 

    // Internal Struct and Array 

    typedef struct packed { 
        logic                    valid; 
        logic [1:0]              level; 
        logic [VPN_WIDTH-1:0]    vpn; 
        logic [PA_WIDTH-1:0]     pte_addr; 
        logic [PTE_WIDTH-1:0]    pte_data; 
        logic [PERM_WIDTH-1:0]   perm; 
        logic [REQ_ID_WIDTH-1:0] req_id; 
    } mshr_entry_t; 

    mshr_entry_t mshr_array [MSHR_ENTRIES]; 
    // Priority Encoder Logic 

    logic [$clog2(MSHR_ENTRIES)-1:0] free_idx_int; 
    logic                            found_free; 

    always_comb begin 
        found_free   = 1'b0; 
        free_idx_int = '0; 
        for (int i = 0; i < MSHR_ENTRIES; i++) begin 
            if (!mshr_array[i].valid && !found_free) begin 
                found_free   = 1'b1; 
                free_idx_int = i[$clog2(MSHR_ENTRIES)-1:0]; 
            end 
        end 
    end 

    // Combinational Output Assignments 

    assign mshr_free_o    = found_free; 
    assign alloc_valid_o  = alloc_en_i & found_free; 
    assign alloc_idx_o    = free_idx_int; 

    // Sequential Logic Block 

   always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mshr_array <= '{default: '0}; 
        end else if (flush_i) begin
            // TC9: Global Flush - Invalidates all entries in one cycle
            for (int i = 0; i < MSHR_ENTRIES; i++) begin
                mshr_array[i].valid <= 1'b0;
            end
        end else begin
            // 1. Deallocation
            if (dealloc_en_i) begin
                if (mshr_array[dealloc_idx_i].valid) begin
                    mshr_array[dealloc_idx_i].valid <= 1'b0;
                end
            end

            // 2. Update
            if (update_en_i) begin
                if (mshr_array[update_idx_i].valid) begin
                    mshr_array[update_idx_i].level    <= update_level_i;
                    mshr_array[update_idx_i].pte_addr <= update_pte_addr_i;
                    mshr_array[update_idx_i].pte_data <= update_pte_data_i;
                end
            end

            // 3. Allocation
            if (alloc_en_i && found_free) begin
                mshr_array[free_idx_int]          <= '0; 
                mshr_array[free_idx_int].valid    <= 1'b1;
                mshr_array[free_idx_int].level    <= start_level_i;
                mshr_array[free_idx_int].vpn      <= ptw_tlb_req_vpn_i;
                mshr_array[free_idx_int].req_id   <= ptw_tlb_req_id_i;
                mshr_array[free_idx_int].perm     <= ptw_tlb_req_perm_i;
            end
        end
    end

    // Broadside Output Mapping 

    always_comb begin 
        for (int i = 0; i < MSHR_ENTRIES; i++) begin 
            mshr_valid_o[i]    = mshr_array[i].valid; 
            mshr_level_o[i]    = mshr_array[i].level; 
            mshr_vpn_o[i]      = mshr_array[i].vpn; 
            mshr_pte_addr_o[i] = mshr_array[i].pte_addr; 
            mshr_pte_data_o[i] = mshr_array[i].pte_data; 
            mshr_perm_o[i]     = mshr_array[i].perm; 
            mshr_req_id_o[i]   = mshr_array[i].req_id; 

        end 

    end 

endmodule 