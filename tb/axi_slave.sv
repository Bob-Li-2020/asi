`timescale 1ns / 1ps
module axi_slave import axi_pkg::*, asi_pkg::*;
(
    //---- AXI GLOBAL SIGNALS -------------------
    input  logic                    ACLK     ,
    input  logic                    ARESETn  ,
    //---- AXI ADDRESS WRITE SIGNALS ------------
    input  logic [AXI_IW-1     : 0] AWID     ,
    input  logic [AXI_AW-1     : 0] AWADDR   ,
    input  logic [AXI_LW-1     : 0] AWLEN    ,
    input  logic [AXI_SW-1     : 0] AWSIZE   ,
    input  logic [AXI_BURSTW-1 : 0] AWBURST  ,
    input  logic                    AWVALID  ,
    output logic                    AWREADY  ,
    input  logic [3            : 0] AWCACHE  , // NO LOADS
    input  logic [2            : 0] AWPROT   , // NO LOADS
    input  logic [3            : 0] AWQOS    , // NO LOADS
    input  logic [3            : 0] AWREGION , // NO LOADS
    //---- AXI DATA WRITE SIGNALS ---------------
    input  logic [AXI_DW-1     : 0] WDATA    ,
    input  logic [AXI_WSTRBW-1 : 0] WSTRB    ,
    input  logic                    WLAST    ,
    input  logic                    WVALID   ,
    output logic                    WREADY   ,
    //---- AXI WRITE RESPONSE SIGNALS -----------
    output logic [AXI_IW-1     : 0] BID      ,
    output logic [AXI_BRESPW-1  : 0] BRESP    ,
    output logic                    BVALID   ,
    input  logic                    BREADY   ,
    //---- READ ADDRESS CHANNEL -----------------
    input  logic [AXI_IW-1     : 0] ARID     ,
    input  logic [AXI_AW-1     : 0] ARADDR   ,
    input  logic [AXI_LW-1     : 0] ARLEN    ,
    input  logic [AXI_SW-1     : 0] ARSIZE   ,
    input  logic [AXI_BURSTW-1 : 0] ARBURST  ,
    input  logic                    ARVALID  ,
    output logic                    ARREADY  ,
    input  logic [3            : 0] ARCACHE  , // NO LOADS 
    input  logic [2            : 0] ARPROT   , // NO LOADS 
    input  logic [3            : 0] ARQOS    , // NO LOADS 
    input  logic [3            : 0] ARREGION , // NO LOADS
    //---- READ DATA CHANNEL --------------------
    output logic [AXI_IW-1     : 0] RID      ,
    output logic [AXI_DW-1     : 0] RDATA    ,
    output logic [AXI_RRESPW-1  : 0] RRESP    ,
    output logic                    RLAST    ,
    output logic                    RVALID   ,
    input  logic                    RREADY    
);

localparam MEM_LSB = $clog2(SLV_BYTES);
//---- USER LOGIC SIGNALS ------------
bit                      usr_clk         ;
bit                      usr_reset_n=1'b1;
//---- ASI SIGNALS -------------------
//AW CHANNEL
logic [AXI_IW-1     : 0] m_wid       ;
logic [AXI_LW-1     : 0] m_wlen      ;
logic [AXI_SW-1     : 0] m_wsize     ;
logic [AXI_BURSTW-1 : 0] m_wburst    ;
//W CHANNEL
logic [AXI_AW-1     : 0] m_waddr     ;
logic [AXI_DW-1     : 0] m_wdata     ;
logic [AXI_WSTRBW-1 : 0] m_wstrb     ;
logic                    m_wlast     ;
logic                    m_we        ;
//AR CHANNEL
logic [AXI_IW-1     : 0] m_rid       ;
logic [AXI_LW-1     : 0] m_rlen      ;
logic [AXI_SW-1     : 0] m_rsize     ;
logic [AXI_BURSTW-1 : 0] m_rburst    ;
//R CHANNEL
logic [AXI_AW-1     : 0] m_raddr     ;
logic [AXI_DW-1     : 0] m_rdata     ;
//W/R CHANNEL ADDRESS
logic [AXI_AW-1     : 0] m_addr     ;

assign m_slverr = 1'b0;

asi u_asi(
    .*
);

memory_model #(
    .N     ( SLV_BYTES ),
    .BW    ( 8         ),
    .DEPTH ( 2**SLV_AW ),
    .WS    ( SLV_WS    )
)asi_mem(
    .we    ( m_we     ),
    .clk   ( usr_clk  ),
    .addr  ( m_addr[MEM_LSB +: (SLV_AW-MEM_LSB)]  ),
    .be    ( m_wstrb  ),
    .wdata ( m_wdata  ),
    .q     ( m_rdata  )
);

always #(USR_CLKT/2) usr_clk++;

task USR_RESET;
    usr_reset_n = 1'b0;
    #12;
    usr_reset_n = 1'b1;
endtask

initial begin
    usr_clk = 1'b0;
    USR_RESET;
end

endmodule

module memory_model #(parameter 
N=16, 
BW=8,
DEPTH=2**10,
WS=0, // READ WAIT STATES
// derived parameters
ADDR=$clog2(DEPTH),
DW=BW*N,
MEM_LSB=$clog2(DW/BW)
)(
input we, 
input clk,
input [ADDR-1:MEM_LSB] addr, 

input [N-1:0] be, 
input [DW-1:0] wdata,  // pixel data
output reg [DW-1:0] q
);

logic [N-1:0][BW-1:0] ram[DEPTH]; 

always_ff@(posedge clk)
begin
	if(we) begin
	if(be[0]) ram[addr][0] <= wdata[0*BW +: BW]; 
	if(be[1]) ram[addr][1] <= wdata[1*BW +: BW];
	if(be[2]) ram[addr][2] <= wdata[2*BW +: BW];
	if(be[3]) ram[addr][3] <= wdata[3*BW +: BW];
	if(be[4]) ram[addr][4] <= wdata[4*BW +: BW];
	if(be[5]) ram[addr][5] <= wdata[5*BW +: BW];
	if(be[6]) ram[addr][6] <= wdata[6*BW +: BW];
	if(be[7]) ram[addr][7] <= wdata[7*BW +: BW];
	if(be[8]) ram[addr][8] <= wdata[8*BW +: BW]; 
	if(be[9]) ram[addr][9] <= wdata[9*BW +: BW];
	if(be[10]) ram[addr][10] <= wdata[10*BW +: BW];
	if(be[11]) ram[addr][11] <= wdata[11*BW +: BW];
	if(be[12]) ram[addr][12] <= wdata[12*BW +: BW];
	if(be[13]) ram[addr][13] <= wdata[13*BW +: BW];
	if(be[14]) ram[addr][14] <= wdata[14*BW +: BW];
	if(be[15]) ram[addr][15] <= wdata[15*BW +: BW];
	end
end

//---- READ WS CONTROL ----
genvar i;
generate 
    if(WS==0) begin: WS0
        assign q = ram[addr];
    end: WS0
    else if(WS>=1) begin: WS_N
        logic [DW-1:0] ram_q_ff[WS];
        for(i=0;i<WS;i++) begin
            if(i==0) begin
                always_ff @(posedge clk) 
                    ram_q_ff[0] <= ram[addr];
            end else begin
                always_ff @(posedge clk) 
                    ram_q_ff[i] <= ram_q_ff[i-1];
            end
        end
        assign q = ram_q_ff[WS-1];
    end: WS_N
endgenerate

endmodule
