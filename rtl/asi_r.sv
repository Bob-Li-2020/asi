//-- AUTHOR: LIBING
//-- DATE: 2019.12
//-- DESCRIPTION: AXI SLAVE INTERFACE.READ. BASED ON AXI4 SPEC.
//----------------------SUPPORTED FEATURES: 
//----------------------                         1) OUTSTANDING TRANSACTIONS; 
//----------------------                         2) NARROW TRANSFERS; 
//----------------------                         3) UNALIGNED TRANSFERS.
//----------------------NOT SUPPORTED FEATURES: 
//----------------------                         1) OUT-OF-ORDER TRANSACTIONS; 
//----------------------                         2) INTERLEAVING TRANSFERS;
//----------------------                         3) WRAP TRANSFERS.
//----------------------RRESP:
//----------------------        2'b00: OKAY;
//----------------------        2'b01: EXOKAY. NOT supported;
//----------------------        2'b10: SLVERR; 
//----------------------        2'b00: DECERR. NOT supported.

// asi_r: Axi Slave Interface Read
module asi_r import asi_pkg::*;
#(
    SLV_OD  = 4  , 
    SLV_RD  = 64 , 
    SLV_WS  = 2  ,
    FPGA_IP = 0    
)(
    //---- AXI GLOBAL SIGNALS -------------------
    input  logic                    ACLK        ,
    input  logic                    ARESETn     ,
    //---- READ ADDRESS CHANNEL -----------------
    input  logic [AXI_IW-1     : 0] ARID        ,
    input  logic [AXI_AW-1     : 0] ARADDR      ,
    input  logic [AXI_LW-1     : 0] ARLEN       ,
    input  logic [AXI_SW-1     : 0] ARSIZE      ,
    input  logic [AXI_BURSTW-1 : 0] ARBURST     ,
    input  logic                    ARVALID     ,
    output logic                    ARREADY     ,
    //---- READ DATA CHANNEL --------------------
    output logic [AXI_IW-1     : 0] RID         ,
    output logic [AXI_DW-1     : 0] RDATA       ,
    output logic [AXI_RRESPW-1 : 0] RRESP       ,
    output logic                    RLAST       ,
    output logic                    RVALID      ,
    input  logic                    RREADY      ,
    //---- USER LOGIC SIGNALS -------------------
    input  logic                    usr_clk     ,
    input  logic                    usr_reset_n ,
    //AR CHANNEL
    output logic [AXI_IW-1     : 0] m_rid       ,
    output logic [AXI_LW-1     : 0] m_rlen      ,
    output logic [AXI_SW-1     : 0] m_rsize     ,
    output logic [AXI_BURSTW-1 : 0] m_rburst    ,
    //R CHANNEL
    output logic [AXI_AW-1     : 0] m_raddr     ,
    output logic                    m_re        ,
    input  logic [AXI_DW-1     : 0] m_rdata     ,
    input  logic                    m_rvalid    ,
    input  logic                    m_slverr     
);

//------------------------------------
//------ INTERFACE PARAMETERS --------
//------------------------------------
localparam AFF_DW = AXI_IW + AXI_AW + AXI_LW + AXI_SW + AXI_BURSTW,
           RFF_DW = AXI_IW + AXI_DW + AXI_RRESPW + 1;
localparam OADDR_DEPTH = SLV_OD , // outstanding addresses buffer depth
           RDATA_DEPTH = SLV_RD ; // read data buffer depth
