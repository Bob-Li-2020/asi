package asi_pkg;
//------------ asi_w ------------
//-- module head parameters
localparam
//--- AXI BIT WIDTH 
AXI_DW     = 128                 , // AXI DATA    BUS WIDTH
AXI_AW     = 40                  , // AXI ADDRESS BUS WIDTH
AXI_IW     = 8                   , // AXI ID TAG  BITS WIDTH
AXI_LW     = 8                   , // AXI AWLEN   BITS WIDTH
AXI_SW     = 3                   , // AXI AWSIZE  BITS WIDTH
AXI_BURSTW = 2                   , // AXI AWBURST BITS WIDTH
AXI_BRESPW = 2                   , // AXI BRESP   BITS WIDTH
AXI_RRESPW = 2                   , // AXI RRESP   BITS WIDTH
//--- ASI SLAVE CONFIGURE
SLV_OD     = 4                   , 
SLV_RD     = 64                  , 
SLV_WS     = 2                   ,
SLV_WD     = 64                  , 
SLV_BD     = 4                   , 
SLV_ARB    = 0                   , // 1-GRANT READ HIGHER PRIORITY; 0-GRANT WRITE HIGHER PRIORITY
//--- DERIVED PARAMETERS
AXI_WSTRBW = AXI_DW/8            , // AXI WSTRB   BITS WIDTH
SLV_BITS   = AXI_DW              ,
SLV_BYTES  = SLV_BITS/8          ,
SLV_BYTEW  = $clog2(SLV_BYTES+1) ;
//-- module body
//------------------------------------
//------ AXI-SPEC BURST TYPESS -------
//------------------------------------
localparam [AXI_BURSTW-1 : 0] BT_FIXED     = AXI_BURSTW'(0);
localparam [AXI_BURSTW-1 : 0] BT_INCR      = AXI_BURSTW'(1);
localparam [AXI_BURSTW-1 : 0] BT_WRAP      = AXI_BURSTW'(2);
localparam [AXI_BURSTW-1 : 0] BT_RESERVED  = AXI_BURSTW'(3);
//------------------------------------
//------ AXI-SPEC WRAP LENGTHS -------
//------------------------------------
localparam [AXI_LW-1     : 0] WRAP_BL_2    = AXI_LW'(1);
localparam [AXI_LW-1     : 0] WRAP_BL_4    = AXI_LW'(3);
localparam [AXI_LW-1     : 0] WRAP_BL_8    = AXI_LW'(7);
localparam [AXI_LW-1     : 0] WRAP_BL_16   = AXI_LW'(15);
//------------------------------------
//------ TRANSFER SIZES IN BYTES -----
//------------------------------------
localparam [AXI_SW-1 : 0] TRSIZE_4B  = AXI_SW'(2); // transfer size 4  bytes(32  bits). (4  = 2**TRSIZE_4B)
localparam [AXI_SW-1 : 0] TRSIZE_8B  = AXI_SW'(3); // transfer size 8  bytes(64  bits). (8  = 2**TRSIZE_8B)
localparam [AXI_SW-1 : 0] TRSIZE_16B = AXI_SW'(4); // transfer size 16 bytes(128 bits). (16 = 2**TRSIZE_16B)

endpackage
