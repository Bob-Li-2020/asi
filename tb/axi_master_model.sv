module automatic axi_master_model import axi_pkg::*, asi_pkg::*;
(
    //---- AXI GLOBAL SIGNALS ----------------
    input  logic                    ACLK     ,
    input  logic                    ARESETn  ,
    //---- AXI ADDRESS WRITE SIGNALS ---------
    output logic [AXI_IW-1     : 0] AWID     ,
    output logic [AXI_AW-1     : 0] AWADDR   ,
    output logic [AXI_LW-1     : 0] AWLEN    ,
    output logic [AXI_SW-1     : 0] AWSIZE   ,
    output logic [AXI_BURSTW-1 : 0] AWBURST  ,
    output logic                    AWVALID  ,
    input  logic                    AWREADY  ,
    output logic [3            : 0] AWCACHE  , // NO LOADS
    output logic [2            : 0] AWPROT   , // NO LOADS
    output logic [3            : 0] AWQOS    , // NO LOADS
    output logic [3            : 0] AWREGION , // NO LOADS
    //---- AXI DATA WRITE SIGNALS ------------
    output logic [AXI_DW-1     : 0] WDATA    ,
    output logic [AXI_WSTRBW-1 : 0] WSTRB    ,
    output logic                    WLAST    ,
    output logic                    WVALID   ,
    input  logic                    WREADY   ,
    //---- AXI WRITE RESPONSE SIGNALS --------
    input  logic [AXI_IW-1     : 0] BID      ,
    input  logic [AXI_BRESPW-1  : 0] BRESP    ,
    input  logic                    BVALID   ,
    output logic                    BREADY   ,
    //---- READ ADDRESS CHANNEL --------------
    output logic [AXI_IW-1     : 0] ARID     ,
    output logic [AXI_AW-1     : 0] ARADDR   ,
    output logic [AXI_LW-1     : 0] ARLEN    ,
    output logic [AXI_SW-1     : 0] ARSIZE   ,
    output logic [AXI_BURSTW-1 : 0] ARBURST  ,
    output logic                    ARVALID  ,
    input  logic                    ARREADY  ,
    output logic [3            : 0] ARCACHE  , // NO LOADS 
    output logic [2            : 0] ARPROT   , // NO LOADS 
    output logic [3            : 0] ARQOS    , // NO LOADS 
    output logic [3            : 0] ARREGION , // NO LOADS
    //---- READ DATA CHANNEL -----------------
    input  logic [AXI_IW-1     : 0] RID      ,
    input  logic [AXI_DW-1     : 0] RDATA    ,
    input  logic [AXI_RRESPW-1  : 0] RRESP    ,
    input  logic                    RLAST    ,
    input  logic                    RVALID   ,
    output logic                    RREADY    
);
timeprecision 1ps;
timeunit 1ns;

//---------- DEBUG PARAMETERS ----------
localparam VERBOSE = 0;
//---------- TEST PARAMETERS -----------
localparam BREADY_PERCENTAGE=50, 
           RREADY_PERCENTAGE=10; 
