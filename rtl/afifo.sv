module afifo #(
    parameter AW=20,
    DW=128,
    FPGA_IP=0
)(
    input  logic            wreset_n ,
    input  logic            rreset_n ,
    input  logic            wclk     ,
    input  logic            rclk     ,
    input  logic            we       ,
    input  logic            re       ,
    output logic            wfull    ,
    output logic            rempty   ,
    input  logic [DW-1 : 0] d        ,
    output logic [DW-1 : 0] q         
);
generate if(FPGA_IP==0) begin: UTIL_AFIFO
    wire   EmptyN ;
    wire   FullN  ;
    assign wfull  = ~FullN ;
    assign rempty = ~EmptyN;
    util_fifoa #(
        .AW ( AW ),
        .DW ( DW )
    ) u_fifoa (
        .WClk      ( wclk                ),
        .WRstN     ( wreset_n            ),
        .RClk      ( rclk                ),
        .RRstN     ( rreset_n            ),
        .Read      ( re                  ),
        .Write     ( we                  ),
        .EmptyN    ( EmptyN              ),
        .FullN     ( FullN               ),
        .RFullN(),
        .WData     ( d                   ),
        .RData     ( q                   ),
        .WNum(),
        .RNum(),
        .TEST_MODE ( 1'b0                )
    );
end else if(FPGA_IP==1) begin: ALTERA_AFIFO
    dcfifo u_fifoa 
    (
        .aclr      ( ~wreset_n|~rreset_n ),
        .data      ( d                   ),
        .rdclk     ( rclk                ),
        .rdreq     ( re                  ),
        .wrclk     ( wclk                ),
        .wrreq     ( we                  ),
        .q         ( q                   ),
        .rdempty   ( rempty              ),
        .wrfull    ( wfull               ),
        .eccstatus (),
        .rdfull (),
        .rdusedw (),
        .wrempty (),
        .wrusedw ()
    );
    defparam
        u_fifoa.intended_device_family = "Cyclone V",
        u_fifoa.lpm_numwords = 2**AW,
        u_fifoa.lpm_showahead = "ON",
        u_fifoa.lpm_type = "dcfifo",
        u_fifoa.lpm_width = DW,
        u_fifoa.lpm_widthu = AW,
        u_fifoa.overflow_checking = "ON",
        u_fifoa.rdsync_delaypipe = 5,
        u_fifoa.read_aclr_synch = "ON",
        u_fifoa.underflow_checking = "ON",
        u_fifoa.use_eab = "ON",
        u_fifoa.write_aclr_synch = "ON",
        u_fifoa.wrsync_delaypipe = 5;
end endgenerate
endmodule

