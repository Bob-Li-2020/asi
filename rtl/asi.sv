//-- AUTHOR: LIBING
//-- DATE: 2019.12
//-- DESCRIPTION: AXI SLAVE INTERFACE. BASED ON AXI4 SPEC.
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

// asi: Axi Slave Interface
module asi //import asi_pkg::*;
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
    input  logic [3            : 0] AWCACHE     , // NO LOADS
    input  logic [2            : 0] AWPROT      , // NO LOADS
    input  logic [3            : 0] AWQOS       , // NO LOADS
    input  logic [3            : 0] AWREGION    , // NO LOADS
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
    //---- READ ADDRESS CHANNEL -----------------
    input  logic [AXI_IW-1     : 0] ARID        ,
    input  logic [AXI_AW-1     : 0] ARADDR      ,
    input  logic [AXI_LW-1     : 0] ARLEN       ,
    input  logic [AXI_SW-1     : 0] ARSIZE      ,
    input  logic [AXI_BURSTW-1 : 0] ARBURST     ,
    input  logic                    ARVALID     ,
    output logic                    ARREADY     ,
    input  logic [3            : 0] ARCACHE     , // NO LOADS 
    input  logic [2            : 0] ARPROT      , // NO LOADS 
    input  logic [3            : 0] ARQOS       , // NO LOADS 
    input  logic [3            : 0] ARREGION    , // NO LOADS
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
    //W CHANNEL
    output logic [AXI_DW-1     : 0] m_wdata     ,
    output logic [AXI_WSTRBW-1 : 0] m_wstrb     ,
    output logic                    m_we        ,
    //R CHANNEL
    output logic [AXI_AW-1     : 0] m_addr      ,
    input  logic [AXI_DW-1     : 0] m_rdata      
);