localparam RAN_DATA = 1; // RANDOM WDATA ENABLE
localparam OUTSTANDING_EN = 0; 
localparam AWW_RANDOM_DELAY_MAX = 4; // MAX DELAY BETWEEN AW/W CHANNEL
//---------- ALL DONE EVENT ------------
event all_done;
//--------------------------------------------//
//------------- EASY SIGNALS -----------------//
//--------------------------------------------//
wire clk = ACLK;
wire rst_n = ARESETn;
typedef class XTransactions;
typedef class AWmonitor;
typedef class Wmonitor;
typedef class ARmonitor;
typedef class Rmonitor;
class Driver; // outstanding driver
    //------------------------------------------//
    //--------------- ATTRIBUTES ---------------//
    //------------------------------------------//
    Wtransactions wt_queue[$]; // write transaction outstanding queue
    Rtransactions rt_queue[$]; // read  transaction outstanding queue
    mailbox mbx_aw; // AW CHANNEL mailbox
    mailbox mbx_w;  // W  CHANNEL mailbox
    mailbox mbx_b;  // B  CHANNEL mailbox
    mailbox mbx_r;  // R  CHANNEL mailbox
    mailbox mbx_aw_out, mbx_w_out;
    rand int qsize; // queue size. [1, SLV_OD]. min value 1; max value SLV_OD(slave outstanding depth)
    AWmonitor awm_queue[$];
    Wmonitor   wm_queue[$];
    ARmonitor arm_queue[$];
    Rmonitor   rm_queue[$];
    int total_transfer_number; 
    static int transaction_n; // outstanding transaction number. 1 outstanding transaction consists of <q_size> transactions
    event check_r_done; // check RDATA/WDATA done for all transfers of the outstanding transactions. finish all tasks after this occurs.
    event drive_aw_starts;
    event drive_w_starts;
    //------------------------------------------//
    //--------------- CONSTRAINTS --------------//
    //------------------------------------------//
    constraint c1_qn { qsize>=1; qsize<=(OUTSTANDING_EN ? SLV_OD : 1); }
    //------------------------------------------//
    //--------------- NEW FUNCTION -------------//
    //------------------------------------------//
    function new;
        mbx_aw = new;
        mbx_w  = new;
        mbx_b  = new;
        mbx_r  = new;
        mbx_aw_out=  new;
        mbx_w_out=  new;
        total_transfer_number = 0;
        transaction_n++;
    endfunction
    //------------------------------------------//
    //--------------- CALCULATE N --------------//
    //------------------------------------------//
    function void calc_n;
        int awlen;
        int arlen;
        assert(wt_queue.size==rt_queue.size);
        foreach(wt_queue[i]) begin
            awlen = wt_queue[i].AWLEN;
            arlen = rt_queue[i].ARLEN;
            assert(awlen==arlen);
            total_transfer_number += (awlen+1);
        end
        $display("transaction %0d(counting from 1): total_transfer_number = %0d", transaction_n, total_transfer_number);
    endfunction
    //------------------------------------------//
    //--------------- POST RANDOMIZE -----------//
    //------------------------------------------//
    function void post_randomize;
        fill_queue;
        calc_n;
    endfunction
    //------------------------------------------//
    //--------------- FILL QUEUE ---------------//
    //------------------------------------------//
    function void fill_queue; // fill wt_queue and rt_queue
        XTransactions xt; // a pair of write/read transactions
        for(int i=0;i<qsize;i++) begin
            xt = new;
            assert(xt.randomize) else begin
                $error("%0t: XTransactions randomize failed", $realtime);
                $finish;
            end
            wt_queue.push_back(xt.wt);
            rt_queue.push_back(xt.rt);
        end
        $display("%0t: Driver.fill_queue success with %0d/%0d transaction pairs", $realtime, wt_queue.size, rt_queue.size);
    endfunction
    //------------------------------------------//
    //--------------- GEN MAILBOX --------------//
    //------------------------------------------//
    task gen_mbx_aww; // fill mbx_aw and mbx_w
        foreach(wt_queue[i]) begin
            mbx_aw.put(wt_queue[i]);
            mbx_w.put(wt_queue[i]);
        end
    endtask
    task gen_mbx_ar;
        Wtransactions wt;
        logic [AXI_IW-1 : 0] mbx_bid; // mail from mailbox mbx_b
        foreach(rt_queue[i]) begin
            //mbx_b.get(mbx_bid); // waiting for a write response
            mbx_r.put(rt_queue[i]); // put new request in mbx_r
        end
    endtask
    //------------------------------------------//
    //--------------- TRANSACTION TASKS --------//
    //------------------------------------------//
    task drive_aw(ref mailbox mbx); // drive AW CHANNEL of a write transaction <wt>
        static int n;
        Wtransactions wt;
        int random_delay; // random delay before actually drive AW CHANNEL of the transaction
        random_delay = $urandom_range(0,AWW_RANDOM_DELAY_MAX); 
        mbx.get(wt);
        repeat(random_delay) @(posedge clk);
        $display("%0t: AW CHANNEL %0d STARTS:", $realtime, n);
        wt.show_aw;
        mbx_aw_out.put(wt);
        AWID     = wt.AWID    ;
        AWADDR   = wt.AWADDR  ;
        AWLEN    = wt.AWLEN   ;
        AWSIZE   = wt.AWSIZE  ;
        AWBURST  = wt.AWBURST ;
        AWCACHE  = wt.AWCACHE ; // NO LOADS
        AWPROT   = wt.AWPROT  ; // NO LOADS
        AWQOS    = wt.AWQOS   ; // NO LOADS
        AWREGION = wt.AWREGION; // NO LOADS
        AWVALID  = 1'b1      ; // extending handshake
        do begin 
            @(posedge clk);     // waiting for handshake accepting
        end while(~AWREADY); 
        AWVALID = #0 1'b0;
        $display("%0t: AW CHANNEL %0d FINISHES", $realtime, n);
        n++;
    endtask
    task drive_w(ref mailbox mbx); // drive  W  CHANNEL of a write transaction <wt>
        static int n;
        Wtransactions wt;
        int random_delay; // random delay before actually drive W CHANNEL of the transaction
        random_delay = $urandom_range(0,AWW_RANDOM_DELAY_MAX); 
        mbx.get(wt);
        repeat(random_delay) @(posedge clk);
        $display("%0t: W  CHANNEL %0d STARTS. %0d TRANSFERS IN TOTAL.", $realtime, n, wt.WDATA.size);
        mbx_w_out.put(wt);
        foreach(wt.WDATA[i]) begin
            WDATA = #0 wt.WDATA[i];
            WSTRB = #0 wt.WSTRB[i];
            if(wt.WDATA.size==i+1)
                WLAST = #0 1'b1;
            else
                WLAST = #0 1'b0;
            WVALID   = #0 1'b1;  // extending handshake
            do begin
                @(posedge clk);
            end while(~WREADY); 
            if(VERBOSE) begin
                $display("%0t: i = %0d; WDATA = %h", $realtime, i, WDATA);
                $display("%0t: i = %0d; WSTRB = %b", $realtime, i, WSTRB);
            end
        end
        WVALID = #0 1'b0;
        $display("%0t: W  CHANNEL %0d FINISHES", $realtime, n);
        n++;
    endtask
    task drive_ar(ref mailbox mbx); // drive AR CHANNEL of a read  transaction <rt>
        static int n;
        static int aw_n;
        static int w_n;
        Wtransactions wt;
        Rtransactions rt;
        mbx.get(rt);
        mbx_aw_out.get(wt);$display("^^^^^^^^^^ %0t: get aw_out mail %0d", $realtime, aw_n++);
        mbx_w_out.get(wt);$display("^^^^^^^^^^ %0t: get w_out mail %0d", $realtime, w_n++);
        $display("%0t: AR CHANNEL %0d STARTS:", $realtime, n);
        rt.show_ar;
        ARID     = rt.ARID     ;
        ARADDR   = rt.ARADDR   ;
        ARLEN    = rt.ARLEN    ;
        ARSIZE   = rt.ARSIZE   ;
        ARBURST  = rt.ARBURST  ;
        ARCACHE  = rt.ARCACHE  ; // NO LOADS 
        ARPROT   = rt.ARPROT   ; // NO LOADS 
        ARQOS    = rt.ARQOS    ; // NO LOADS 
        ARREGION = rt.ARREGION ; // NO LOADS
        ARVALID  = 1'b1   ;
        do begin
            @(posedge clk);
        end while(~ARREADY); // extending handshake
        ARVALID  = #0 1'b0   ;
        $display("%0t: AR CHANNEL %0d FINISHES", $realtime, n);
        n++;
    endtask
    task check_b(ref mailbox mbx); // check B CHANNEL(BID AGAINST AWID)
        int n; // number of received BRESP, when reaches qsize, break
        logic [AXI_IW-1:0] awid;
        $display("%0t: B CHANNEL MONITORING STARTS", $realtime);
        while(1) begin
            @(posedge clk);
            //$display("%0t: waiting for B CHANNEL HANDSHAKE", $realtime);
            if(BREADY & BVALID) begin
                //-- 1. CHECK "BID" AGAINST "AWID"
                assert(awm_queue.size) else begin $error("%0t: Received BRESP, however, awm_queue.size==%0d", $realtime, awm_queue.size); $finish; end
                awid = awm_queue.pop_front().AWID;
                assert(awid==BID) else begin $error("%0t: BID(%h) AWID(%h) MISMATCH!", $realtime, BID, awid); $finish; end
                //-- 2. PUT "BID" INTO MAILBOX, FOR <drive_ar>
                assert(BRESP==BRESP_OKAY) else begin $error("%0t: Received NOT SUPPORTED BRESP %h", $realtime, BRESP); $finish; end
                $display("%0t: RECEIVED BID   = %h", $realtime, BID);
                $display("%0t: RECEIVED BRESP = %h", $realtime, BRESP);
                mbx.put(BID);
                n++;
                if(n==qsize) begin
                    $display("%0t: B CHANNEL FINISHES. RECEIVED %0d BRESPS IN TOTAL.", $realtime, n);
                    break;
                end
            end
        end
    endtask
    task check_r; // check R CHANNEL
        int n;
        Rmonitor rm;
        Wmonitor wm;
        ARmonitor arm;
        bit check_result;
        while(1) begin
            if(rm_queue.size) begin
                rm = rm_queue.pop_front;
                assert(wm_queue.size && arm_queue.size) else begin $error("%0t: rm.size=%0d , however, wm.size=%0d, arm.size=%0d", $realtime, rm_queue.size, wm_queue.size, arm_queue.size); $finish; end
                wm = wm_queue.pop_front;
                //-- 1. CHECK RID/ARID
                if(rm.RLAST) begin
                    arm = arm_queue.pop_front;
                    assert(rm.RID==arm.ARID) else begin
                        $error("%0t: RID/ARID ERROR:", $realtime);
                        $error("RID=%h", rm.RID);
                        $error("ARID=%h", arm.ARID);
                        $finish;
                    end
                    $display("%0t: RECEIVED RID=%h; RLAST=%0d", $realtime, rm.RID, rm.RLAST);
                end
                //-- 2. CHECK RDATA/WDATA
                check_result = check_against(rm.RDATA, wm.WDATA, wm.WSTRB); // 0~OK; 1~ERROR
                assert(check_result==0) else begin 
                    $error("%0t: RDATA/WDATA ERROR:", $realtime);
                    $error("%0d: RDATA = %h",n, rm.RDATA);
                    $error("%0d: WDATA = %h",n, wm.WDATA);
                    $error("%0d: WSTRB = %b",n, wm.WSTRB);
                    $finish;
                end
                $display("%0d: RDATA = %h",n, rm.RDATA);
                $display("%0d: WDATA = %h",n, wm.WDATA);
                $display("%0d: WSTRB = %b",n, wm.WSTRB);
                n++;
                if(n==total_transfer_number) begin
                    -> check_r_done;
                    $display("%0t: CHECK PASS %0d RDATA/WDATA", $realtime, n);
                    $display("%0t: R CHANNEL FINISHES", $realtime);
                    $display("^^^^^^^^^%0t: rm.size = %0d", $realtime, rm_queue.size);
                    break;
                end
            end
            @(posedge clk);
        end
    endtask
    task monitor_r; // monitor R CHANNEL
        static int n;
        Rmonitor rm;
        fork 
            begin: MONITOR_RCHANNEL
                do begin
                    if(RVALID & RREADY) begin
                        rm = new;
                        rm.RID    = RID     ;
                        rm.RDATA  = RDATA   ;
                        rm.RRESP  = RRESP   ;
                        rm.RLAST  = RLAST   ;
                        rm_queue.push_back(rm);
                        $display("^^^^^^^^^^%0t: put rm %0d into rm_queue. now rm.size=%0d", $realtime, n, rm_queue.size);
                        n++;
                    end
                    @(posedge clk);
                        $display("%%%%%%%%%%%0t: put rm %0d into rm_queue. now rm.size=%0d", $realtime, n, rm_queue.size);
                end while(1);
            end: MONITOR_RCHANNEL
            begin: AWAITS_CHECK_DONE
                @(check_r_done);
            end
        join_any
        wait fork;
    endtask
    task monitor_aw; // monitor AW CHANNEL
        AWmonitor awm;
        fork
            begin
                do begin
                    @(posedge clk);
                    if(AWVALID & AWREADY) begin 
                        awm = new;
                        awm.AWID     = AWID    ;
                        awm.AWADDR   = AWADDR  ;
                        awm.AWLEN    = AWLEN   ;
                        awm.AWSIZE   = AWSIZE  ;
                        awm.AWBURST  = AWBURST ;
                        awm_queue.push_back(awm);
                    end
                end while(1);
            end
            begin
                @(check_r_done);
            end
        join_any
    endtask
    task monitor_w; // monitor W CHANNEL
        Wmonitor wm;
        fork
            begin
                do begin
                    if(WVALID & WREADY) begin
                        wm = new;
                        wm.WDATA = WDATA; 
                        wm.WSTRB = WSTRB;
                        wm.WLAST = WLAST;
                        wm_queue.push_back(wm);
                    end
                    @(posedge clk);
                end while(1);
            end
            begin
                $display("%0t: ########## monitor_w captured check_r_done", $realtime);
                @(check_r_done);
            end
        join_any
    endtask
    task monitor_ar; // monitor AR CHANNEL
        ARmonitor arm;
        fork
            begin
                do begin
                    if(ARVALID & ARREADY) begin
                        arm = new;
                        arm.ARID     = ARID    ;
                        arm.ARADDR   = ARADDR  ;
                        arm.ARLEN    = ARLEN   ;
                        arm.ARSIZE   = ARSIZE  ;
                        arm.ARBURST  = ARBURST ;
                        arm_queue.push_back(arm);
                    end
                    @(posedge clk);
                end while(1);
            end
            begin
                @(check_r_done);
            end
        join_any
    endtask
    task run; // run all
        fork 
            //------ generators -----//
            gen_mbx_aww;
            gen_mbx_ar;
            //------ drivers -------//
            drive_aw(mbx_aw);
            drive_w(mbx_w);
            drive_ar(mbx_r);
            //------ monitors -----//
            monitor_r;
            monitor_aw;
            monitor_w;
            monitor_ar;
            //------ monitors -----//
            check_b(mbx_b);
            check_r;
        join
        $display("%0t: ####################### TRANSACTION %0d CHECK SUCCESS!\n", $realtime, transaction_n);
    endtask
