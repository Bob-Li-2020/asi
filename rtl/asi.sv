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
    //--------- AXI PARAMETERS -------
    AXI_DW     = 128                 , // AXI DATA    BUS WIDTH
    AXI_AW     = 40                  , // AXI ADDRESS BUS WIDTH
    AXI_IW     = 8                   , // AXI ID TAG  BITS WIDTH
    AXI_LW     = 8                   , // AXI AWLEN   BITS WIDTH
    AXI_SW     = 3                   , // AXI AWSIZE  BITS WIDTH
    AXI_BURSTW = 2                   , // AXI AWBURST BITS WIDTH
    AXI_BRESPW = 2                   , // AXI BRESP   BITS WIDTH
    AXI_RRESPW = 2                   , // AXI RRESP   BITS WIDTH
    //--------- ASI CONFIGURE --------
    ASI_OD     = 4                   , // ASI OUTSTANDING DEPTH
    ASI_RD     = 64                  , // ASI READ BUFFER DEPTH
    ASI_WD     = 64                  , // ASI WRITE BUFFER DEPTH
    ASI_BD     = 4                   , // ASI WRITE RESPONSE BUFFER DEPTH
    ASI_ARB    = 0                   , // 1-GRANT READ WITH HIGHER PRIORITY; 0-GRANT WRITE WITH HIGHER PRIORITY
    //--------- SLAVE ATTRIBUTES -----
    SLV_WS     = 1                   , // SLAVE MODEL READ WAIT STATES CYCLE
    //-------- DERIVED PARAMETERS ----
    AXI_BYTES  = AXI_DW/8            , // BYTES NUMBER IN <AXI_DW>
    AXI_WSTRBW = AXI_BYTES           , // AXI WSTRB BITS WIDTH
    AXI_BYTESW = $clog2(AXI_BYTES+1)   
)(
    //---- AXI GLOBAL SIGNALS -----------------------
    input  logic                    ACLK            ,
    input  logic                    ARESETn         ,
    //---- AXI ADDRESS WRITE SIGNALS ----------------
    input  logic [AXI_IW-1     : 0] AWID            ,
    input  logic [AXI_AW-1     : 0] AWADDR          ,
    input  logic [AXI_LW-1     : 0] AWLEN           ,
    input  logic [AXI_SW-1     : 0] AWSIZE          ,
    input  logic [AXI_BURSTW-1 : 0] AWBURST         ,
    input  logic                    AWVALID         ,
    output logic                    AWREADY         ,
    input  logic [3            : 0] AWCACHE         , // NO LOADS
    input  logic [2            : 0] AWPROT          , // NO LOADS
    input  logic [3            : 0] AWQOS           , // NO LOADS
    input  logic [3            : 0] AWREGION        , // NO LOADS
    //---- AXI DATA WRITE SIGNALS -------------------
    input  logic [AXI_DW-1     : 0] WDATA           ,
    input  logic [AXI_WSTRBW-1 : 0] WSTRB           ,
    input  logic                    WLAST           ,
    input  logic                    WVALID          ,
    output logic                    WREADY          ,
    //---- AXI WRITE RESPONSE SIGNALS ---------------
    output logic [AXI_IW-1     : 0] BID             ,
    output logic [AXI_BRESPW-1 : 0] BRESP           ,
    output logic                    BVALID          ,
    input  logic                    BREADY          ,
    //---- READ ADDRESS CHANNEL ---------------------
    input  logic [AXI_IW-1     : 0] ARID            ,
    input  logic [AXI_AW-1     : 0] ARADDR          ,
    input  logic [AXI_LW-1     : 0] ARLEN           ,
    input  logic [AXI_SW-1     : 0] ARSIZE          ,
    input  logic [AXI_BURSTW-1 : 0] ARBURST         ,
    input  logic                    ARVALID         ,
    output logic                    ARREADY         ,
    input  logic [3            : 0] ARCACHE         , // NO LOADS 
    input  logic [2            : 0] ARPROT          , // NO LOADS 
    input  logic [3            : 0] ARQOS           , // NO LOADS 
    input  logic [3            : 0] ARREGION        , // NO LOADS
    //---- READ DATA CHANNEL ------------------------
    output logic [AXI_IW-1     : 0] RID             ,
    output logic [AXI_DW-1     : 0] RDATA           ,
    output logic [AXI_RRESPW-1 : 0] RRESP           ,
    output logic                    RLAST           ,
    output logic                    RVALID          ,
    input  logic                    RREADY          ,
    //---- USER LOGIC SIGNALS -----------------------
    input  logic                    usr_clk         ,
    input  logic                    usr_reset_n     ,
    //ADDRESS & ENABLE
    output logic [AXI_AW-1     : 0] usr_a           , // address
    output logic                    usr_ce          , // clock enable. Active-High
    //W CHANNEL
    output logic [AXI_DW-1     : 0] usr_d           , // data
    output logic [AXI_WSTRBW-1 : 0] usr_we          , // write enable. Active-High
    //R CHANNEL
    input  logic [AXI_DW-1     : 0] usr_q           , // Q
    //extra signals
    output logic [AXI_SW-1     : 0] usr_wsize       ,
    output logic [AXI_SW-1     : 0] usr_rsize       ,
    input  logic                    usr_wsize_error ,
    input  logic                    usr_rsize_error  
);
timeunit 1ns;
timeprecision 1ps;
typedef enum logic [1:0] {ARB_IDLE=2'b00, ARB_READ, ARB_WRITE } TYPE_ARB;
typedef enum logic { RGNT=1'b0, WGNT } TYPE_GNT;
//--------------------------------------
//------ r_inf/w_inf SIGNALS -----------
//--------------------------------------
//ADDRESS
logic [AXI_AW-1     : 0] m_addr        ;
//W CHANNEL
logic [AXI_DW-1     : 0] m_wdata       ;
logic [AXI_WSTRBW-1 : 0] m_wstrb       ;
logic                    m_we          ;
//R CHANNEL
logic [AXI_DW-1     : 0] m_rdata       ;
logic                    m_re          ; // asi read request("m_raddr" valid)
//--------------------------------------
//------ EASY SIGNALS ------------------
//--------------------------------------
logic                    rlast         ;
logic                    wlast         ;
logic                    arff_v        ;
logic                    awff_v        ;
//--------------------------------------
//------ asi SIGNALS -------------------
//--------------------------------------
//ARBITER SIGNALS
logic                    m_arff_rvalid ; // (AR FIFO NOT EMPTY) && (BP_st_cur==BP_FIRST)
logic                    m_awff_rvalid ; // (AW FIFO NOT EMPTY) && (BP_st_cur==BP_FIRST)
logic                    m_rgranted    ;
logic                    m_wgranted    ;
//ERROR FLAGS
logic                    m_wsize_error ; // unsupported transfer size
logic                    m_rsize_error ; // unsupported transfer size
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
//R CHANNEL
logic                    m_rlast       ; // asi read request last cycle
//ADDRESSES
logic [AXI_AW-1     : 0] m_waddr       ;
logic [AXI_AW-1     : 0] m_raddr       ;
//--------------------------------------
//------ ARBITER STATE MACHINE ---------
//--------------------------------------
TYPE_ARB st_cur;
TYPE_ARB st_nxt;
//------------------------------------
//---- TOP PORTS ASSIGN --------------
//------------------------------------
//ADDRESS & ENABLE
assign usr_a         = m_addr           ; // address
assign usr_ce        = m_we | m_re      ; // clock enable
//W CHANNEL
assign usr_d         = m_wdata          ; // data
assign usr_we        = m_wstrb & {AXI_WSTRBW{m_we}}; // write enable
//R CHANNEL
assign m_rdata       = usr_q            ; // Q
//extra signals
assign usr_wsize     = m_wsize          ;
assign usr_rsize     = m_rsize          ;
assign m_wsize_error = usr_wsize_error  ;
assign m_rsize_error = usr_rsize_error  ;
//------------------------------------
//------ EASY SIGNALS ASSIGN ---------
//------------------------------------
assign rlast         = m_rlast          ;
assign wlast         = m_wlast          ;
assign arff_v        = m_arff_rvalid    ;
assign awff_v        = m_awff_rvalid    ;
//------------------------------------
//------ ARBITER STATE MACHINE -------
//------------------------------------
assign m_addr        = m_we ? m_waddr : m_raddr;
assign m_rgranted    = st_cur==ARB_READ ; 
assign m_wgranted    = st_cur==ARB_WRITE;
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
            if(arff_v & (!awff_v | ASI_ARB))
                st_nxt = ARB_READ;
            if(awff_v & (!arff_v | !ASI_ARB))
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
//--------- AXI PARAMETERS -------
.AXI_DW     ( AXI_DW     ),
.AXI_AW     ( AXI_AW     ),
.AXI_IW     ( AXI_IW     ),
.AXI_LW     ( AXI_LW     ),
.AXI_SW     ( AXI_SW     ),
.AXI_BURSTW ( AXI_BURSTW ),
.AXI_BRESPW ( AXI_BRESPW ),
.AXI_RRESPW ( AXI_RRESPW ),
//--------- ASI CONFIGURE --------
.ASI_OD     ( ASI_OD     ),
.ASI_RD     ( ASI_RD     ),
.ASI_WD     ( ASI_WD     ),
.ASI_BD     ( ASI_BD     ),
.ASI_ARB    ( ASI_ARB    ),
//--------- SLAVE ATTRIBUTES -----
.SLV_WS     ( SLV_WS     ),
//-------- DERIVED PARAMETERS ----
.AXI_BYTES  ( AXI_BYTES  ),
.AXI_WSTRBW ( AXI_WSTRBW ),
.AXI_BYTESW ( AXI_BYTESW )
) w_inf ( 
    .*
);

asi_r #(
//--------- AXI PARAMETERS -------
.AXI_DW     ( AXI_DW     ),
.AXI_AW     ( AXI_AW     ),
.AXI_IW     ( AXI_IW     ),
.AXI_LW     ( AXI_LW     ),
.AXI_SW     ( AXI_SW     ),
.AXI_BURSTW ( AXI_BURSTW ),
.AXI_BRESPW ( AXI_BRESPW ),
.AXI_RRESPW ( AXI_RRESPW ),
//--------- ASI CONFIGURE --------
.ASI_OD     ( ASI_OD     ),
.ASI_RD     ( ASI_RD     ),
.ASI_WD     ( ASI_WD     ),
.ASI_BD     ( ASI_BD     ),
.ASI_ARB    ( ASI_ARB    ),
//--------- SLAVE ATTRIBUTES -----
.SLV_WS     ( SLV_WS     ),
//-------- DERIVED PARAMETERS ----
.AXI_BYTES  ( AXI_BYTES  ),
.AXI_WSTRBW ( AXI_WSTRBW ),
.AXI_BYTESW ( AXI_BYTESW )
) r_inf ( 
    .*
);

endmodule