typedef enum logic [1:0] {ARB_IDLE=2'b00, ARB_READ, ARB_WRITE } TYPE_ARB;
typedef enum logic { RGNT=1'b0, WGNT } TYPE_GNT;
//------------------------------------
//------ EASY SIGNALS ----------------
//------------------------------------
wire                     rlast         ;
wire                     wlast         ;
wire                     arff_v        ;
wire                     awff_v        ;
//------------------------------------
//------ asi SIGNALS -----------------
//------------------------------------
logic                    m_re          ; // asi read request("m_raddr" valid)
logic                    m_rlast       ; // asi read request last cycle
logic                    m_rvalid      ; // rdata valid("m_rdata" valid)
logic                    m_rslverr     ; // slave device error flag
logic                    m_arff_rvalid ; // (AR FIFO NOT EMPTY) && (BP_st_cur==BP_FIRST)
logic                    m_awff_rvalid ; // (AW FIFO NOT EMPTY) && (BP_st_cur==BP_FIRST)
logic                    rgranted      ;
logic                    wgranted      ;
//AW CHANNEL
logic [AXI_IW-1     : 0] m_wid         ;
logic [AXI_LW-1     : 0] m_wlen        ;
logic [AXI_SW-1     : 0] m_wsize       ;
logic [AXI_BURSTW-1 : 0] m_wburst      ;
//W CHANNEL
logic                    m_wlast       ;
//AR CHANNEL
logic [AXI_IW-1     : 0] m_rid         ;
logic [AXI_LW-1     : 0] m_rlen        ;
logic [AXI_SW-1     : 0] m_rsize       ;
logic [AXI_BURSTW-1 : 0] m_rburst      ;
//ADDRESSES
logic [AXI_AW-1     : 0] m_waddr       ;
logic [AXI_AW-1     : 0] m_raddr       ;
//------------------------------------
//------ asi SIGNALS-busy ------------
//------------------------------------
logic                    m_wbusy       ;
logic                    m_rbusy       ;
//------------------------------------
//------ ARBITER STATE MACHINE -------
//------------------------------------
TYPE_ARB st_cur;
TYPE_ARB st_nxt;
//------------------------------------
//------ READ WAIT STATE CONTROL -----
//------------------------------------
generate 
    if(SLV_WS==0) begin: WS0
        assign m_rvalid = m_re;
    end: WS0
    else if(SLV_WS==1) begin: WS1
        always_ff @(posedge usr_clk)
            m_rvalid <= m_re;
    end: WS1
    else if(SLV_WS>=2) begin: WS_N
        logic [SLV_WS-2 : 0] m_re_ff ;
        always_ff @(posedge usr_clk)
            {m_rvalid, m_re_ff} <= {m_re_ff, m_re};
    end: WS_N
endgenerate
//------------------------------------
//------ slave error flag assign -----
//------------------------------------
assign m_rslverr = 1'b0             ; // TODO: register address space ONLY accepts 32-bit transfer size. assert this flag if not.
//------------------------------------
//------ EASY SIGNALS ASSIGN ---------
//------------------------------------
assign rlast     = m_rlast          ;
assign wlast     = m_wlast          ;
assign arff_v    = m_arff_rvalid    ;
assign awff_v    = m_awff_rvalid    ;
//------------------------------------
//------ ARBITER STATE MACHINE -------
//------------------------------------
assign m_addr    = m_we ? m_waddr : m_raddr;
assign rgranted  = st_cur==ARB_READ ; 
assign wgranted  = st_cur==ARB_WRITE;
always_ff @(posedge usr_clk or negedge usr_reset_n) begin
    if(!usr_reset_n) begin
        st_cur <= ARB_IDLE;
    end
    else begin
        st_cur <= st_nxt;
    end
end
always_comb begin
    case(st_cur)
        ARB_IDLE: begin
            st_nxt = st_cur;
            if(arff_v & (~awff_v | SLV_ARB))
                st_nxt = ARB_READ;
            if(awff_v & (~arff_v | ~SLV_ARB))
                st_nxt = ARB_WRITE;
        end
        ARB_READ: st_nxt = rlast ? (awff_v ? ARB_WRITE : ARB_IDLE) : st_cur;
        ARB_WRITE: st_nxt = wlast ? (arff_v ? ARB_READ : ARB_IDLE) : st_cur;
        default: st_nxt = ARB_IDLE;
    endcase
end

//------------------------------------
//------ asi_w/r INSTANCES -----------
//------------------------------------
asi_w #(
    //--- AXI BIT WIDTHs
    .AXI_DW     ( AXI_DW     ),
    .AXI_AW     ( AXI_AW     ),
    .AXI_IW     ( AXI_IW     ),
    .AXI_LW     ( AXI_LW     ),
    .AXI_SW     ( AXI_SW     ),
    .AXI_BURSTW ( AXI_BURSTW ),
    .AXI_BRESPW ( AXI_BRESPW ),
    .AXI_RRESPW ( AXI_RRESPW ),
    //--- ASI SLAVE CONFIGURE
    .SLV_OD     ( SLV_OD     ),
    .SLV_RD     ( SLV_RD     ),
    .SLV_WS     ( SLV_WS     ),
    .SLV_WD     ( SLV_WD     ),
    .SLV_BD     ( SLV_BD     ),
    .SLV_ARB    ( SLV_ARB    ),
    //--- DERIVED PARAMETERS
    .AXI_WSTRBW ( AXI_WSTRBW ),
    .SLV_BITS   ( SLV_BITS   ),
    .SLV_BYTES  ( SLV_BYTES  ),
    .SLV_BYTEW  ( SLV_BYTEW  )
) w_inf ( 
    .*
);

asi_r #(
    //--- AXI BIT WIDTHs
    .AXI_DW     ( AXI_DW     ),
    .AXI_AW     ( AXI_AW     ),
    .AXI_IW     ( AXI_IW     ),
    .AXI_LW     ( AXI_LW     ),
    .AXI_SW     ( AXI_SW     ),
    .AXI_BURSTW ( AXI_BURSTW ),
    .AXI_BRESPW ( AXI_BRESPW ),
    .AXI_RRESPW ( AXI_RRESPW ),
    //--- ASI SLAVE CONFIGURE
    .SLV_OD     ( SLV_OD     ),
    .SLV_RD     ( SLV_RD     ),
    .SLV_WS     ( SLV_WS     ),
    .SLV_WD     ( SLV_WD     ),
    .SLV_BD     ( SLV_BD     ),
    .SLV_ARB    ( SLV_ARB    ),
    //--- DERIVED PARAMETERS
    .AXI_WSTRBW ( AXI_WSTRBW ),
    .SLV_BITS   ( SLV_BITS   ),
    .SLV_BYTES  ( SLV_BYTES  ),
    .SLV_BYTEW  ( SLV_BYTEW  )
) r_inf ( 
    .*
);

endmodule


