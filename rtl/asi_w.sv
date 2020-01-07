//-- AUTHOR: LIBING
//-- DATE: 2019.12
//-- DESCRIPTION: AXI SLAVE INTERFACE.WRITE. BASED ON AXI4 SPEC.
//----------------------SUPPORTED FEATURES: 
//----------------------                         1) OUTSTANDING TRANSACTIONS; 
//----------------------                         2) NARROW TRANSFERS; 
//----------------------                         3) UNALIGNED TRANSFERS.
//----------------------NOT SUPPORTED FEATURES: 
//----------------------                         1) OUT-OF-ORDER TRANSACTIONS; 
//----------------------                         2) INTERLEAVING TRANSFERS;
//----------------------                         3) WRAP TRANSFERS.
//----------------------BRESP:
//----------------------        2'b00: OKAY;
//----------------------        2'b01: EXOKAY. NOT supported;
//----------------------        2'b10: SLVERR; 
//----------------------        2'b00: DECERR. NOT supported.

// asi_w: Axi Slave Interface Write
module asi_w //import asi_pkg::*;
#(
    //--- AXI BIT WIDTHs 
    AXI_DW     = 128                 , // AXI DATA    BUS WIDTH
    AXI_AW     = 40                  , // AXI ADDRESS BUS WIDTH
    AXI_IW     = 8                   , // AXI ID TAG  BITS WIDTH
    AXI_LW     = 8                   , // AXI AWLEN   BITS WIDTH
    AXI_SW     = 3                   , // AXI AWSIZE  BITS WIDTH
    AXI_BURSTW = 2                   , // AXI AWBURST BITS WIDTH
    AXI_BRESPW = 2                   , // AXI BRESP   BITS WIDTH
    AXI_RRESPW = 2                   , // AXI RRESP   BITS WIDTH
    //--- ASI SLAVE CONFIGURE
    SLV_OD     = 4                   , // SLAVE OUTSTANDING DEPTH
    SLV_RD     = 64                  , // SLAVE READ BUFFER DEPTH
    SLV_WS     = 2                   , // SLAVE READ WAIT STATES CYCLE
    SLV_WD     = 64                  , // SLAVE WRITE BUFFER DEPTH
    SLV_BD     = 4                   , // SLAVE WRITE RESPONSE BUFFER DEPTH
    SLV_ARB    = 0                   , // 1-GRANT READ HIGHER PRIORITY; 0-GRANT WRITE HIGHER PRIORITY
    //--- DERIVED PARAMETERS
    AXI_WSTRBW = AXI_DW/8            , // AXI WSTRB BITS WIDTH
    SLV_BITS   = AXI_DW              , 
    SLV_BYTES  = SLV_BITS/8          ,
    SLV_BYTEW  = $clog2(SLV_BYTES+1)  
)(
    //---- AXI GLOBAL SIGNALS -------------------
    input  logic                    ACLK        ,
    input  logic                    ARESETn     ,
    //---- AXI ADDRESS WRITE SIGNALS ------------
    input  logic [AXI_IW-1     : 0] AWID        ,
    input  logic [AXI_AW-1     : 0] AWADDR      ,
    input  logic [AXI_LW-1     : 0] AWLEN       ,
    input  logic [AXI_SW-1     : 0] AWSIZE      ,
    input  logic [AXI_BURSTW-1 : 0] AWBURST     ,
    input  logic                    AWVALID     ,
    output logic                    AWREADY     ,
    //---- AXI DATA WRITE SIGNALS ---------------
    input  logic [AXI_DW-1     : 0] WDATA       ,
    input  logic [AXI_WSTRBW-1 : 0] WSTRB       ,
    input  logic                    WLAST       ,
    input  logic                    WVALID      ,
    output logic                    WREADY      ,
    //---- AXI WRITE RESPONSE SIGNALS -----------
    output logic [AXI_IW-1     : 0] BID         ,
    output logic [AXI_BRESPW-1 : 0] BRESP       ,
    output logic                    BVALID      ,
    input  logic                    BREADY      ,
    //---- USER LOGIC SIGNALS -------------------
    input  logic                    usr_clk     ,
    input  logic                    usr_reset_n ,
    //AW CHANNEL
    output logic [AXI_IW-1     : 0] m_wid       ,
    output logic [AXI_LW-1     : 0] m_wlen      ,
    output logic [AXI_SW-1     : 0] m_wsize     ,
    output logic [AXI_BURSTW-1 : 0] m_wburst    ,
    //W CHANNEL
    output logic [AXI_AW-1     : 0] m_waddr     ,
    output logic [AXI_DW-1     : 0] m_wdata     ,
    output logic [AXI_WSTRBW-1 : 0] m_wstrb     ,
    output logic                    m_wlast     ,
    output logic                    m_we        ,
    //ARBITER SIGNALS
    output logic                    m_wbusy     ,
    output logic                    m_awff_rvalid,
    input  logic                    wgranted
    
);
//------------------------------------
//------ INTERFACE PARAMETERS --------
//------------------------------------
localparam AFF_DW = AXI_IW + AXI_AW + AXI_LW + AXI_SW + AXI_BURSTW,
           WFF_DW = AXI_DW + AXI_WSTRBW + 1,
           BFF_DW = AXI_IW + AXI_BRESPW;
