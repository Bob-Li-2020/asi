/********************************************************
    Copyright (C) 2000.
    All rights reserved.

    Descriptions:
        (RTL) Asynchronous FIFO with variable depth and width.
    Notes:
        Depth must be 2, 4, 8, 16...
    Usage:
        util_fifoa #(width, log2(depth)) instance_name(...);
    FlipFlops Count:
        width * depth + log2(depth) * 6 + 6
        if(RS) +4


 ********************************************************/

module util_fifoa(WClk, WRstN, Write, FullN , WData, WNum,
                  RClk, RRstN, Read , EmptyN, RData, RFullN, RNum, TEST_MODE
                  );

parameter  DW=8; //data width: >0
parameter  AW=2; //log2(DEPTH): can be 1,2,3,4...
parameter  RS=0; //reset propagate enable, default: disable
parameter  PT=1; //read/write protect
localparam DEPTH=1<<AW;

input   WClk, WRstN;
input   RClk, RRstN;
input   Read, Write;
output  EmptyN, FullN;
input   [DW-1:0] WData;
output  [DW-1:0] RData;
output  RFullN;
output  [AW:0]  WNum, RNum;
input   TEST_MODE;

wire     rstn_w;
wire     rstn_r;

generate
    if(RS==0) //reset not propagate to other side
        begin : RS0
        assign   rstn_w = WRstN;
        assign   rstn_r = RRstN;
        end
    else
        begin : RS1
        wire     rstn = WRstN & RRstN;
        reg      rstn_w_sync,rstn_w_meta;
        reg      rstn_r_sync,rstn_r_meta;
        assign   rstn_w = TEST_MODE ? WRstN:rstn_w_sync;
        assign   rstn_r = TEST_MODE ? RRstN:rstn_r_sync;
        
        always  @(posedge WClk or negedge rstn)
            if(!rstn)  {rstn_w_sync,rstn_w_meta} <= 2'b0;
            else       {rstn_w_sync,rstn_w_meta} <= {rstn_w_meta, 1'b1};
        
        always  @(posedge RClk or negedge rstn)
            if(!rstn)  {rstn_r_sync,rstn_r_meta} <= 2'b0;
            else       {rstn_r_sync,rstn_r_meta} <= {rstn_r_meta, 1'b1};
        end
endgenerate

//use fifoa_ctrl and an async read RAM

  wire [AW-1:0] RAddr, WAddr;
  //ram
  reg  [DW-1:0] mem_ccdds[DEPTH-1:0]; //cross clock domain data startpoint
  assign RData = mem_ccdds[RAddr];
  
  always @(posedge WClk)
      if(Write && FullN)
          mem_ccdds[WAddr] <= WData;
  
  util_fifoa_ctrl #(AW,PT) u(
                  .WClk  (WClk  ),
                  .WRstN (rstn_w),
                  .Write (Write ),
                  .FullN (FullN ),
                  .WAddr (WAddr ),
                  .RClk  (RClk  ),
                  .RRstN (rstn_r),
                  .Read  (Read  ),
                  .EmptyN(EmptyN),
                  .RAddr (RAddr ),
                  .RFullN(RFullN),
                  .WPtrGray(),
                  .RPtrGray(),
                  .WPtrGray_sync(),
                  .RPtrGray_sync(),
                  .WNum  (WNum  ),
                  .RNum  (RNum  )
              );


endmodule