//------------------------------------
//------ BURST PHASE DATA TYPE -------
//------------------------------------
// BP_FIRST: transfer the first transfer
// BP_BURST: transfer the rest  transfer(s)
// BP_IDLE : do nothing
typedef enum logic [1:0] { BP_FIRST=2'b00, BP_BURST, BP_IDLE } RBURST_PHASE; 
//------------------------------------
//------ EASY SIGNALS ----------------
//------------------------------------
wire                     clk             ;
wire                     rst_n           ;
wire                     aff_rvalid      ;
//------------------------------------
//------ AR CHANNEL FIFO SIGNALS -----
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
//------ R CHANNEL FIFO SIGNALS ------
//------------------------------------
logic                    rff_wreset_n    ;
logic                    rff_rreset_n    ;
logic                    rff_wclk        ;
logic                    rff_rclk        ;
logic                    rff_we          ;
logic                    rff_re          ;
logic                    rff_wfull       ;
logic                    rff_rempty      ;
logic [RFF_DW-1     : 0] rff_d           ;
logic [RFF_DW-1     : 0] rff_q           ;
//------------------------------------
//------ AR FIFO Q SIGNALS -----------
//------------------------------------
logic [AXI_IW-1     : 0] aq_id           ;
logic [AXI_AW-1     : 0] aq_addr         ;
logic [AXI_LW-1     : 0] aq_len          ;
logic [AXI_SW-1     : 0] aq_size         ;
logic [AXI_BURSTW-1 : 0] aq_burst        ;
//------------------------------------
//------ AR FIFO Q SIGNALS LATCH -----
//------------------------------------
logic [AXI_IW-1     : 0] aq_id_latch     ;
logic [AXI_AW-1     : 0] aq_addr_latch   ;
logic [AXI_LW-1     : 0] aq_len_latch    ;
logic [AXI_SW-1     : 0] aq_size_latch   ;
logic [AXI_BURSTW-1 : 0] aq_burst_latch  ;
//------------------------------------
//------ R FIFO Q SIGNALS ------------ 
//------------------------------------
logic [AXI_IW-1     : 0] rq_id           ;
logic [AXI_DW-1     : 0] rq_data         ;
logic [AXI_RRESPW-1 : 0] rq_resp         ;
logic                    rq_last         ;
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
//------ R FIFO D SIGNALS ------------
//------------------------------------
logic [AXI_RRESPW-1 : 0] m_rresp_ws      ;
logic                    burst_last_ws   ;
logic [AXI_IW-1     : 0] m_rid_ws        ;
//------------------------------------
//------ TRANSFER SIZE ERROR ---------
//------------------------------------
logic                    trsize_err      ;
//------------------------------------
//------ READ RESPONSE VALUE ---------
//------------------------------------
logic [AXI_RRESPW-1 : 0] m_rresp         ;
//------------------------------------
//------ STATE MACHINE VARIABLES -----
//------------------------------------
logic                    burst_last      ;
RBURST_PHASE             st_cur          ;
RBURST_PHASE             st_nxt          ; 
//-------------------------------------------------- LOGIC DESIGNS -----------------------------------------------------//

//------------------------------------
//------ OUTPUT PORTS ASSIGN ---------
//------------------------------------
//-- AXI HANDSHAKES
assign ARREADY        = ~aff_wfull       ;
//-- R CHANNEL 
assign RID            = rq_id            ;
assign RDATA          = rq_data          ;
assign RRESP          = rq_resp          ;
assign RLAST          = rq_last          ;
assign RVALID         = ~rff_rempty      ;
//-- USER LOGIC
assign m_rid          = st_cur==BP_FIRST ? aq_id    : aq_id_latch;
assign m_rlen         = st_cur==BP_FIRST ? aq_len   : aq_len_latch;
assign m_rsize        = st_cur==BP_FIRST ? aq_size  : aq_size_latch;
assign m_rburst       = st_cur==BP_FIRST ? aq_burst : aq_burst_latch;
assign m_raddr        = st_cur==BP_FIRST ? start_addr : burst_addr;
assign m_re           = ~aff_rempty && st_cur==BP_FIRST || st_cur==BP_BURST;
//------------------------------------
//------ EASY ASSIGNMENTS ------------
//------------------------------------
assign clk            = usr_clk          ;
assign rst_n          = usr_reset_n      ;
assign aff_rvalid     = ~aff_rempty && st_cur==BP_FIRST;
//------------------------------------
//------ AR CHANNEL FIFO ASSIGN ------
//------------------------------------
assign aff_wreset_n   = ARESETn          ;
assign aff_rreset_n   = usr_reset_n      ;
assign aff_wclk       = ACLK             ;
assign aff_rclk       = usr_clk          ;
assign aff_we         = ARVALID & ARREADY;
assign aff_re         = aff_rvalid       ;
assign aff_d          = { ARID, ARADDR, ARLEN, ARSIZE, ARBURST };
assign { aq_id, aq_addr, aq_len, aq_size, aq_burst } = aff_q;
//------------------------------------
//------ R CHANNEL FIFO ASSIGN -------
//------------------------------------
assign rff_wreset_n   = usr_reset_n      ;
assign rff_rreset_n   = ARESETn          ;
assign rff_wclk       = usr_clk          ;
assign rff_rclk       = ACLK             ;
assign rff_we         = m_rvalid         ;
assign rff_re         = RVALID & RREADY  ;
assign rff_d          = { m_rid_ws, m_rdata, m_rresp_ws, burst_last_ws }; 
assign { rq_id, rq_data, rq_resp, rq_last } = rff_q;
//------------------------------------
//------ TRANSFER SIZE ERROR ---------
//------------------------------------
assign trsize_err     = m_rsize > (AXI_SW'(SLV_BYTEW-1)); 
//------------------------------------
//------ READ RESPONSE VALUE ---------
//------------------------------------
assign m_rresp        = { trsize_err, 1'b0 };
//------------------------------------
//------ ADDRESS CALCULATION ---------
//------------------------------------
assign burst_addr_inc = m_rburst==BT_FIXED ? '0 : (SLV_BYTEW'(1))<<m_rsize;
assign burst_addr_nxt = st_cur==BP_FIRST ? burst_addr_inc+aligned_addr : st_cur==BP_BURST ? burst_addr_inc+burst_addr : 'x;
assign start_addr     = st_cur==BP_FIRST ? aq_addr : aq_addr_latch;
assign aligned_addr   = start_addr_mask & start_addr;
always_comb begin
    start_addr_mask = ('1)<<(SLV_BYTEW-1);
	for(int i=0;i<SLV_BYTEW;i++) begin
		if(i==m_rsize) begin
            start_addr_mask = ('1)<<i;
		end
	end
end
//------------------------------------
//------ STATE MACHINES CONTROL ------
//------------------------------------
assign burst_last = (m_re && aq_len=='0 && st_cur==BP_FIRST) || (m_re && burst_cc==aq_len_latch && st_cur==BP_BURST);
always_ff @(posedge clk or negedge rst_n) begin 
    if(!rst_n) 
        st_cur <= BP_IDLE; 
    else 
        st_cur <= st_nxt;
end
always_comb 
    case(st_cur)
        BP_FIRST: st_nxt = aff_re && aq_len ? BP_BURST : st_cur;
        BP_BURST: st_nxt = burst_last ? BP_FIRST : st_cur;
        BP_IDLE : st_nxt = BP_FIRST;
        default : st_nxt = BP_IDLE;
    endcase
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
        burst_cc   <= m_re ? burst_cc+1'b1 : burst_cc;
        burst_addr <= m_re ? burst_addr_nxt[0 +: AXI_AW] : burst_addr;
    end
end
//------------------------------------
//------ R FIFO D SIGNALS ------------
//------------------------------------
generate 
    if(SLV_WS==0) begin: WS0
        assign m_rresp_ws    = m_rresp   ;
        assign burst_last_ws = burst_last;
        assign m_rid_ws      = m_rid     ;
    end: WS0
    else if(SLV_WS==1) begin: WS1
        always_ff @(posedge clk)
            {m_rresp_ws, burst_last_ws, m_rid_ws} <= {m_rresp, burst_last, m_rid};
    end: WS1
    else begin: WS_N
        wire  [AXI_RRESPW+1+AXI_IW-1 : 0] rfd_sigs = {m_rresp, burst_last, m_rid};
        logic [AXI_RRESPW+1+AXI_IW-1 : 0] rfd_sigs_ff[SLV_WS] ;
        always_ff @(posedge clk) begin
            rfd_sigs_ff[0] <= rfd_sigs;
            for(int i=1;i<SLV_WS;i++) 
                rfd_sigs_ff[i] <= rfd_sigs_ff[i-1];
        end
        assign {m_rresp_ws, burst_last_ws, m_rid_ws} = rfd_sigs_ff[SLV_WS-1];
    end
endgenerate
//------------------------------------
//------ AR FIFO Q SIGNALS LATCH -----
//------------------------------------
always_ff @(posedge clk) begin
    if(aff_re) begin
        aq_id_latch    <= aq_id;
        aq_addr_latch  <= aq_addr;
        aq_len_latch   <= aq_len;
        aq_size_latch  <= aq_size;
        aq_burst_latch <= aq_burst;
    end
end
//------------------------------------
//------ AR CHANNEL BUFFER -----------
//------------------------------------
afifo #(
    .AW      ( $clog2(OADDR_DEPTH) ),
    .DW      ( AFF_DW              ),
    .FPGA_IP ( FPGA_IP             )
) ar_buffer (
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
//------ R CHANNEL BUFFER ------------
//------------------------------------
afifo #(
    .AW      ( $clog2(RDATA_DEPTH) ),
    .DW      ( RFF_DW              ),
    .FPGA_IP ( FPGA_IP             )
) r_buffer (
    .wreset_n ( rff_wreset_n ),
    .rreset_n ( rff_rreset_n ),
    .wclk     ( rff_wclk     ),
    .rclk     ( rff_rclk     ),
    .we       ( rff_we       ),
    .re       ( rff_re       ),
    .wfull    ( rff_wfull    ),
    .rempty   ( rff_rempty   ),
    .d        ( rff_d        ),
    .q        ( rff_q        )
);

endmodule