endclass: Driver

class XTransactions; 
    //------------------------------------------//
    //--------------- ATTRIBUTES ---------------//
    //------------------------------------------//
    Wtransactions wt;
    Rtransactions rt;
    rand logic [SLV_AW-1     : 0] SLV_AXADDR  ; // start address
    logic      [AXI_AW-1     : 0] AXADDR      ;
    rand logic [AXI_LW-1     : 0] AXLEN       ;
    rand logic [AXI_SW-1     : 0] AXSIZE      ;
    //------------------------------------------//
    //--------------- CONSTRAINTS --------------//
    //------------------------------------------//
    constraint c1_narrow { if(!NARROW_EN) SLV_AXADDR%(2**AXSIZE) == 0; } // narrow transfer constraint
    constraint c2_len  { AXLEN<=AXI_MAXLEN; } // transfer len constraint
    constraint c3_size {  // transfer size constraint
        if(RAN_SIZE) 
            AXSIZE<=$clog2(AXI_BYTES);
        else 
            AXSIZE==$clog2(AXI_BYTES); 
    }
    constraint c4_order {
        solve AXSIZE before SLV_AXADDR;
    }
    //------------------------------------------//
    //--------------- SHOW AW ------------------//
    //------------------------------------------//
    function void show_aw;
        $display(" SLV_AXADDR = 0x%h", AXADDR);
        $display(" AXADDR     = 0x%h", AXADDR);
        $display(" AXLEN      = %0d", AXLEN);
        $display(" AXSIZE     = %0d", AXSIZE);
    endfunction
    //------------------------------------------//
    //--------------- POST RANDOMIZE -----------//
    //------------------------------------------//
    function void post_randomize;
        AXADDR = {'0, SLV_AXADDR};
        gen_wt;
        gen_rt;
    endfunction: post_randomize
    //------------------------------------------//
    //--------------- GEN WTRANSACTION ---------//
    //------------------------------------------//
    function void gen_wt;
        wt = new(.RAN_DATA(RAN_DATA));
        assert( wt.randomize with { AWADDR==AXADDR; AWLEN==AXLEN; AWSIZE==AXSIZE; } ) else begin
            $error("%0t: Wtransaction randomize failed with info: ", $realtime);
            show_aw;
            $finish;
        end
    endfunction
    //------------------------------------------//
    //--------------- GEN RTRANSACTION ---------//
    //------------------------------------------//
    function void gen_rt;
        rt = new;
        assert( rt.randomize with { ARADDR==AXADDR; ARLEN==AXLEN; ARSIZE==AXSIZE; } ) else begin
            $error("%0t: Rtransaction randomize failed with info: ", $realtime);
            show_aw;
            $finish;
        end
    endfunction
endclass: XTransactions

class AWmonitor; // AW CHANNEL monitor
    logic [AXI_IW-1     : 0] AWID     ;
    logic [AXI_AW-1     : 0] AWADDR   ;
    logic [AXI_LW-1     : 0] AWLEN    ;
    logic [AXI_SW-1     : 0] AWSIZE   ;
    logic [AXI_BURSTW-1 : 0] AWBURST  ;
endclass: AWmonitor
class Wmonitor; // W CHANNEL monitor
    logic [AXI_DW-1     : 0] WDATA;
    logic [AXI_WSTRBW-1 : 0] WSTRB;
    logic                    WLAST;
endclass: Wmonitor
class ARmonitor; // AR CHANNEL monitor
    logic [AXI_IW-1     : 0] ARID     ;
    logic [AXI_AW-1     : 0] ARADDR   ;
    logic [AXI_LW-1     : 0] ARLEN    ;
    logic [AXI_SW-1     : 0] ARSIZE   ;
    logic [AXI_BURSTW-1 : 0] ARBURST  ;
endclass: ARmonitor
class Rmonitor; // R CHANNEL monitor
    logic [AXI_IW-1     : 0] RID  ;
    logic [AXI_DW-1     : 0] RDATA;
    logic [AXI_RRESPW-1  : 0] RRESP;
    logic                    RLAST;
endclass: Rmonitor

function int check_against(
    input logic [AXI_DW-1:0] rdata, wdata, 
    input logic [AXI_BYTES-1:0] wstrb
);
//------ check rdata againtst wdata, if match return 0----//
    for(int i=0;i<AXI_BYTES;i++) begin
        assert(!($isunknown(wstrb[i])));
        if(wstrb[i]===1'b1) begin
            if(rdata[i*8 +: 8] !== wdata[i*8 +: 8])
                return 1;
            else begin
                //$display("%0t: rdata = %h", $realtime, rdata);
                //$display("%0t: wdata = %h", $realtime, wdata);
                //$display("%0t: wstrb = %b", $realtime, wstrb);
                //$stop;
            end
        end
    end
    return 0;
endfunction

function void show_driver_info;
    $display("################# DRIVER FEATURES #############");
    $display("BREADY_PERCENTAGE=%0d", BREADY_PERCENTAGE); 
    $display("RREADY_PERCENTAGE=%0d", RREADY_PERCENTAGE); 
    $display("RAN_DATA         =%0d", RAN_DATA); 
    $display("OUTSTANDING_EN   =%0d", OUTSTANDING_EN); 
    $display;
endfunction

//--------------------------------------------//
//------------- READY CONTROL ----------------//
//--------------------------------------------//
always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        BREADY <= 1'b1;
        RREADY <= 1'b1;
    end else begin
        BREADY <= ($urandom_range(0,99) < BREADY_PERCENTAGE);
        RREADY <= ($urandom_range(0,99) < RREADY_PERCENTAGE);
    end
end
initial begin
    show_driver_info;
    AWVALID=1'b0;
    WVALID=1'b0;
    WLAST=1'b0;
    ARVALID=1'b0;
    //BREADY=1'b1;
    //RREADY=1'b1;
end

initial begin
    Driver drv;
    wait(ARESETn);
    for(int i=0;i<10000;i++) begin
        drv = new;
        assert(drv.randomize) else begin
            $display("%0t: Driver drv randomize failed", $realtime);
            $finish;
        end
        drv.run;
    end
    -> all_done;
end

initial begin
    @(all_done);
    $display("%0t: ######## ALL DONE! ###########",$realtime);
    $stop;
end

endmodule
