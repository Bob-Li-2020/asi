/********************************************************
    Copyright (C) 2000.
    All rights reserved.

    Descriptions:
        (RTL) Asynchronous FIFO with variable depth and width.
    Notes:
        Depth must be 2, 4, 8, 16... ( DL=1,2,3,4,... )
    Usage:
        fifoa_ctrl #(log2(depth)) instance_name(...);
    FlipFlops Count:
        log2(depth) * 6 + 6 (+1 for FR&FullN, +1 for ER&EmptyN, +1 for RFR&RFullN)
    SubModules:
        none

    Written by  Zhu Feng   May 26, 2007  (ver 2.0)
                           Mar 7, 2009   (add FR, ER, RFR, support unregister output, save 1 cycle)
 ********************************************************/
module util_fifoa_ctrl( WClk, WRstN, Write, FullN , WAddr, WPtrGray, RPtrGray_sync, WNum,
                        RClk, RRstN, Read , EmptyN, RAddr, RFullN, RPtrGray, WPtrGray_sync, RNum
                       );

parameter  DL = 8;
parameter  PT = 1; //read/write protect
parameter  FR = 1; //FullN REG out
parameter  ER = 1; //EmptyN REG out
parameter  RFR= 1; //RFullN REG out

input           WClk;
input           WRstN; 
input           RClk; 
input           RRstN; 
input           Write; 
output          FullN;  
input           Read;  
output          EmptyN;  
output[DL-1:0]  WAddr;
output[DL-1:0]  RAddr;
output          RFullN;
output[DL:0]    WPtrGray;
output[DL:0]    RPtrGray;
output[DL:0]    WPtrGray_sync;
output[DL:0]    RPtrGray_sync;
output[DL:0]    WNum;
output[DL:0]    RNum;

reg             valid_r;
reg             nfull_r; //fulln at write side
reg             rnful_r; //fulln at read side
reg   [DL:0]    RPtrGray;
reg   [DL:0]    WPtrGray;
reg   [DL:0]    RPtrGray_sync;
reg   [DL:0]    RPtrGray_meta;
reg   [DL:0]    WPtrGray_sync;
reg   [DL:0]    WPtrGray_meta;
reg   [DL-1:0]  WAddr;
reg   [DL-1:0]  RAddr;
reg   [DL:0]    RPtrGray_cmp;
reg   [DL:0]    WPtrGray_cmp;

wire            wt = PT ? (Write & FullN ) : Write;
wire            rd = PT ? (Read  & EmptyN) : Read ;

wire  [DL:0]    RPtrBin      = GrayToBin(RPtrGray);
wire  [DL:0]    RPtrBinA1    = RPtrBin + 1;
wire  [DL:0]    RPtrGrayNx   = rd ? BinToGray(RPtrBinA1) : RPtrGray;
wire  [DL:0]    WPtrBin      = GrayToBin(WPtrGray);
wire  [DL:0]    WPtrBinNx    = WPtrBin + (wt ? 1 : 0);
wire  [DL:0]    WPtrGrayNx   = BinToGray(WPtrBinNx);

wire            valid_c      = RPtrGray != WPtrGray_sync;
wire            nfull_c      = WPtrGray != RPtrGray_cmp;
wire            rnful_c      = RPtrGray != WPtrGray_cmp;

assign          EmptyN       = ER  ? valid_r : valid_c;
assign          FullN        = FR  ? nfull_r : nfull_c;
assign          RFullN       = RFR ? rnful_r : rnful_c;
assign          WNum         = WPtrBin - GrayToBin(RPtrGray_sync);
assign          RNum         = GrayToBin(WPtrGray_sync) - RPtrBin;


always @(*)
    begin
    WAddr        = WPtrGray[DL-1:0];
    WAddr[DL-1]  = WPtrGray[DL]^WPtrGray[DL-1];
    RAddr        = RPtrGray[DL-1:0];
    RAddr[DL-1]  = RPtrGray[DL]^RPtrGray[DL-1];
    RPtrGray_cmp = RPtrGray_sync;
    RPtrGray_cmp[DL:DL-1] = ~RPtrGray_sync[DL:DL-1];
    WPtrGray_cmp = WPtrGray_sync;
    WPtrGray_cmp[DL:DL-1] = ~WPtrGray_sync[DL:DL-1];
    end

//read pointers
always @(posedge RClk or negedge RRstN) 
    if(!RRstN)
        RPtrGray <= 0;
    else
        RPtrGray <= RPtrGrayNx;

always @(posedge RClk or negedge RRstN) 
    if(!RRstN) 
        valid_r <= 1'b0;
    else
        valid_r <= RPtrGrayNx != WPtrGray_sync;

always @(posedge RClk or negedge RRstN) 
    if(!RRstN) 
        rnful_r <= 1'b1;
    else
        rnful_r <= RPtrGrayNx != WPtrGray_cmp;

//write pointers
always @(posedge WClk or negedge WRstN) 
    if(!WRstN)
        WPtrGray <= 0;
    else
        WPtrGray <= WPtrGrayNx;

always @(posedge WClk or negedge WRstN) 
    if(!WRstN) 
        nfull_r <= 1'b0; //deny write during reset
    else
        nfull_r <= WPtrGrayNx != RPtrGray_cmp;

//synchronize
always @(posedge RClk or negedge RRstN)
    if(!RRstN) {WPtrGray_sync, WPtrGray_meta} <= 0;
    else       {WPtrGray_sync, WPtrGray_meta} <= {WPtrGray_meta, WPtrGray};

always @(posedge WClk or negedge WRstN)
    if(!WRstN) {RPtrGray_sync, RPtrGray_meta} <= 0;
    else       {RPtrGray_sync, RPtrGray_meta} <= {RPtrGray_meta, RPtrGray};

//functions
function [DL:0] GrayToBin;
    input [DL:0] Gray;
    integer i;
    begin
    GrayToBin[DL]=Gray[DL];
    for(i=DL-1;i>=0;i=i-1)
        GrayToBin[i] = GrayToBin[i+1]^Gray[i];
    end
endfunction

function [DL:0] BinToGray;
    input [DL:0] Bin;
    BinToGray = {1'b0,Bin[DL:1]} ^ Bin;
endfunction


endmodule



