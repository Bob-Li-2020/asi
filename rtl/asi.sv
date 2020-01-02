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
module asi #(
    parameter 
              //--- AXI PARAMETERS
              AXI_DW     = 128                 , // AXI DATA     BUS WIDTH
              AXI_AW     = 40                  , // AXI ADDRESS  BUS WIDTH
              AXI_IW     = 8                   , // AXI ID TAG   BITS WIDTH
              AXI_LW     = 8                   , // AXI AWLEN    BITS WIDTH
              AXI_SW     = 3                   , // AXI AWSIZE   BITS WIDTH
              AXI_BURSTW = 2                   , // AXI AWBURST  BITS WIDTH
              AXI_RESPW  = 2                   , // AXI B(R)RESP BITS WIDTH
              AXI_WSTRBW = AXI_DW/8            , // AXI WSTRB    BITS WIDTH
              //--- SLAVE PARAMETERS
              SLV_OD     = 4                   , // SLAVE OUTSTANDING  DEPTH
              SLV_WD     = 64                  , // SLAVE WDATA BUFFER DEPTH
              SLV_RD     = 64                  , // SLAVE RDATA BUFFER DEPTH
              SLV_BD     = 4                   , // SLAVE BRESP BUFFER DEPTH
              SLV_BITS   = AXI_DW              ,
              SLV_BYTES  = SLV_BITS/8          ,
              SLV_BYTEW  = $clog2(SLV_BYTES+1) ,
              //--- FIFO CHOICE
              ALTERA_FIFO = 0
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
    output logic [AXI_RESPW-1  : 0] BRESP       ,
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
    output logic [AXI_RESPW-1  : 0] RRESP       ,
    output logic                    RLAST       ,
    output logic                    RVALID      ,
    input  logic                    RREADY      ,
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
    output logic                    m_wvalid    ,
    //AR CHANNEL
    output logic [AXI_IW-1     : 0] m_rid       ,
    output logic [AXI_LW-1     : 0] m_rlen      ,
    output logic [AXI_SW-1     : 0] m_rsize     ,
    output logic [AXI_BURSTW-1 : 0] m_rburst    ,
    //R CHANNEL
    output logic [AXI_AW-1     : 0] m_raddr     ,
    output logic                    m_rvalid    ,
    input  logic [AXI_DW-1     : 0] m_rdata     ,
    input  logic                    m_slverr     
);

asi_w #(
    .AXI_DW     ( AXI_DW     ),
    .AXI_AW     ( AXI_AW     ),
    .AXI_IW     ( AXI_IW     ),
    .AXI_LW     ( AXI_LW     ),
    .AXI_SW     ( AXI_SW     ),
    .AXI_BURSTW ( AXI_BURSTW ),
    .AXI_BRESPW ( AXI_RESPW  ),
    .AXI_WSTRBW ( AXI_WSTRBW ),
    .SLV_OD     ( SLV_OD     ),
    .SLV_WD     ( SLV_WD     ),
    .SLV_BD     ( SLV_BD     ),
    .ALTERA_FIFO( ALTERA_FIFO)
) w_inf (
    .*
);

asi_r #(
    .AXI_DW     ( AXI_DW     ),
    .AXI_AW     ( AXI_AW     ),
    .AXI_IW     ( AXI_IW     ),
    .AXI_LW     ( AXI_LW     ),
    .AXI_SW     ( AXI_SW     ),
    .AXI_BURSTW ( AXI_BURSTW ),
    .AXI_RRESPW ( AXI_RESPW  ),
    .SLV_OD     ( SLV_OD     ),
    .SLV_RD     ( SLV_RD     ),
    .ALTERA_FIFO( ALTERA_FIFO)
) r_inf (
    .*
);

endmodule

