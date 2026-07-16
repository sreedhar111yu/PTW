`timescale 1ns / 1ps
//PTW WITH AR FIFO FEATURE ADDED, SELECT_PTE WORKING FINE, REQ_READY WORKING FINE, B_RESP WORKING FINE.  
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/14/2026 12:07:22 PM
// Design Name: 
// Module Name: ptw_n
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ptw_n
    #(
        parameter VA_W     = 48,
        parameter PA_W     = 48,
        parameter PPN_W    = 32,
        parameter ASID_W   = 32,
        parameter MSHR_N   = 16,       // need to change to 16 
        parameter AXI_ID_W = 4,       // log2(MSHR_N) will change from 3 to 4
        parameter REQ_ID_W = 2,
        parameter DATA_WIDTH = 1024,
        //parameter CNT_WIDTH = 8,
        parameter CNT_W  = 3,
        parameter DW = 32,
        parameter RESP_W = 16
    )
    (
        input  wire clk,
        input  wire rst_n,
    
    //Global config
     // SATP Register Bank (8 entries)   satp comment
     // Each entry = {ASID[31:0], PPN[31:0]}
    
        input wire [63:0] satp_entry0,
        input wire [63:0] satp_entry1,
        input wire [63:0] satp_entry2,
        input wire [63:0] satp_entry3,
        input wire [63:0] satp_entry4,
        input wire [63:0] satp_entry5,
        input wire [63:0] satp_entry6,
        input wire [63:0] satp_entry7,


        //input wire [PPN_W-1:0]	   satp_ppn,
        /* PTW request */
        input  wire                 req_valid,
        input  wire [VA_W-1:0]      req_va,
        input  wire [ASID_W-1:0]    req_asid,
        input  wire [REQ_ID_W-1:0]  req_id, //req id also to be captured
        //input  wire                 req_r,
        input  wire                 req_w,
        //input  wire                 req_x,
        output wire                 req_ready,
    
        /* PTW response */
        input  wire                 resp_ready,
        output reg [RESP_W-1:0]     resp_valid,
        output reg                  resp_fault,
        output reg [511:0]          resp_ppn,  //made 16 from 12
        output reg [1:0]            resp_page_size,
        output reg [ASID_W-1:0]     resp_asid,
        output reg [RESP_W*3-1:0]     resp_perms,
        //output reg [RESP_W-1:0]     resp_perm_w,
        //output reg [RESP_W-1:0]     resp_perm_x,
        output reg [RESP_W-1:0]     resp_perm_d,
        output reg [REQ_ID_W-1:0]   resp_req_id, //added
    
        /* AXI read */
        output reg                  ar_valid,
        output reg [PA_W-1:0]       ar_addr,
        output reg  [7:0]           ar_len,    // new signal added
        output reg  [2:0]           ar_size,   // new signal added
        output reg  [1:0]           ar_burst, //new signal added
        output reg [AXI_ID_W-1:0]   ar_id,
        input  wire                 ar_ready,
    
        input  wire                 r_valid,
        input  wire [DATA_WIDTH-1:0]r_data,
        input  wire [AXI_ID_W-1:0]  r_id,
    
        /* AXI write (D-bit update) */
        output reg                  aw_valid,
        output reg [PA_W-1:0]       aw_addr,
        output reg [AXI_ID_W-1:0]   aw_id,
        output reg  [7:0]           aw_len,    // new signal added
        output reg  [2:0]           aw_size,   // new signal added
        output reg  [1:0]           aw_burst, //new signal added
        input  wire                 aw_ready,
    
        output reg                  w_valid,
        output reg [1023:0]           w_data,
        input  wire                 w_ready,
    
        input  wire                 b_valid,
        input  wire [AXI_ID_W-1:0]  b_id,
        input  wire [2:0]           b_resp,
        input wire        invalidate_req,    //CHANGE added for asid invalid
        input wire [31:0] invalidate_asid,    //CHANGE added for asid invalid
        //  FLUSH LOGIC (ASID BASED)
        //input wire                        asid_flush_req,
        //input wire [ASID_W-1:0]           asid_flush_val,
    
        /* counters */
        output wire  [DW-1:0]  l2_rd_req_cnt_o,
        output wire  [DW-1:0]  l2_wr_req_cnt_o,
        output wire  [DW-1:0]  l2_rd_rsp_cnt_o,
        output wire  [DW-1:0]  l2_wr_rsp_cnt_o,
        output wire            l2_rd_req_cnt_overflow_o,
        output wire            l2_wr_req_cnt_overflow_o,
        output wire            l2_rd_rsp_cnt_overflow_o,
        output wire            l2_wr_rsp_cnt_overflow_o,
        output wire [CNT_W-1:0]cache_rd_hit_cnt_o,
        output wire [CNT_W-1:0]cache_wr_hit_cnt_o,
        output wire [CNT_W-1:0]cache_rd_miss_cnt_o,
        output wire [CNT_W-1:0]cache_wr_miss_cnt_o,
        output wire cache_rd_hit_cnt_overflow_o,
        output wire cache_wr_hit_cnt_overflow_o,
        output wire cache_rd_miss_cnt_overflow_o,
        output wire cache_wr_miss_cnt_overflow_o,
        output wire [DW-1:0]   axi_rd_req_cnt_o,
        output wire [DW-1:0]   axi_wr_req_cnt_o,
        output wire [DW-1:0]   axi_rd_rsp_cnt_o,
        output wire [DW-1:0]   axi_wr_rsp_cnt_o,
        output wire            axi_rd_req_cnt_overflow_o,
        output wire            axi_wr_req_cnt_overflow_o,
        output wire            axi_rd_rsp_cnt_overflow_o,
        output wire            axi_wr_rsp_cnt_overflow_o
    
    );
    
        /* ------------------ Constants ------------------ */
        localparam PS_64K = 2'b00;
        localparam PS_2M  = 2'b01;
    
        localparam M_IDLE   = 3'd0;	//keep issuing ARs here
        localparam M_WAIT_R = 3'd1;	//after AR, wait for R and then go back to IDLE
        localparam M_NEED_AW = 3'd2;//on reaching leaf and if D bit update
        localparam M_WAIT_B = 3'd3;//after AW, wait for B
        localparam M_DONE   = 3'd4;//after B
        localparam M_FAULT  = 3'd5;//error,either due to unexpected responses or malformed PTE from memory like no Valid, unexpected Leaf, no-Leaf
    
        localparam FSM_IDLE        = 3'd0;
        localparam FSM_DISPATCH    = 3'd1;
        localparam FSM_SCAN_MSHR   = 3'd2;
        localparam FSM_EVAL_MSHR   = 3'd3;
        localparam FSM_CHECK_CACHE = 3'd4;
        localparam FSM_ADVANCE     = 3'd5;
        localparam FSM_INVALIDATE  = 3'd6;
    
        localparam ACT_NONE        = 4'd0;
        localparam ACT_ALLOC       = 4'd1;
        localparam ACT_CACHE_NEXT  = 4'd2;
        localparam ACT_AR          = 4'd3;
        localparam ACT_HANDLE_R    = 4'd4;
        localparam ACT_ISSUE_AW    = 4'd5;
        localparam ACT_HANDLE_B    = 4'd6;
        localparam ACT_RETIRE      = 4'd7;
    
        /* ------------------ Helpers ------------------ */
        function [1:0] detect_page_size;
            input [1:0] level;
            begin
                detect_page_size = (level == 2'd2) ? PS_2M : PS_64K;
            end
        endfunction
    
        function [47:16] mask_ppn;   //made 16 from 12
            input [47:16] pte_ppn;   //made 16 
            input [VA_W-1:0] va;
            input [1:0] ps;
            begin
                if (ps == PS_2M)
                    mask_ppn = {pte_ppn[47:17], va[20:16]};
                else
                    mask_ppn = pte_ppn;
            end
        endfunction
    
        function need_d_update;
            input [63:0] pte;
            input w;
            begin
                need_d_update = w && !pte[7];
            end
        endfunction
    
    
    
    function [8:0] vpn_index;
        input [47:0] va;
        input [1:0]  level;
        begin
            case (level)
                2'd0: vpn_index = va[47:39];              // root (VPN3)
                2'd1: vpn_index = va[38:30];              // VPN2
                2'd2: vpn_index = va[29:21];              // VPN1
                2'd3: vpn_index = {4'b0, va[20:16]};      // leaf VPN0 (5 bits)
                default: vpn_index = 9'b0;
            endcase
        end
    endfunction
    
     /*===================FLUSH Signals=======================*/
        
        reg flush_in_prog;
        reg flush_req_r;
        reg [ASID_W-1:0] flush_asid_r;
    
        /* ================= FIFOs ================= */
    
        /* REQ FIFO */
        wire req_fifo_full, req_fifo_empty;
        wire [VA_W+ASID_W+REQ_ID_W:0] req_fifo_rdata;
        reg  req_fifo_rd;
    
        sync_fifo_fwft #(
            .DATA_WIDTH (VA_W+ASID_W+REQ_ID_W+1),
            .DEPTH (16),
            .AFULL_TH (2)
        ) req_fifo (
            .clk     (clk),
            .rst_n     (rst_n),
            .wr_en   (req_valid && !req_fifo_full),
            .wr_data ({req_id,req_w,req_asid,req_va}), //req_id added  // size is 85 depth 
            .full    (req_fifo_full),
            .rd_en   (req_fifo_rd),
            .rd_data (req_fifo_rdata), //85  83 now
            .empty   (req_fifo_empty),
            .almost_full()
        );
    
       // assign req_ready = !req_fifo_full;      original 
       reg [3:0] mshr_used_count  = 4'd0; 
        assign req_ready = !(mshr_used_count == 4'b1111) && !flush_in_prog; //CHANGE added for asid invalid
    
    
          /* AXI R FIFO */
        wire r_fifo_empty;
        wire [AXI_ID_W+1023:0] r_fifo_rdata;
        reg  r_fifo_rd;
        reg  [AXI_ID_W+63:0] r_fifo_rdata_64;
        sync_fifo_fwft #(
            .DATA_WIDTH (AXI_ID_W+1024),
            .DEPTH (16),
            .AFULL_TH (2)
        ) r_fifo (
            .clk     (clk),
            .rst_n     (rst_n),
            .wr_en   (r_valid),
            .wr_data ({r_id,r_data}),
            .full    (),
            .rd_en   (r_fifo_rd),
            .rd_data (r_fifo_rdata),
            .empty   (r_fifo_empty),
            .almost_full()
        );
    
        /* AXI B FIFO */
        wire b_fifo_empty;
        wire [AXI_ID_W+2:0] b_fifo_rdata;
        reg  b_fifo_rd;
    
        sync_fifo_fwft #(
            .DATA_WIDTH (AXI_ID_W+3),  //7
            .DEPTH (16),
            .AFULL_TH (2)
        ) b_fifo (
            .clk     (clk),
            .rst_n     (rst_n),
            .wr_en   (b_valid),
            .wr_data ({b_id,b_resp}),
            .full    (),
            .rd_en   (b_fifo_rd),
            .rd_data (b_fifo_rdata),
            .empty   (b_fifo_empty),
            .almost_full()
        );
        
        /* AXI AR FIFO*/
        wire ar_fifo_empty;
        wire ar_fifo_full;
        wire [AXI_ID_W+PA_W+12:0] ar_fifo_rdata;
        reg  ar_fifo_rd;
        reg [PA_W-1:0]ar_addr_temp;
        reg a_valid;
        reg [AXI_ID_W-1:0] idx;
        reg [AXI_ID_W-1:0] ar_fifo_idx;
        sync_fifo_fwft #(
           .DATA_WIDTH (AXI_ID_W+PA_W+13), //4 + 48 +13 =65
           .DEPTH (16),
           .AFULL_TH (2)
        ) ar_fifo (
           .clk     (clk),
           .rst_n     (rst_n),
           .wr_en   (a_valid),
           .wr_data ({ar_fifo_idx,8'd0, 3'b111, 2'b01, {ar_addr_temp[PA_W-1:7],7'b0}}),  //ar_id, ar_len, ar_size, ar_burst, ar_addr
           .full    (ar_fifo_full),
           .rd_en   (ar_fifo_rd),
           .rd_data (ar_fifo_rdata),
           .empty   (ar_fifo_empty),
           .almost_full()
        );
        
        /* ================= MSHRs ================= */
    
        reg              m_valid    [0:MSHR_N-1];   //y
        reg [2:0]        m_state    [0:MSHR_N-1];   //y
        reg [VA_W-1:0]   m_va        [0:MSHR_N-1];  //y
        reg [ASID_W-1:0] m_asid      [0:MSHR_N-1];  //y
        reg [47:0]       m_table_pa  [0:MSHR_N-1];  //y
        reg [1023:0]     m_last_pte  [0:MSHR_N-1];
        reg              m_r         [0:MSHR_N-1];   // need to remove
        reg              m_w         [0:MSHR_N-1];   //y
        //reg              m_x         [0:MSHR_N-1];   // need to remove
        reg [1:0]        m_level     [0:MSHR_N-1];   //y
        reg [8:0]        m_index     [0:MSHR_N-1];   //y
        reg [511:0]      m_leaf_ppn  [0:MSHR_N-1];  //made 16
        reg [1:0]        m_ps        [0:MSHR_N-1];
        reg [15:0]       m_perm_r    [0:MSHR_N-1];
        reg [15:0]       m_perm_w    [0:MSHR_N-1];
        reg [15:0]       m_perm_x    [0:MSHR_N-1];
        reg [15:0]       m_perm_d    [0:MSHR_N-1];
       //reg              m_req_id    [0:MSHR_N-1]; //added
        reg [REQ_ID_W-1:0]m_req_id  [0:MSHR_N-1];    //y
        reg [3:0]         m_addr_alloc [0:MSHR_N-1];  //y
        
         /* ================= SATP ARRAY ================= */  //satp comment

    wire [ASID_W-1:0] satp_asid_arr [0:7];   
    wire [PPN_W-1:0]  satp_ppn_arr  [0:7];   
    
    assign satp_asid_arr[0] = satp_entry0[63:32]; 
    assign satp_ppn_arr[0]  = satp_entry0[31:0];  
    
    assign satp_asid_arr[1] = satp_entry1[63:32]; 
    assign satp_ppn_arr[1]  = satp_entry1[31:0];  
    
    assign satp_asid_arr[2] = satp_entry2[63:32];
    assign satp_ppn_arr[2]  = satp_entry2[31:0];
    
    assign satp_asid_arr[3] = satp_entry3[63:32];
    assign satp_ppn_arr[3]  = satp_entry3[31:0];
    
    assign satp_asid_arr[4] = satp_entry4[63:32];
    assign satp_ppn_arr[4]  = satp_entry4[31:0];
    
    assign satp_asid_arr[5] = satp_entry5[63:32];
    assign satp_ppn_arr[5]  = satp_entry5[31:0];
    
    assign satp_asid_arr[6] = satp_entry6[63:32];
    assign satp_ppn_arr[6]  = satp_entry6[31:0];
    
    assign satp_asid_arr[7] = satp_entry7[63:32];
    assign satp_ppn_arr[7]  = satp_entry7[31:0];
    
    /* ================= SATP LOOKUP ================= */  //change

    reg [PPN_W-1:0] satp_ppn_sel;  //change
    reg satp_hit;                  //change

        /* ================= PTW Cache (8-way, non-leaf only) ================= */
    
        reg              cache_valid   [0:7];
        reg [ASID_W-1:0] cache_asid [0:7];
        reg [1:0]        cache_level      [0:7]; 
        reg [8:0]        cache_index		[0:7];
        reg [47:0]       cache_tag_pa [0:7];
        reg [47:0]       cache_next_pa[0:7];
    
       //reg                 asid_flush_req_r ;
       //reg [ASID_W-1:0]    asid_flush_val_r;
        /*===================FLUSH Signals=======================*/
        
        //reg flush_in_prog;
        //reg flush_req_r;
        //reg [ASID_W-1:0] flush_asid_r;
        
        always @(posedge clk or negedge rst_n) begin 
         if(!rst_n) begin
           flush_req_r  <= 0;
           flush_asid_r <= 0;
         end
         else if (invalidate_req) begin 
           flush_req_r  <= 1;
           flush_asid_r <= invalidate_asid;
         end
         else if (!flush_in_prog) begin 
            flush_req_r <= 0;
          end
         end
      
        /* ---------------- Tree PLRU ---------------- */
      /*  reg [6:0] plru_bits;
    
        function [2:0] plru_victim;
            input [6:0] b;
            input [0:7] cache_valid;
            reg free_found;
            integer j;
            begin
            free_found = 0;  //added to verify working of plru_victim
            for (j = 0; j < 8; j = j + 1) begin
            if (!cache_valid[j] && free_found == 0) begin //added
                   free_found = 1;
                    plru_victim = j;
                end
            end
            if(free_found == 0)
             begin
                if (!b[0]) begin
                    if (!b[1]) begin
                        if (!b[3]) plru_victim = 3'd0;
                       else       plru_victim = 3'd1;
                    end else begin
                        if (!b[4]) plru_victim = 3'd2;
                        else       plru_victim = 3'd3;
                    end
                end else begin
                    if (!b[2]) begin
                        if (!b[5]) plru_victim = 3'd4;
                        else       plru_victim = 3'd5;
                    end else begin
                        if (!b[6]) plru_victim = 3'd6;
                        else       plru_victim = 3'd7;
                    end
                end
            end
          end   //added
        endfunction
        */
    //added to fix the packing--unpacking issue before passing the parameter //      
       /* wire [0:7] cache_valid_vec;
        genvar gv;
        generate
            for (gv = 0; gv < 8; gv = gv + 1) begin
                assign cache_valid_vec[gv] = cache_valid[gv];
            end
        endgenerate*/
    /////////////////////////////////////////////////////////////////////////
        
      /*=================== PLRU INSTANTIATION ============================*/ //CHANGE added for plru sep.
    
        wire [2:0] plru_victim_way;
        reg        plru_update_en;
        reg [2:0]  plru_update_way;
        
        wire  dummy_set = 1'd0; // PTW has only 1 "set" (fully associative cache of 8 entries)
        //changed dummy_set from 5 bit to 1 bit
        pseudoLRU #(
            .SETS(1),      // ? single set
            .WAYS(8),
            .SET_BITS(1), 
            .WAY_BITS(3)
        ) u_plru (
            .clk_i(clk),
            .rstn_i(rst_n),
        
            .update_i(plru_update_en),
            .update_set_i(dummy_set),
            .update_way_i(plru_update_way),
        
            .repl_set_i(dummy_set),
            .replacement_way_o(plru_victim_way)
        );
    
    
    
        /* ================= Dispatcher FSM ================= */
    
        reg [2:0] fsm;
        reg [3:0] action;
        //reg [AXI_ID_W-1:0] idx;
    /////////////////////////added////////////////////
        reg [ASID_W-1:0] sel_asid;
        reg [1:0]        sel_level;
        reg [8:0]        sel_index;
        reg [47:0]       sel_table_pa;
    //////////////////////////////////////////////////
        integer i,j;
        reg found; //added
        reg cache_hit;
        reg [2:0] cache_hit_way;
        reg [47:0] cache_hit_next;
        integer victim;
        integer k;
        reg found_invalid;
        reg [63:0] selected_pte;
        reg [63:0] pte_k[0:15];
        //reg [7:0] base;
         //genvar g;
       // reg [PA_W-1:0]ar_addr_temp;
        //reg a_valid;
        
        /* ================= SATP LOOKUP ================= */  //satp comment
    
    reg [ASID_W-1:0] req_asid_local;
    
    always @(*) begin
        satp_ppn_sel = 0;
        satp_hit = 0;
    
        req_asid_local = req_fifo_rdata[VA_W+ASID_W-1:VA_W];
    
        for (k = 0; k < 8; k = k + 1) begin
            if (!satp_hit && satp_asid_arr[k] == req_asid_local) begin
                satp_ppn_sel = satp_ppn_arr[k];
                satp_hit = 1;
            end
        end 
    end 
        /*==================AXI Request Scheduler===================*/
        always @(posedge clk or negedge rst_n)
         begin
           if(!rst_n)
             begin
             ar_valid    <= 1'b0;
             ar_fifo_rd  <= 1'b0;
             ar_addr     <= {PA_W{1'b0}};
             ar_id       <= {AXI_ID_W{1'b0}};
             ar_len      <= 8'd0;
             ar_size     <= 3'd0;
            ar_burst    <= 2'd0;
         end
        else
         begin
           ar_fifo_rd <= 1'b0;

        //--------------------------------------------------
        // Load next request from FIFO
        //--------------------------------------------------

          if(!ar_valid && !ar_fifo_empty && !ar_fifo_rd)
          begin

              ar_valid <= 1;

              ar_fifo_rd <= 1'b1;

              ar_addr  <= ar_fifo_rdata[PA_W-1:0];

              ar_burst <= ar_fifo_rdata[PA_W+1:PA_W];

              ar_size  <= ar_fifo_rdata[PA_W+4:PA_W+2];

              ar_len   <= ar_fifo_rdata[PA_W+12:PA_W+5];

              ar_id    <= ar_fifo_rdata[AXI_ID_W+PA_W+12:PA_W+13];

          end

        //--------------------------------------------------
        // AXI Handshake
        //--------------------------------------------------

           if(ar_valid && ar_ready)
           begin

             //ar_fifo_rd <= 1'b1;

             ar_valid   <= 1'b0;

            end

          end
        end


        /* ================= Main sequential logic ================= */
    
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                fsm <= FSM_IDLE;
                resp_valid <= 16'd0;
                //ar_valid <= 0;
                a_valid <=0;
                aw_valid <= 0;
                w_valid  <= 0;
                req_fifo_rd = 0;
                r_fifo_rd = 0;
                b_fifo_rd = 0;
                ar_fifo_rd = 0;
                plru_update_en <= 0;   //CHANGE added for plru sep.
                //plru_bits <= 7'b0;
                sel_asid <= 0;
                sel_level <= 0;
                sel_index <= 0;
                sel_table_pa <= 0;
                found	<= 0;
                flush_in_prog <= 0;
                for (i=0;i<MSHR_N;i=i+1) begin
                    m_valid[i] <= 0;
                    m_state[i] <= M_IDLE;
                end
                for (i=0;i<8;i=i+1)
                    cache_valid[i] <= 0;
            end else begin
                resp_valid <= 16'd0;
                //ar_valid <= 0;
                a_valid <=0;
                aw_valid <= 0;
                w_valid  <= 0;
                req_fifo_rd = 0;
                r_fifo_rd = 0;
                b_fifo_rd = 0;
                //ar_fifo_rd =0;
            plru_update_en <= 0;   //CHANGE added for plru sep.
                case (fsm)
                    FSM_IDLE: fsm <= FSM_DISPATCH;
    
                    FSM_DISPATCH: begin
                        action <= ACT_NONE;
                        m_addr_alloc[idx][3:0] = ar_addr_temp[6:3];
                         if (flush_req_r) begin     // CHANGE added for invalid asid
                            fsm <= FSM_INVALIDATE;
                        end
                        if (!b_fifo_empty) 
                         begin
                          action <= ACT_HANDLE_B; 
                          idx <= b_fifo_rdata[AXI_ID_W+2:3];
                          b_fifo_rd = 1;
                          fsm <= FSM_ADVANCE;
                    end	
                        else if (!r_fifo_empty) 
                        begin
                         /*r_fifo_rdata_64 = m_addr_alloc[idx] ? {r_fifo_rdata[AXI_ID_W+127:128], r_fifo_rdata[127:64]} :
                                                                      { r_fifo_rdata[AXI_ID_W+127:128],r_fifo_rdata[63:0]};*/ 
                          case(m_addr_alloc[r_fifo_rdata[AXI_ID_W+1023:1024]][3:0])
                             
                              4'd0:  selected_pte = r_fifo_rdata[63:0];
                              4'd1:  selected_pte = r_fifo_rdata[127:64];
                              4'd2:  selected_pte = r_fifo_rdata[191:128];
                              4'd3:  selected_pte = r_fifo_rdata[255:192];
                              4'd4:  selected_pte = r_fifo_rdata[319:256];
                              4'd5:  selected_pte = r_fifo_rdata[383:320];
                              4'd6:  selected_pte = r_fifo_rdata[447:384];
                              4'd7:  selected_pte = r_fifo_rdata[511:448];
                              4'd8:  selected_pte = r_fifo_rdata[575:512];
                              4'd9:  selected_pte = r_fifo_rdata[639:576];
                              4'd10: selected_pte = r_fifo_rdata[703:640];
                              4'd11: selected_pte = r_fifo_rdata[767:704];
                              4'd12: selected_pte = r_fifo_rdata[831:768];
                              4'd13: selected_pte = r_fifo_rdata[895:832];
                              4'd14: selected_pte = r_fifo_rdata[959:896];
                              4'd15: selected_pte = r_fifo_rdata[1023:960];
                              default: selected_pte = 64'b0;
                           endcase
                          r_fifo_rdata_64 = {r_fifo_rdata[AXI_ID_W+1023:1024],selected_pte};                    
                          action <= ACT_HANDLE_R;
                          r_fifo_rd = 1;
                          idx <= r_fifo_rdata[AXI_ID_W+1023:1024];
                          fsm <= FSM_ADVANCE;
                         end
                        else if (!req_fifo_empty)
                         begin
                           //for (i=0;i<MSHR_N;i=i+1) begin //added
                          for (i=(MSHR_N-1);i>=0;i=i-1) begin //added
                           if (!m_valid[i]) begin
                             action <= ACT_ALLOC; 
                             idx <= i;
                             req_fifo_rd = 1;
                             fsm <= FSM_ADVANCE;	//dont advance if no free MSHR
                        end
                    end //added
                 end
                else begin
                   fsm <= FSM_SCAN_MSHR;
                end
                    end
                            
            FSM_SCAN_MSHR: begin
                found = 0;
                for (i=0;i<MSHR_N;i=i+1) begin
                    //if (!found && m_valid[i]) begin
                   if (!found && m_valid[i] && m_state[i] != M_WAIT_R && m_state[i] != M_WAIT_B) begin /*exclude entries waiting for R and B responses as they have already*/
                   found = 1;
                   idx <= i;
                   fsm <= FSM_EVAL_MSHR;
                end
            end
     
            if (!found)
               fsm <= FSM_DISPATCH;
            end
            
                   FSM_EVAL_MSHR: begin
               if (m_state[idx]==M_DONE || (m_state[idx]==M_FAULT)) begin
                  action <= ACT_RETIRE;
                  fsm <= FSM_ADVANCE;
               end
            else if (m_state[idx]==M_NEED_AW) begin
                action <= ACT_ISSUE_AW;
                fsm <= FSM_ADVANCE;
                        end
                        else if (m_state[idx]==M_IDLE) begin
                            sel_asid     <= m_asid[idx];
                            sel_level    <= m_level[idx];
                            sel_index    <= m_index[idx];
                            sel_table_pa <= m_table_pa[idx];
                            fsm		 <= FSM_CHECK_CACHE;
                        end
                        else begin						
                            fsm <= FSM_DISPATCH;
                        end
                    end
                    
                    FSM_CHECK_CACHE: begin
                        cache_hit = 0;
                        for (j=0;j<8;j=j+1) begin
                            if (!cache_hit &&
                                cache_valid[j] &&
                                cache_asid[j]  == sel_asid &&
                                cache_level[j] == sel_level &&
                                cache_index[j] == sel_index &&
                                cache_tag_pa[j]== sel_table_pa) begin
                                cache_hit      = 1;
                                cache_hit_way  = j[2:0];
                                cache_hit_next = cache_next_pa[j];
                            end
                        end
                        action <= cache_hit ? ACT_CACHE_NEXT : ACT_AR;
                        fsm <= FSM_ADVANCE;
                    end
                    FSM_INVALIDATE: begin                       //CHANGE  added for asid invalid 
                        flush_in_prog <= 1;
                        ar_valid <= 0;
                        aw_valid <= 0;
                        w_valid  <= 0;
                        for (j = 0; j < 8; j = j + 1) begin    //Flush PTW Cache
                            if (cache_valid[j] && cache_asid[j] == flush_asid_r) begin
                                cache_valid[j] <= 0;
                            end
                        end
                        //Flush MSHR entries
                        for (j = 0; j < MSHR_N; j = j + 1) begin
                            if (m_valid[j] && m_asid[j] == flush_asid_r)
                                m_valid[j] <= 0;
                            end
    
                        resp_valid <= 16'd0;
                        flush_in_prog <= 0;
                        fsm <= FSM_DISPATCH;
                    end
    
                    FSM_ADVANCE: begin
                        case (action)
                            ACT_ALLOC: begin
                                m_req_id[idx] <= req_fifo_rdata[VA_W+ASID_W+REQ_ID_W+1:VA_W+ASID_W];
                                m_valid[idx] <= 1;
                                m_state[idx] <= M_IDLE;
                                m_va[idx] <= req_fifo_rdata[VA_W-1:0];
                                m_asid[idx] <= req_fifo_rdata[VA_W+ASID_W-1:VA_W];
                                m_r[idx] <= !req_fifo_rdata[VA_W+ASID_W+1];
                                m_w[idx] <= req_fifo_rdata[VA_W+ASID_W+1];
                                //m_x[idx] <= req_fifo_rdata[VA_W+ASID_W];
                                //m_req_id[idx] <= req_fifo_rdata[VA_W+ASID_W+REQ_ID_W+2:VA_W+ASID_W+3]; //added req_fifo_rdata[84:83]
                                m_level[idx] <= 0;
                                m_index[idx] <= vpn_index(req_fifo_rdata[VA_W-1:0],0);//index for level 0
                                //m_table_pa[idx] <= {satp_ppn,16'b0};//SATP PPN << 16 for 64KB page
                                if (!satp_hit) begin  // satp comment
                                   m_state[idx] <= M_FAULT;   
                                end else begin
                                   m_table_pa[idx] <= {satp_ppn_sel,16'b0};  
                               end
                               for( i=0; i<16;i=i+1) begin 
                                if(m_valid[i])
                                  mshr_used_count = mshr_used_count + 1;
                               end

                            end
    
                            ACT_CACHE_NEXT: begin
                                cache_hit <=0;
                                m_table_pa[idx] <= cache_hit_next;
                                m_index[idx] <= vpn_index(m_va[idx], (m_level[idx] + 1)); //index for next level
                                m_level[idx] <= m_level[idx] + 1;
                                 // plru_update(cache_hit_way);
                                plru_update_en  <= 1; //CHANGE added for plru sep.
                                plru_update_way <= cache_hit_way;   //CHANGE added for plru sep.
    
                            end
    
                            ACT_AR: begin
                              if(!ar_fifo_full ) begin  //&& ar_fifo_empty
                                  //a_valid    <= 1;
                                  //ar_fifo_rd  <=1;
                                  ar_fifo_idx  <= idx;
                                  ar_addr_temp = m_table_pa[idx] + (vpn_index(m_va[idx], m_level[idx]) << 3);
                                  a_valid    <= 1;
                                  m_state[idx] <= M_WAIT_R;
                                // logic 
         //idx,8'd0(len), 3'b111(size), 2'b01(burst), ar_addr_temp    ar_fifo_rdata[4 bits AXI_ID_W + 8 bits + 3 bits + 2 bits + 48 PA_W = 65 bits]
                                /*if (ar_ready && !ar_fifo_empty)
                                  m_state[idx] <= M_WAIT_R;
                                  ar_valid    <= ar_fifo_rd;
                                  ar_addr     <=  {ar_fifo_rdata[PA_W-1:7], 7'b0};					//[47:0]	   
                                  ar_id       <= ar_fifo_rdata[64:61];    //RANGE FOR ID IS [69:PA_W+13] == [AXI_ID_W + PA_W+13 :PA_W+13] 
                                  ar_len      <= ar_fifo_rdata[60:53];    //RANGE FOR LEN IS [60:53]                  // newly added by default given 0 
                                  ar_size     <= ar_fifo_rdata[52:50];   //RANGE FOR SIZE IS[52:50]
                                  ar_burst    <= ar_fifo_rdata[49:48];       //RANGE FOR BURST IS [49:48]             // newly added by default given as INCR(01)
                             end*/
                             end
                           end
                            ACT_HANDLE_R: begin
                              
                               if (m_state[idx]==M_WAIT_R) begin
                                    if (!r_fifo_rdata_64[0]) begin //added
                                        m_state[idx] <= M_FAULT; //Valid bit is zero, so fault.
                                     end //added
                                    else if (r_fifo_rdata_64[1]||
                                             r_fifo_rdata_64[2]||
                                             r_fifo_rdata_64[3]) begin	// one of R/W/X bits set, so this is leaf 
                                         if(m_level[idx] <= 1) begin 
                                          // we are not at leaf yet, but leaf received, so assert fault.
                                             m_state[idx] <= M_FAULT;
                                          end
                                            pte_k[0]  = r_fifo_rdata[63:0];
                                            pte_k[1]  = r_fifo_rdata[127:64];
                                            pte_k[2]  = r_fifo_rdata[191:128];
                                            pte_k[3]  = r_fifo_rdata[255:192];
                                            pte_k[4]  = r_fifo_rdata[319:256];
                                            pte_k[5]  = r_fifo_rdata[383:320];
                                            pte_k[6]  = r_fifo_rdata[447:384];
                                            pte_k[7]  = r_fifo_rdata[511:448];
                                            pte_k[8]  = r_fifo_rdata[575:512];
                                            pte_k[9]  = r_fifo_rdata[639:576];
                                            pte_k[10] = r_fifo_rdata[703:640];
                                            pte_k[11] = r_fifo_rdata[767:704];
                                            pte_k[12] = r_fifo_rdata[831:768];
                                            pte_k[13] = r_fifo_rdata[895:832];
                                            pte_k[14] = r_fifo_rdata[959:896];
                                            pte_k[15] = r_fifo_rdata[1023:960];
    
                                        if (need_d_update(r_fifo_rdata_64[63:0],m_w[idx])) begin	//need D bit update
                                            //m_last_pte[idx] <= r_fifo_rdata_64[63:0];
                                            for (k=0; k < 16; k=k+1) begin 
                                              case(k)
                                               0: m_last_pte[idx][63:0]    <= pte_k[k][63:0];
                                               1: m_last_pte[idx][127:64]  <= pte_k[k][63:0];
                                               2: m_last_pte[idx][191:128] <= pte_k[k][63:0];//[191:128];
                                               3: m_last_pte[idx][255:192] <= pte_k[k][63:0];//[255:192];
                                               4: m_last_pte[idx][319:256] <= pte_k[k][63:0];//[319:256];
                                               5: m_last_pte[idx][383:320] <= pte_k[k][63:0];//[383:320];
                                               6: m_last_pte[idx][447:384] <= pte_k[k][63:0];//[447:384];
                                               7: m_last_pte[idx][511:448] <= pte_k[k][63:0];//[511:448];
                                               8: m_last_pte[idx][575:512] <= pte_k[k][63:0];//[575:512];
                                               9: m_last_pte[idx][639:576] <= pte_k[k][63:0];//[639:576];
                                               10:m_last_pte[idx][703:640] <= pte_k[k][63:0];//[703:640];
                                               11:m_last_pte[idx][767:704] <= pte_k[k][63:0];
                                               12:m_last_pte[idx][831:768] <= pte_k[k][63:0];//[767:704];
                                               13:m_last_pte[idx][895:832] <= pte_k[k][63:0];//[895:832];
                                               14:m_last_pte[idx][959:896] <= pte_k[k][63:0];//[959:896];
                                               15:m_last_pte[idx][1023:960] <= pte_k[k][63:0];//[1023:960];
                                               endcase
                                            end
                                            m_state[idx] <= M_NEED_AW;
                                        end else begin		//no need for D bit update
                                            m_ps[idx] <= detect_page_size(m_level[idx]);
                                           /* m_leaf_ppn[idx] <= mask_ppn(
                                                r_fifo_rdata_64[41:10],
                                                m_va[idx],
                                                detect_page_size(m_level[idx]));
                                            m_perm_r[idx] <= r_fifo_rdata_64[1];
                                            m_perm_w[idx] <= r_fifo_rdata_64[2];
                                            m_perm_x[idx] <= r_fifo_rdata_64[3];
                                            m_perm_d[idx] <= r_fifo_rdata_64[7];
                                            */
                                            //base = idx << 4;
                                            //sample = mask_ppn(pte_k[0][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                           // ---- PTE 0 ----
                                          m_leaf_ppn[idx][31:0] <= mask_ppn(pte_k[0][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][0]  <= pte_k[0][1];
                                          m_perm_w[idx][0]  <= pte_k[0][2];
                                          m_perm_x[idx][0]  <= pte_k[0][3];
                                          m_perm_d[idx][0]  <= pte_k[0][7];
    
                                          // ---- PTE 1 ----
                                          m_leaf_ppn[idx][63:32] <= mask_ppn(pte_k[1][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][1]  <= pte_k[1][1];
                                          m_perm_w[idx][1]  <= pte_k[1][2]; 
                                          m_perm_x[idx][1]  <= pte_k[1][3];
                                          m_perm_d[idx][1]  <= pte_k[1][7];
    
                                          // ---- PTE 2 ----
                                          m_leaf_ppn[idx][95:64] <= mask_ppn(pte_k[2][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][2]  <= pte_k[2][1];
                                          m_perm_w[idx][2]  <= pte_k[2][2];
                                          m_perm_x[idx][2]  <= pte_k[2][3];
                                          m_perm_d[idx][2]  <= pte_k[2][7];
    
                                         // ---- PTE 3 ----
                                          m_leaf_ppn[idx][127:96] <= mask_ppn(pte_k[3][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][3]  <= pte_k[3][1];
                                          m_perm_w[idx][3]  <= pte_k[3][2];
                                          m_perm_x[idx][3]  <= pte_k[3][3];
                                          m_perm_d[idx][3]  <= pte_k[3][7];
     
                                          // ---- PTE 4 ----
                                          m_leaf_ppn[idx][159:128] <= mask_ppn(pte_k[4][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][4]  <= pte_k[4][1];
                                          m_perm_w[idx][4]  <= pte_k[4][2];
                                          m_perm_x[idx][4]  <= pte_k[4][3];
                                          m_perm_d[idx][4]  <= pte_k[4][7];
    
                                          // ---- PTE 5 ----
                                          m_leaf_ppn[idx][191:160] <= mask_ppn(pte_k[5][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][5]  <= pte_k[5][1];
                                          m_perm_w[idx][5]  <= pte_k[5][2];
                                          m_perm_x[idx][5]  <= pte_k[5][3];
                                          m_perm_d[idx][5]  <= pte_k[5][7];
    
                                          // ---- PTE 6 ----
                                          m_leaf_ppn[idx][223:192] <= mask_ppn(pte_k[6][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][6]  <= pte_k[6][1];
                                          m_perm_w[idx][6]  <= pte_k[6][2];
                                          m_perm_x[idx][6]  <= pte_k[6][3];
                                          m_perm_d[idx][6]  <= pte_k[6][7];
    
                                           // ---- PTE 7 ----
                                          m_leaf_ppn[idx][255:224] <= mask_ppn(pte_k[7][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][7]  <= pte_k[7][1];
                                          m_perm_w[idx][7]  <= pte_k[7][2];
                                          m_perm_x[idx][7]  <= pte_k[7][3];
                                          m_perm_d[idx][7]  <= pte_k[7][7];
    
                                         // ---- PTE 8 ----
                                         m_leaf_ppn[idx][287:256] <= mask_ppn(pte_k[8][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                         m_perm_r[idx][8]  <= pte_k[8][1];
                                         m_perm_w[idx][8]  <= pte_k[8][2];
                                         m_perm_x[idx][8]  <= pte_k[8][3];
                                         m_perm_d[idx][8]  <= pte_k[8][7];
    
                                         // ---- PTE 9 ----
                                         m_leaf_ppn[idx][319:288] <= mask_ppn(pte_k[9][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                         m_perm_r[idx][9]  <= pte_k[9][1];
                                         m_perm_w[idx][9]  <= pte_k[9][2];
                                         m_perm_x[idx][9]  <= pte_k[9][3];
                                         m_perm_d[idx][9]  <= pte_k[9][7];
    
                                         // ---- PTE 10 ----
                                         m_leaf_ppn[idx][351:320] <= mask_ppn(pte_k[10][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                         m_perm_r[idx][10]  <= pte_k[10][1];
                                         m_perm_w[idx][10]  <= pte_k[10][2];
                                         m_perm_x[idx][10]  <= pte_k[10][3];
                                         m_perm_d[idx][10]  <= pte_k[10][7];
    
                                         // ---- PTE 11 ----
                                         m_leaf_ppn[idx][383:352] <= mask_ppn(pte_k[11][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                         m_perm_r[idx][11]  <= pte_k[11][1];
                                         m_perm_w[idx][11]  <= pte_k[11][2];
                                         m_perm_x[idx][11]  <= pte_k[11][3];
                                         m_perm_d[idx][11]  <= pte_k[11][7];
    
                                         // ---- PTE 12 ----
                                         m_leaf_ppn[idx][415:384] <= mask_ppn(pte_k[12][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                         m_perm_r[idx][12]  <= pte_k[12][1];
                                         m_perm_w[idx][12]  <= pte_k[12][2];
                                         m_perm_x[idx][12]  <= pte_k[12][3];
                                         m_perm_d[idx][12]  <= pte_k[12][7];
    
                                         // ---- PTE 13 ----
                                         m_leaf_ppn[idx][447:416] <= mask_ppn(pte_k[13][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                         m_perm_r[idx][13]  <= pte_k[13][1];
                                         m_perm_w[idx][13]  <= pte_k[13][2];
                                         m_perm_x[idx][13]  <= pte_k[13][3];
                                         m_perm_d[idx][13]  <= pte_k[13][7];
    
                                         // ---- PTE 14 ----
                                         m_leaf_ppn[idx][479:448] <= mask_ppn(pte_k[14][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                         m_perm_r[idx][14]  <= pte_k[14][1];
                                         m_perm_w[idx][14]  <= pte_k[14][2];
                                         m_perm_x[idx][14]  <= pte_k[14][3]; 
                                         m_perm_d[idx][14]  <= pte_k[14][7];
    
                                          // ---- PTE 15 ----
                                          m_leaf_ppn[idx][511:480] <= mask_ppn(pte_k[15][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                          m_perm_r[idx][15]  <= pte_k[15][1];
                                          m_perm_w[idx][15]  <= pte_k[15][2];
                                          m_perm_x[idx][15]  <= pte_k[15][3];
                                          m_perm_d[idx][15]  <= pte_k[15][7];
    
                                          m_state[idx] <= M_DONE;
                                        end
                                    end else begin //not leaf, continue traversing but update cache
                                        if(m_level[idx] == 3) begin
                                        m_state[idx] <= M_FAULT; //already at last level and no leaf still
                                        end //added
                                        else begin //begin added	
                                             m_state[idx] <= M_IDLE;
                                       end
                                         m_index[idx] <= vpn_index(m_va[idx], (m_level[idx]+1)); //index for next level ,added by me for 3VA case   
                                         victim = plru_victim_way;           //CHANGE added for sep. plru
                                        // INVALID-FIRST override           //CHANGE added for sep.plru
                                        found_invalid = 0;
                                       // victim = plru_victim_way;
                                        for (j = 0; j < 8; j = j + 1) begin
                                            if (!found_invalid && !cache_valid[j]) begin
                                                victim = j;
                                                found_invalid = 1;
                                            end
                                        end
    
                                        cache_index[victim]     <= m_index[idx];
                                        cache_valid[victim]		<= 1;
                                        cache_level[victim]		<= m_level[idx];  
                                        cache_asid[victim]		<= m_asid[idx];
                                        cache_tag_pa[victim]	<= m_table_pa[idx];
                                        cache_next_pa[victim] <=
                                            {r_fifo_rdata_64[41:10],16'b0};           //made 16 from 12
                                        //plru_update(victim);
                                        plru_update_en  <= 1;    //CHANGE added for plru sep.
                                        plru_update_way <= victim;   //CHANGE added for plru sep.
                                        m_table_pa[idx] <=
                                            {r_fifo_rdata_64[41:10],16'b0};
                                        m_level[idx] <= m_level[idx] + 1;
                                        /*if(m_level[idx] == 3) begin
                                        m_state[idx] <= M_FAULT; //already at last level and no leaf still
                                        end //added
                                        else begin //begin added	
                                             m_state[idx] <= M_IDLE;
                                       end*/
                                    end
                                end else begin //begin added
                                    m_state[idx] <= M_FAULT;
                                end //added
                            end
    
                            ACT_ISSUE_AW: begin
                                aw_valid <= 1;
                                aw_len   <=8'd0;
                                aw_size  <=3'b111;
                                aw_burst <= 2'b01;
                                w_valid  <= 1;
                                aw_addr <= m_table_pa[idx] + (vpn_index(m_va[idx], m_level[idx]) << 3);							   
                                aw_id   <= idx;
                                for (k=0;k<16;k=k+1)
                                w_data  <= m_last_pte[idx] | (64'h1<<((k*64)+7));//Set D bit alone which is bit 7 in PTE
                                if (aw_ready && w_ready)
                                    m_state[idx] <= M_WAIT_B;
                            end
    
                            ACT_HANDLE_B: begin
                                if (m_state[idx]==M_WAIT_B) begin
                                  if(b_fifo_rdata[2:0] == 3'b000) begin 
                                    m_ps[idx] <= detect_page_size(m_level[idx]);
                                    m_leaf_ppn[idx][31:0]  <= mask_ppn(m_last_pte[idx][41:10], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][63:32] <= mask_ppn(m_last_pte[idx][105:74], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][95:64] <= mask_ppn(m_last_pte[idx][169:138], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][127:96]<= mask_ppn(m_last_pte[idx][233:202], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][159:128]  <= mask_ppn(m_last_pte[idx][297:266], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][191:160]  <= mask_ppn(m_last_pte[idx][361:330], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][223:192]  <= mask_ppn(m_last_pte[idx][425:394], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][255:224]  <= mask_ppn(m_last_pte[idx][489:458], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][287:256]  <= mask_ppn(m_last_pte[idx][553:522], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][319:288]  <= mask_ppn(m_last_pte[idx][617:586], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][351:320]  <= mask_ppn(m_last_pte[idx][681:650], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][383:352]  <= mask_ppn(m_last_pte[idx][745:714], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][415:384]  <= mask_ppn(m_last_pte[idx][809:778], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][447:416]  <= mask_ppn(m_last_pte[idx][873:842], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][479:448]  <= mask_ppn(m_last_pte[idx][937:906], m_va[idx], detect_page_size(m_level[idx]));
                                    m_leaf_ppn[idx][511:480]  <= mask_ppn(m_last_pte[idx][1001:970], m_va[idx], detect_page_size(m_level[idx]));
                                    //m_perm_r[idx] <= m_last_pte[idx][1*i];
                                    for(k=0;k<16;k=k+1)
                                     begin
                                      m_perm_r[idx][k] <= m_last_pte[idx][(k*64)+1];
                                      m_perm_w[idx][k] <= m_last_pte[idx][(k*64)+2];
                                      m_perm_x[idx][k] <= m_last_pte[idx][(k*64)+3];
                                      m_perm_d[idx][k] <= m_last_pte[idx][(k*64)+7];
                                    end
                                    m_state[idx] <= M_DONE;
                                  end else
                                    m_state[idx] <= M_FAULT;
                               end else
                                    m_state[idx] <= M_FAULT;
                             end   
    
                            ACT_RETIRE: begin
                                if(resp_ready) begin 
                                resp_valid <= 16'd1;
                                if(m_state[idx]==M_FAULT) begin resp_fault <=1; end
                                else begin resp_fault <=0; end
                                //resp_fault <= 0;
                                resp_ppn <= m_leaf_ppn[idx];
                                resp_page_size <= m_ps[idx];
                                resp_asid <= m_asid[idx];
                                resp_perms[47:32] <= m_perm_r[idx];
                                resp_perms[31:16] <= m_perm_w[idx];
                                resp_perms[15:0] <= m_perm_x[idx];
                                resp_perm_d <= m_perm_d[idx];
                                resp_req_id <= m_req_id[idx]; //added
                                m_valid[idx] <= 0;
                                r_fifo_rdata_64 <=64'd0;
                               end
                            end
                        endcase
                        fsm <= FSM_DISPATCH;
                         
                    end
                endcase
            end
        end
      
    
    
    /*==========COUNTERS=================*/
    
    ////////////////////////////////////
    //L2 interface
    ///////////////////////////////////
    
    wire      [31:0]l2_rd_req_cnt;
    wire      [31:0]l2_wr_req_cnt;
    wire      [31:0]l2_rd_rsp_cnt;
    wire      [31:0]l2_wr_rsp_cnt;
    wire      l2_rd_req_cnt_overflow;
    wire      l2_wr_req_cnt_overflow;
    wire      l2_rd_rsp_cnt_overflow;
    wire      l2_wr_rsp_cnt_overflow;
    
    ////////////////////////////////////
    //cache interface
    ///////////////////////////////////
    
    //wire [CNT_WIDTH-1:0]cache_rd_hit_cnt;
    wire [CNT_W-1:0]cache_rd_hit_cnt;
    wire [CNT_W-1:0]cache_wr_hit_cnt;
    wire [CNT_W-1:0]cache_rd_miss_cnt;
    wire [CNT_W-1:0]cache_wr_miss_cnt;
    wire cache_rd_hit_cnt_overflow;
    wire cache_wr_hit_cnt_overflow;
    wire cache_rd_miss_cnt_overflow;
    wire cache_wr_miss_cnt_overflow;
    
    ////////////////////////////////////
    //axi interface
    ///////////////////////////////////
    
    wire      [31:0]axi_rd_req_cnt;
    wire      [31:0]axi_wr_req_cnt;
    wire      [31:0]axi_rd_rsp_cnt;
    wire      [31:0]axi_wr_rsp_cnt;
    wire      axi_rd_req_cnt_overflow;
    wire      axi_wr_req_cnt_overflow;
    wire      axi_rd_rsp_cnt_overflow;
    wire      axi_wr_rsp_cnt_overflow;
    
    //L2 interface counter 
    
    ptw_counter #(.CNT_W (32)) u_l2_rd_req_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (req_valid && !req_w),
          .cnt          (l2_rd_req_cnt),
          .cnt_overflow (l2_rd_req_cnt_overflow)
        );
    
     ptw_counter #(.CNT_W (32)) u_l2_wr_req_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (req_valid && req_w),
          .cnt          (l2_wr_req_cnt),
          .cnt_overflow (l2_wr_req_cnt_overflow)
        ); 
     ptw_counter #(.CNT_W (32)) u_l2_rd_rsp_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (resp_valid && resp_perms[47:32]),
          .cnt          (l2_rd_rsp_cnt),
          .cnt_overflow (l2_rd_rsp_cnt_overflow)
        ); 
      ptw_counter #(.CNT_W (32)) u_l2_wr_rsp_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (resp_valid && resp_perms[31:16]),
          .cnt          (l2_wr_rsp_cnt),
          .cnt_overflow (l2_wr_rsp_cnt_overflow)
        );
    
    ///////////////////////////////
    //cache hit/miss count
    //////////////////////////////
    
      ptw_counter #(.CNT_W (CNT_W)) u_cache_rd_hit_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (cache_hit && !req_w),
          .cnt          (cache_rd_hit_cnt),
          .cnt_overflow (cache_rd_hit_cnt_overflow)
        );
     
     ptw_counter #(.CNT_W (CNT_W)) u_cache_wr_hit_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      ((fsm == FSM_CHECK_CACHE) && cache_hit && req_w),
          .cnt          (cache_wr_hit_cnt),
          .cnt_overflow (cache_wr_hit_cnt_overflow)
        );
    
     ptw_counter #(.CNT_W (CNT_W)) u_cache_rd_miss_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (ar_valid && !cache_hit && !req_w),
          .cnt          (cache_rd_miss_cnt),
          .cnt_overflow (cache_rd_miss_cnt_overflow)
        );
    
     ptw_counter #(.CNT_W (CNT_W)) u_cache_wr_miss_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (!cache_hit && req_w),
          .cnt          (cache_wr_miss_cnt),
          .cnt_overflow (cache_wr_miss_cnt_overflow)
        );
     ///////////////////////////////////
     // AXI Interface
     //////////////////////////////////
    
     ptw_counter #(.CNT_W (32)) u_axi_rd_req_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (ar_valid && !req_w),
          .cnt          (axi_rd_req_cnt),
          .cnt_overflow (axi_rd_req_cnt_overflow)
        );
     ptw_counter #(.CNT_W (32)) u_axi_wr_req_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (ar_valid && req_w),
          .cnt          (axi_wr_req_cnt),
          .cnt_overflow (axi_wr_req_cnt_overflow)
        );
     ptw_counter #(.CNT_W (32)) u_axi_rd_rsp_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (r_valid && !req_w),
          .cnt          (axi_rd_rsp_cnt),
          .cnt_overflow (axi_rd_rsp_cnt_overflow)
        );
     ptw_counter #(.CNT_W (32)) u_axi_wr_rsp_cnt (
          .clk          (clk),
          .rst_n        (rst_n),
          .cnt_inc      (r_valid && req_w),
          .cnt          (axi_wr_rsp_cnt),
          .cnt_overflow (axi_wr_rsp_cnt_overflow)
        );
    
        assign l2_rd_req_cnt_o = l2_rd_req_cnt;
        assign l2_wr_req_cnt_o = l2_wr_req_cnt; 
        assign l2_rd_rsp_cnt_o = l2_rd_rsp_cnt;
        assign l2_wr_rsp_cnt_o = l2_wr_rsp_cnt;
        assign l2_rd_req_cnt_overflow_o = l2_rd_req_cnt_overflow;
        assign l2_wr_req_cnt_overflow_o = l2_wr_req_cnt_overflow;
        assign l2_rd_rsp_cnt_overflow_o = l2_rd_rsp_cnt_overflow;
        assign l2_wr_rsp_cnt_overflow_o = l2_wr_rsp_cnt_overflow;
    
        assign cache_rd_hit_cnt_o  = cache_rd_hit_cnt;
        assign cache_wr_hit_cnt_o  = cache_wr_hit_cnt;
        assign cache_rd_miss_cnt_o = cache_rd_miss_cnt;
        assign cache_wr_miss_cnt_o = cache_wr_miss_cnt;
        assign cache_rd_hit_cnt_overflow_o  = cache_rd_hit_cnt_overflow;
        assign cache_wr_hit_cnt_overflow_o  = cache_wr_hit_cnt_overflow;
        assign cache_rd_miss_cnt_overflow_o = cache_rd_miss_cnt_overflow;
        assign cache_wr_miss_cnt_overflow_o = cache_wr_miss_cnt_overflow;
    
        assign axi_rd_req_cnt_o = axi_rd_req_cnt;
        assign axi_wr_req_cnt_o = axi_wr_req_cnt;
        assign axi_rd_rsp_cnt_o = axi_rd_rsp_cnt;
        assign axi_wr_rsp_cnt_o = axi_wr_rsp_cnt;
        assign axi_rd_req_cnt_overflow_o = axi_rd_req_cnt_overflow;
        assign axi_wr_req_cnt_overflow_o = axi_wr_req_cnt_overflow;
        assign axi_rd_rsp_cnt_overflow_o = axi_rd_rsp_cnt_overflow;
        assign axi_wr_rsp_cnt_overflow_o = axi_wr_rsp_cnt_overflow;
    endmodule
    



