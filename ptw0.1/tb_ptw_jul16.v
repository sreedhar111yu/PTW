//tb_ptw_n
 
// 
 

`timescale 1ns/1ps
module tb_ptw;
parameter VA_W=48;
parameter PA_W=48;
parameter PPN_W=32;
parameter ASID_W=32;
parameter AXI_ID_W=4;
parameter REQ_ID_W=2;
/////////////////////////////////////////
// CLOCK
/////////////////////////////////////////
reg clk;
//always #5 clk = ~clk;
reg rst_n;
/////////////////////////////////////////
// REQUEST
/////////////////////////////////////////
reg req_valid;
reg [VA_W-1:0] req_va;
reg [ASID_W-1:0] satp_asid;
reg [REQ_ID_W-1:0] req_id;
reg req_w;
wire req_ready;
/////////////////////////////////////////
// RESPONSE
/////////////////////////////////////////
localparam RESP_W = 16;
 
reg resp_ready;
 
wire [RESP_W-1:0] resp_valid;
 
wire              resp_fault;
 
wire [511:0]      resp_ppn;
 
wire [1:0]        resp_page_size;
wire [31:0]       resp_asid;
wire [47:0] resp_perms;
wire [RESP_W-1:0] resp_perm_d;
 
wire [REQ_ID_W-1:0] resp_req_id;
///////////////////////////////////////
//AR
/////////////////////////////////////
 
wire [47:0]        ar_addr;
wire [7:0]         ar_len;
wire [2:0]         ar_size;
wire [1:0]         ar_burst;
 
 
// AW
wire               aw_valid;
wire [47:0]        aw_addr;
wire [AXI_ID_W-1:0] aw_id;
wire [7:0] aw_len;
wire [2:0] aw_size;
wire [1:0] aw_burst;
// W
wire               w_valid;
wire [1023:0]        w_data;
 
 
// B
reg                b_valid;
reg [AXI_ID_W-1:0] b_id;
reg [2:0]          b_resp;
 
// FLUSH
reg                invalidate_req;
reg [31:0]         invalidate_asid;
 
//reg                asid_flush_req;
//reg [31:0]         asid_flush_val;
 
/////////////////////////////////////////
// AXI
/////////////////////////////////////////
wire ar_valid;
wire [AXI_ID_W-1:0] ar_id;
reg ar_ready;
reg r_valid;
reg [1023:0] r_data;
reg [AXI_ID_W-1:0] r_id;
 
reg pending;
reg [AXI_ID_W-1:0] saved_id;
reg [47:0] saved_addr;
reg d_updated;
/////////////////////////////////////////
// DUT
/////////////////////////////////////////
ptw_n dut(
 
.clk(clk),
.rst_n(rst_n),
 

.satp_entry0({32'd1,32'h8000}),
.satp_entry1({32'd2,32'h8001}),
.satp_entry2({32'd3,32'h8000}),
.satp_entry3(64'd0),
.satp_entry4(64'd0),
.satp_entry5(64'd0),
.satp_entry6(64'd0),
.satp_entry7(64'd0),

 
.req_valid(req_valid),
.req_va(req_va),
.req_asid(satp_asid),
.req_id(req_id),
.req_w(req_w),
.req_ready(req_ready),
 
.resp_ready(resp_ready),
.resp_valid(resp_valid),
.resp_fault(resp_fault),
.resp_ppn(resp_ppn),
.resp_page_size(resp_page_size),
.resp_asid(resp_asid),
.resp_perm_d(resp_perm_d),
.resp_req_id(resp_req_id),
.resp_perms(resp_perms),
 
.ar_valid(ar_valid),
.ar_addr(ar_addr),
.ar_len(ar_len),
.ar_size(ar_size),
.ar_burst(ar_burst),
.ar_id(ar_id),
.ar_ready(ar_ready),
 
.r_valid(r_valid),
.r_data(r_data),
.r_id(r_id),
 
.aw_valid(aw_valid),
.aw_addr(aw_addr),
.aw_id(aw_id),
.aw_ready(1'b1),
.aw_len(aw_len),
.aw_size(aw_size),
.aw_burst(aw_burst),
 
.w_valid(w_valid),
.w_data(w_data),
.w_ready(1'b1),
 
.b_valid(b_valid),
.b_id(b_id),
.b_resp(b_resp),
 
.invalidate_req(invalidate_req),
.invalidate_asid(invalidate_asid),
 
//.asid_flush_req(asid_flush_req),
//.asid_flush_val(asid_flush_val),
 
.l2_rd_req_cnt_o(),
.l2_wr_req_cnt_o(),
.l2_rd_rsp_cnt_o(),
.l2_wr_rsp_cnt_o(),
.l2_rd_req_cnt_overflow_o(),
.l2_wr_req_cnt_overflow_o(),
.l2_rd_rsp_cnt_overflow_o(),
.l2_wr_rsp_cnt_overflow_o(),
 
.cache_rd_hit_cnt_o(),
.cache_wr_hit_cnt_o(),
.cache_rd_miss_cnt_o(),
.cache_wr_miss_cnt_o(),
.cache_rd_hit_cnt_overflow_o(),
.cache_wr_hit_cnt_overflow_o(),
.cache_rd_miss_cnt_overflow_o(),
.cache_wr_miss_cnt_overflow_o(),
 
.axi_rd_req_cnt_o(),
.axi_wr_req_cnt_o(),
.axi_rd_rsp_cnt_o(),
.axi_wr_rsp_cnt_o(),
.axi_rd_req_cnt_overflow_o(),
.axi_wr_req_cnt_overflow_o(),
.axi_rd_rsp_cnt_overflow_o(),
.axi_wr_rsp_cnt_overflow_o()
 
);
 
initial begin
		clk=1'b0;
		forever #5 clk=~clk;
	end
 
 
 
typedef struct packed {
 
    bit [21:0] reserved;
    bit [31:0] ppn;
    bit [1:0]  rsv;
 
    bit d;
    bit a;
    bit g;
    bit u;
 
    bit x;
    bit w;
    bit r;
    bit v;
 
} pte_t;
 
pte_t pt_mem [bit [63:0]];
bit [31:0] next_ppn = 32'h1000;
 
task automatic get_ppn(
    output bit [31:0] ppn
);
begin
 
    ppn = next_ppn;
 
    next_ppn=next_ppn+32'h1000;
 
end
endtask
 
function automatic bit [63:0]
calc_pte_addr(
    input bit [31:0] base_ppn,
    input int unsigned vpn
);
begin
 
    return ({base_ppn} << 16)
           + (vpn << 3);
 
end
endfunction
 
function automatic pte_t
make_nonleaf_pte(
    input bit [31:0] next_level_ppn
);
 
    pte_t pte;
 
begin
 
    pte = '0;
 
    pte.ppn = next_level_ppn;
 
    pte.v = 1'b1;
 
    return pte;
 
end
endfunction
 
function automatic pte_t
make_leaf_pte(
    input bit [31:0] final_ppn
);
 
    pte_t pte;
 
begin
 
    pte = '0;
 
    pte.ppn = final_ppn;
 
    pte.v = 1'b1;
    pte.r = 1'b1;
    pte.w = 1'b1;
    pte.x = 1'b1;
    pte.d = 1'b1;
 
    return pte;
 
end
endfunction


function automatic pte_t
make_leaf_pte_d0(
    input bit [31:0] final_ppn
);

    pte_t pte;

begin

    pte = '0;

    pte.ppn = final_ppn;

    pte.v = 1'b1;
    pte.r = 1'b1;
    pte.w = 1'b1;
    pte.x = 1'b1;

    pte.d = 1'b0;

    return pte;

end
endfunction

 
task automatic create_translation(
 
    input bit [47:0] va,
    input bit [31:0] satp_ppn,
    input bit [31:0] final_ppn,
 
    input int leaf_level
 
);
 
    bit [8:0] vpn3;
    bit [8:0] vpn2;
    bit [8:0] vpn1;
    bit [4:0] vpn0;
 
    bit [31:0] ppn_l3;
    bit [31:0] ppn_l2;
    bit [31:0] ppn_l1;
 
    bit [63:0] addr_l3;
    bit [63:0] addr_l2;
    bit [63:0] addr_l1;
    bit [63:0] addr_l0;
 
begin
 
    //----------------------------------
    // VPN split
    //----------------------------------
 
    vpn3 = va[47:39];
    vpn2 = va[38:30];
    vpn1 = va[29:21];
    vpn0 = va[20:16];
 
    //----------------------------------
    // allocate next level ppns
    //----------------------------------
 
    get_ppn(ppn_l3);
    get_ppn(ppn_l2);
    get_ppn(ppn_l1);
 
    //----------------------------------
    // L3
    //----------------------------------
 
    addr_l3 =
        calc_pte_addr(
            satp_ppn,
            vpn3
        );
 
    pt_mem[addr_l3] =
        make_nonleaf_pte(ppn_l3);
 
    //----------------------------------
    // L2
    //----------------------------------
 
    addr_l2 =
        calc_pte_addr(
            ppn_l3,
            vpn2
        );
 
    if(leaf_level == 2)
    begin
 
        pt_mem[addr_l2] =
            make_leaf_pte(final_ppn);
 
        return;
 
    end
 
    pt_mem[addr_l2] =
        make_nonleaf_pte(ppn_l2);
 
    //----------------------------------
    // L1
    //----------------------------------
 
    addr_l1 =
        calc_pte_addr(
            ppn_l2,
            vpn1
        );
 
    if(leaf_level == 1)
    begin
 
        pt_mem[addr_l1] =
            make_leaf_pte(final_ppn);
 
        return;
 
    end
 
    pt_mem[addr_l1] =
        make_nonleaf_pte(ppn_l1);
 
    //----------------------------------
    // L0
    //----------------------------------
 
    addr_l0 =
        calc_pte_addr(
            ppn_l1,
            vpn0
        );
 
    pt_mem[addr_l0] =
        make_leaf_pte(final_ppn);
 
end
endtask


task automatic create_translation_d0(

    input bit [47:0] va,
    input bit [31:0] satp_ppn,
    input bit [31:0] final_ppn

);

    bit [8:0] vpn3;
    bit [8:0] vpn2;
    bit [8:0] vpn1;
    bit [4:0] vpn0;

    bit [31:0] ppn_l3;
    bit [31:0] ppn_l2;
    bit [31:0] ppn_l1;

    bit [63:0] addr_l3;
    bit [63:0] addr_l2;
    bit [63:0] addr_l1;
    bit [63:0] addr_l0;

begin

    vpn3 = va[47:39];
    vpn2 = va[38:30];
    vpn1 = va[29:21];
    vpn0 = va[20:16];

    get_ppn(ppn_l3);
    get_ppn(ppn_l2);
    get_ppn(ppn_l1);

    addr_l3 = calc_pte_addr(satp_ppn,vpn3);
    addr_l2 = calc_pte_addr(ppn_l3,vpn2);
    addr_l1 = calc_pte_addr(ppn_l2,vpn1);
    addr_l0 = calc_pte_addr(ppn_l1,vpn0);

    pt_mem[addr_l3] = make_nonleaf_pte(ppn_l3);
    pt_mem[addr_l2] = make_nonleaf_pte(ppn_l2);
    pt_mem[addr_l1] = make_nonleaf_pte(ppn_l1);

    pt_mem[addr_l0] = make_leaf_pte_d0(final_ppn);

end

endtask

 
 
//////////////////////////////////////////////////////axi_channels///////////////////////////////////////////////////
typedef struct {
 
    bit [47:0]         addr;
    bit [AXI_ID_W-1:0] id;
 
} ar_req_t;
 
ar_req_t ar_q[$];
 
always @(posedge clk or negedge rst_n)
begin
    ar_req_t req;
 
    if(!rst_n)
    begin
        ar_q.delete();
    end
    else
    begin
        if(ar_valid && ar_ready)
        begin
            req.addr = ar_addr;
            req.id   = ar_id;
 
            ar_q.push_back(req);
/*
            $display(
                "[%0t] AR addr=%h id=%0d",
                $time,
                ar_addr,
                ar_id
            );*/
        end
    end
end
/*
function automatic bit [1023:0]
create_rdata_16pte(
 
    input pte_t pte
 
);
 
    bit [1023:0] data;
    int i;
 
begin
 
    data = '0;
 
    for(i=0;i<16;i++)
    begin
        data[i*64 +: 64] = pte;
    end
 
    return data;
 
end
 
endfunction
*/
function automatic bit [1023:0]
create_rdata_16pte(
 
    input bit [47:0] ar_addr
 
);
 
    bit [1023:0] data;
    bit [47:0] line_addr;
    int i;
 
begin
 
    data = '0;
 
data[0]   = 1; data[64]  = 1; data[128] = 1; data[192] = 1; data[256] = 1; data[320] = 1; data[384] = 1; 
data[448] = 1; data[512] = 1; data[576] = 1; data[640] = 1; data[704] = 1; data[768] = 1; data[832] = 1; 
data[896] = 1; data[960] = 1;
 
    //----------------------------------
    // 128B align
    //----------------------------------
 
    line_addr = {ar_addr[47:7],7'b0};
 
    //----------------------------------
    // Fill cache line
    //----------------------------------
 
    for(i=0;i<16;i++)
    begin
 
        if(pt_mem.exists(line_addr + (i*8)))
        begin
            data[i*64 +: 64]
                = pt_mem[line_addr + (i*8)];
		//$display("%p",pt_mem[line_addr + (i*8)]);
 
$display(
        "PTE[%0d] addr=%h value=%h",
        i,
        line_addr + (i*8),
        pt_mem[line_addr + (i*8)]
    );
        end
  /*     else
        begin
            data[i*64 +: 64]
                = 64'd0;
       end
     */ 
    end
 
$display("-------- RDATA LINE --------");
    for(i=0;i<16;i++)
    begin
        if(data[i*64 +: 64] != 0)
        begin
            $display(
                "PTE[%0d] = %h",
                i,
                data[i*64 +: 64]
            );
        end
    end
    $display("----------------------------");
 
    return data;
 
end
 
endfunction
 
always @(posedge clk or negedge rst_n)
begin
 
    ar_req_t req;
 
    if(!rst_n)
    begin
        r_valid <= 0;
        r_data  <= 0;
        r_id    <= 0;
    end
    else
    begin
 
        r_valid <= 0;
 
        if(ar_q.size() > 0)
        begin
 
            req = ar_q.pop_front();
 
            r_valid <= 1;
            r_id    <= req.id;
 
         //   if(pt_mem.exists(req.addr))
         //   begin
 
         //       r_data <= create_rdata_16pte(pt_mem[req.addr]);
		r_data <= create_rdata_16pte(req.addr);
                $display(
                    "[%0t] R addr=%h ppn=%h",
                    $time,
                    req.addr,
                    pt_mem[req.addr].ppn
                );
          //  end
/*            else
            begin
 
                $display(
                    "[TB ERROR] No PTE for addr=%h",
                    req.addr
                );
 
                r_data <= '0;
 
            end
*/
        end
 
    end
 
end


always @(posedge clk)
begin

    b_valid <= 0;

    if(aw_valid && w_valid)
    begin

        b_valid <= 1;
        b_id    <= aw_id;
        b_resp  <= 3'b000;

        $display(
            "[%0t] B RESP ID=%0d",
            $time,
            aw_id
        );

    end

end


always @(posedge clk)
begin

    if(ar_valid)
    begin
        $display(
        "[%0t] AR addr=%h id=%0d",
        $time,
        ar_addr,
        ar_id
        );
    end

    if(r_valid)
    begin
        $display(
        "[%0t] R id=%0d",
        $time,
        r_id
        );
    end

    if(aw_valid)
    begin
        $display(
        "[%0t] AW addr=%h id=%0d",
        $time,
        aw_addr,
        aw_id
        );
    end

    if(w_valid)
    begin
        $display(
        "[%0t] W VALID",
        $time
        );
    end

    if(b_valid)
    begin
        $display(
        "[%0t] B id=%0d",
        $time,
        b_id
        );
    end

    if(resp_valid != 16'd0)
    begin
        $display(
        "[%0t] RESP_VALID=%h FAULT=%0d PPN=%h D=%h RESP perms R=%h W=%h X=%h",
        $time,
        resp_valid,
        resp_fault,
        resp_ppn,
        resp_perm_d,
        resp_perms[47:32],
        resp_perms[31:16],
        resp_perms[15:0]

        );
    end
    if(aw_valid)
begin
    $display(
    "[%0t] AW addr=%h id=%0d len=%0d size=%0d burst=%0d",
    $time,
    aw_addr,
    aw_id,
    aw_len,
    aw_size,
    aw_burst
    );
end

end

// AW Moniter

always @(posedge clk)

begin

   if(w_valid)

   begin

      $display("-------- WDATA LINE --------");

      for(int i=0;i<16;i++)

      begin

         $display(

            "PTE[%0d] = %016h D=%0d",

            i,

            w_data[i*64 +: 64],

            w_data[(i*64)+7]

         );

      end

      $display("----------------------------");

   end

end
 
 

//////////////////////////
// SEND TASK
///////////////////////
 
task send_read;
 
input [47:0] va;
input [31:0] asid;
input [1:0]  id;
 
begin
 
    @(posedge clk);
 
    while(!req_ready)
        @(posedge clk);
 
    req_valid <= 1;
 
    req_va    <= va;
    satp_asid <= asid;
    req_id    <= id;
 
    
    req_w <= 0;
    
 
    @(posedge clk);
 
    req_valid <= 0;
 
    
    req_w <= 0;
    
 
end
 
endtask


task send_write;

input [47:0] va;
input [31:0] asid;
input [1:0]  id;

begin

    @(posedge clk);

    while(!req_ready)
        @(posedge clk);

    req_valid <= 1;

    req_va    <= va;
    satp_asid <= asid;
    req_id    <= id;

    
    req_w <= 1;
    

    @(posedge clk);

    req_valid <= 0;

    
    req_w <= 0;
    

end

endtask

 
initial begin
//	   clk = 0;
   rst_n = 0;
 
   req_valid = 0;
   req_va    = 0;
   satp_asid = 0;
   req_id    = 0;
 
   
   req_w = 0;
   
 
   resp_ready = 1;
 
   ar_ready = 1;
 
   r_valid = 0;
   r_data  = 0;
   r_id    = 0;
   
   
    b_valid = 0;
    b_id    = 0;
    b_resp  = 0;

 
//  rsp_cnt = 0  ar_cnt = 0;
//  r_cnt  = 0;
 
   repeat(10) @(posedge clk);
 
   rst_n = 1;
 
   @(posedge clk);
 

$display("====================================");
$display("1KB WRITE TEST");
$display("====================================");

create_translation_d0(
    48'h0000_1234_1000,
    32'h8000,
    32'hDEAD_BEEF
);

send_write(
    48'h0000_1234_1000,
    32'd1,
    0
);

wait(resp_valid != 0);

if(!resp_fault)
    $display("PASS : WRITE COMPLETED");
else
    $display("FAIL : WRITE FAULT");

#500;
$finish;

end
 
endmodule