localparam OADDR_DEPTH = SLV_OD , // outstanding addresses buffer depth
           WDATA_DEPTH = SLV_WD , // write data buffer depth
           BRESP_DEPTH = SLV_BD ; // write response buffer depth
localparam [AXI_BURSTW-1 : 0] BT_FIXED     = AXI_BURSTW'(0);
localparam [AXI_BURSTW-1 : 0] BT_INCR      = AXI_BURSTW'(1);
localparam [AXI_BURSTW-1 : 0] BT_WRAP      = AXI_BURSTW'(2);
localparam [AXI_BURSTW-1 : 0] BT_RESERVED  = AXI_BURSTW'(3);
//----------------------------------------------------------------------------//
//-- !! TRANSFER MAY OCCUR IN <BP_FIRST> and <BP_BURST> !!--------------------//
//-- !! RESPONSE MAY OCCUR IN <BP_FIRST>  or <BP_BURST> or <BP_BRESP> !! -----//
//----------------------------------------------------------------------------//
// BP_FIRST: transfer the first transfer
// BP_BURST: transfer the rest  transfer(s)
// BP_BRESP: waiting for sending write response 
// BP_IDLE : do nothing
typedef enum logic [1:0] { BP_FIRST=2'b00, BP_BURST, BP_BRESP, BP_IDLE } WBURST_PHASE; 
//------------------------------------
//------ EASY SIGNALS ----------------
//------------------------------------
wire                     clk             ;
wire                     rst_n           ;
wire                     aff_rvalid      ;
wire                     wff_rvalid      ;
wire                     bff_rvalid      ;
//------------------------------------
//------ AW CHANNEL FIFO SIGNALS -----
//------------------------------------
logic                    aff_wreset_n    ;
logic                    aff_rreset_n    ;
logic                    aff_wclk        ;
logic                    aff_rclk        ;
logic                    aff_we          ;
logic                    aff_re          ;
logic                    aff_wfull       ;
logic                    aff_rempty      ;
logic [AFF_DW-1     : 0] aff_d           ;
logic [AFF_DW-1     : 0] aff_q           ;
//------------------------------------
//------ W CHANNEL FIFO SIGNALS ------
//------------------------------------
logic                    wff_wreset_n    ;
logic                    wff_rreset_n    ;
logic                    wff_wclk        ;
logic                    wff_rclk        ;
logic                    wff_we          ;
logic                    wff_re          ;
logic                    wff_wfull       ;
logic                    wff_rempty      ;
logic [WFF_DW-1     : 0] wff_d           ;
logic [WFF_DW-1     : 0] wff_q           ;
//------------------------------------
//------ B CHANNEL FIFO SIGNALS ------
//------------------------------------
logic                    bff_wreset_n    ;
logic                    bff_rreset_n    ;
logic                    bff_wclk        ;
logic                    bff_rclk        ;
logic                    bff_we          ;
logic                    bff_re          ;
logic                    bff_wfull       ;
logic                    bff_rempty      ;
logic [BFF_DW-1     : 0] bff_d           ;
logic [BFF_DW-1     : 0] bff_q           ;
//------------------------------------
//------ AW FIFO Q SIGNALS -----------
//------------------------------------
logic [AXI_IW-1     : 0] aq_id           ;
logic [AXI_AW-1     : 0] aq_addr         ;
logic [AXI_LW-1     : 0] aq_len          ;
logic [AXI_SW-1     : 0] aq_size         ;
logic [AXI_BURSTW-1 : 0] aq_burst        ;
//------------------------------------
//------ AW FIFO Q SIGNALS LATCH -----
//------------------------------------
logic [AXI_IW-1     : 0] aq_id_latch     ;
logic [AXI_AW-1     : 0] aq_addr_latch   ;
logic [AXI_LW-1     : 0] aq_len_latch    ;
logic [AXI_SW-1     : 0] aq_size_latch   ;
logic [AXI_BURSTW-1 : 0] aq_burst_latch  ;
//------------------------------------
//------ W FIFO Q SIGNALS ------------ 
//------------------------------------
logic [AXI_DW-1     : 0] wq_data         ;
logic [AXI_WSTRBW-1 : 0] wq_strb         ;
logic                    wq_last         ;
//------------------------------------
//------ B FIFO Q SIGNALS ------------
//------------------------------------
logic [AXI_IW-1     : 0] bq_bid          ;
logic [AXI_BRESPW-1 : 0] bq_bresp        ;
//------------------------------------
//------ AXI BURST ADDRESSES ---------
//------------------------------------
logic [SLV_BYTEW-1  : 0] burst_addr_inc  ;
logic [AXI_AW-0     : 0] burst_addr_nxt  ;
logic [AXI_AW-1     : 0] burst_addr      ;
logic [AXI_LW-1     : 0] burst_cc        ;
logic [AXI_AW-1     : 0] start_addr      ;
logic [AXI_AW-1     : 0] start_addr_mask ;
logic [AXI_AW-1     : 0] aligned_addr    ;
//------------------------------------
//------ TRANSFER SIZE ERROR ---------
//------------------------------------
logic                    trsize_err      ;
//------------------------------------
//------ WRITE RESPONSE VALUE --------
//------------------------------------
logic [AXI_BRESPW-1 : 0] m_bresp         ;
//------------------------------------
//------ STATE MACHINE VARIABLES -----
//------------------------------------
logic                    burst_last      ;
WBURST_PHASE             st_cur          ;
WBURST_PHASE             st_nxt          ; 
//-------------------------------------------------- LOGIC DESIGNS -----------------------------------------------------//
//------------------------------------
//------ OUTPUT PORTS ASSIGN ---------
//------------------------------------
//-- AXI HANDSHAKES
assign AWREADY        = ~aff_wfull         ;
assign WREADY         = ~wff_wfull         ;
//-- AXI B CHANNEL
assign BID            = bq_bid             ;
assign BRESP          = bq_bresp           ;
assign BVALID         = bff_rvalid         ;
//-- USER LOGIC
assign m_wid          = st_cur==BP_FIRST ? aq_id    : aq_id_latch;      
assign m_wlen         = st_cur==BP_FIRST ? aq_len   : aq_len_latch;    
assign m_wsize        = st_cur==BP_FIRST ? aq_size  : aq_size_latch;  
assign m_wburst       = st_cur==BP_FIRST ? aq_burst : aq_burst_latch;
assign m_waddr        = st_cur==BP_FIRST ? start_addr : burst_addr;
assign m_wdata        = wq_data            ;
assign m_wstrb        = wq_strb            ;
assign m_wlast        = wq_last            ;
assign m_we           = wff_re             ;
assign m_wbusy        = aff_re | st_cur==BP_BURST;
assign m_awff_rvalid  = ~aff_rempty && st_cur==BP_FIRST; 
//------------------------------------
//------ EASY ASSIGNMENTS ------------
//------------------------------------
assign clk            = usr_clk            ;
assign rst_n          = usr_reset_n        ;
assign aff_rvalid     = ~aff_rempty & ~wff_rempty && st_cur==BP_FIRST; // awfifo read may only occur in state <BP_FIRST>
assign wff_rvalid     = ~aff_rempty & ~wff_rempty && st_cur==BP_FIRST || ~wff_rempty && st_cur==BP_BURST; 
assign bff_rvalid     = ~bff_rempty        ;
//------------------------------------
//------ AW CHANNEL FIFO ASSIGN ------
//------------------------------------
assign aff_wreset_n   = ARESETn            ;
assign aff_rreset_n   = usr_reset_n        ;
assign aff_wclk       = ACLK               ;
assign aff_rclk       = usr_clk            ;
assign aff_we         = AWVALID & AWREADY  ;
assign aff_re         = aff_rvalid & wgranted; 
assign aff_d          = { AWID, AWADDR, AWLEN, AWSIZE, AWBURST };
assign { aq_id, aq_addr, aq_len, aq_size, aq_burst } = aff_q;
//------------------------------------
//------ W CHANNEL FIFO ASSIGN -------
//------------------------------------
assign wff_wreset_n   = ARESETn            ;
assign wff_rreset_n   = usr_reset_n        ;
assign wff_wclk       = ACLK               ;
assign wff_rclk       = usr_clk            ;
assign wff_we         = WVALID & WREADY    ;
assign wff_re         = wff_rvalid & wgranted;
assign wff_d          = { WDATA, WSTRB, WLAST };
assign { wq_data, wq_strb, wq_last } = wff_q;
//------------------------------------
//------ B CHANNEL FIFO ASSIGN -------
//------------------------------------
assign bff_wreset_n   = usr_reset_n        ;
assign bff_rreset_n   = ARESETn            ;
assign bff_wclk       = usr_clk            ;
assign bff_rclk       = ACLK               ;
assign bff_we         = ~bff_wfull && (burst_last || st_cur==BP_BRESP);
assign bff_re         = bff_rvalid & BREADY;
assign bff_d          = {m_wid, m_bresp}   ;
assign { bq_bid, bq_bresp } = bff_q        ;
//------------------------------------
//------ TRANSFER SIZE ASSIGN --------
//------------------------------------
assign trsize_err     = m_wsize > (AXI_SW'(SLV_BYTEW-1));
//------------------------------------
//------ WRITE RESPONSE VALUE --------
//------------------------------------
assign m_bresp        = { trsize_err, 1'b0 };
//------------------------------------
//------ ADDRESS CALCULATION ---------
//------------------------------------
// ! DOES NOT SUPPORT WRAP ! ! DOES NOT ACCEPT 'BT_RESERVED' BURST TYPE !
assign start_addr     = st_cur==BP_FIRST ? aq_addr : aq_addr_latch;
assign burst_addr_inc = m_wburst==BT_FIXED ? '0 : (SLV_BYTEW'(1))<<m_wsize;
assign burst_addr_nxt = st_cur==BP_FIRST ? burst_addr_inc+aligned_addr : st_cur==BP_BURST ? burst_addr_inc+burst_addr : 'x; 
assign aligned_addr   = start_addr_mask & start_addr;
always_comb begin
    start_addr_mask = ('1)<<(SLV_BYTEW-1);
	for(int i=0;i<SLV_BYTEW;i++) begin
		if(i==m_wsize) begin
            start_addr_mask = ('1)<<i;
		end
	end
end
//------------------------------------
//------ STATE MACHINES CONTROL ------
//------------------------------------
assign burst_last = (wff_re && aq_len=='0 && st_cur==BP_FIRST) || (wff_re && burst_cc==aq_len_latch && st_cur==BP_BURST);
always_ff @(posedge clk or negedge rst_n) begin 
    if(!rst_n) 
        st_cur <= BP_IDLE; 
    else 
        st_cur <= st_nxt;
end

always_comb begin
    case(st_cur)
        BP_FIRST: st_nxt = aff_re && aq_len ? BP_BURST : st_cur; // if burst length is 1, won't jump to <BP_BURST>
        BP_BURST: st_nxt = burst_last ? (~bff_wfull ? BP_FIRST : BP_BRESP) : st_cur;
        BP_BRESP: st_nxt = ~bff_wfull ? BP_FIRST : st_cur;
        BP_IDLE : st_nxt = BP_FIRST;
        default : st_nxt = BP_IDLE;
    endcase
end

always_ff @(posedge clk or negedge rst_n) begin 
    if(!rst_n) begin
        burst_cc   <= '0;
        burst_addr <= '0;
    end
    else if(st_cur==BP_FIRST) begin
        burst_cc   <= st_nxt==BP_BURST ? AXI_BURSTW'(1) : 'x;
        burst_addr <= st_nxt==BP_BURST ? burst_addr_nxt[0 +: AXI_AW] : 'x;
    end
    else if(st_cur==BP_BURST) begin
        burst_cc   <= ~wff_rempty ? burst_cc+1'b1 : burst_cc;
        burst_addr <= ~wff_rempty ? burst_addr_nxt[0 +: AXI_AW] : burst_addr;
    end
end
//------------------------------------
//------ AW FIFO Q SIGNALS LATCH -----
//------------------------------------
always_ff @(posedge clk) begin
    if(aff_re) begin
        aq_id_latch     <= aq_id   ;
        aq_addr_latch   <= aq_addr ;
        aq_len_latch    <= aq_len  ;
        aq_size_latch   <= aq_size ;
        aq_burst_latch  <= aq_burst;
    end
end
//------------------------------------
//------ AW CHANNEL BUFFER -----------
//------------------------------------
afifo #(
    .AW      ( $clog2(OADDR_DEPTH) ),
    .DW      ( AFF_DW              )
) aw_buffer (
    .wreset_n ( aff_wreset_n ),
    .rreset_n ( aff_rreset_n ),
    .wclk     ( aff_wclk     ),
    .rclk     ( aff_rclk     ),
    .we       ( aff_we       ),
    .re       ( aff_re       ),
    .wfull    ( aff_wfull    ),
    .rempty   ( aff_rempty   ),
    .d        ( aff_d        ),
    .q        ( aff_q        )
);
//------------------------------------
//------ W CHANNEL BUFFER ------------
//------------------------------------
afifo #(
    .AW      ( $clog2(WDATA_DEPTH) ),
    .DW      ( WFF_DW              )
) w_buffer (
    .wreset_n ( wff_wreset_n ),
    .rreset_n ( wff_rreset_n ),
    .wclk     ( wff_wclk     ),
    .rclk     ( wff_rclk     ),
    .we       ( wff_we       ),
    .re       ( wff_re       ),
    .wfull    ( wff_wfull    ),
    .rempty   ( wff_rempty   ),
    .d        ( wff_d        ),
    .q        ( wff_q        )
);
//------------------------------------
//------ B CHANNEL BUFFER ------------
//------------------------------------
afifo #(
    .AW      ( $clog2(BRESP_DEPTH) ),
    .DW      ( BFF_DW              )
) b_buffer (
    .wreset_n ( bff_wreset_n ),
    .rreset_n ( bff_rreset_n ),
    .wclk     ( bff_wclk     ),
    .rclk     ( bff_rclk     ),
    .we       ( bff_we       ),
    .re       ( bff_re       ),
    .wfull    ( bff_wfull    ),
    .rempty   ( bff_rempty   ),
    .d        ( bff_d        ),
    .q        ( bff_q        )
);
endmodule

