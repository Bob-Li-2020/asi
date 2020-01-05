module tb;
timeunit 1ns;
timeprecision 1ps;
`define PSESUDO_WIRE_DELAY 1ps
import axi_pkg::*;
import asi_pkg::*;
//---- AXI GLOBAL SIGNALS ------------
bit                      ACLK        ;
bit                      ARESETn=1'b1;
//---- AXI ADDRESS WRITE SIGNALS -----
logic [AXI_IW-1     : 0] AWID        ;
logic [AXI_AW-1     : 0] AWADDR      ;
logic [AXI_LW-1     : 0] AWLEN       ;
logic [AXI_SW-1     : 0] AWSIZE      ;
logic [AXI_BURSTW-1 : 0] AWBURST     ;
logic                    AWVALID     ;
logic                    AWREADY     ;
logic [3            : 0] AWCACHE     ;// NO LOADS
logic [2            : 0] AWPROT      ;// NO LOADS
logic [3            : 0] AWQOS       ;// NO LOADS
logic [3            : 0] AWREGION    ;// NO LOADS
//---- AXI DATA WRITE SIGNALS --------
logic [AXI_DW-1     : 0] WDATA       ;
logic [AXI_WSTRBW-1 : 0] WSTRB       ;
logic                    WLAST       ;
logic                    WVALID      ;
logic                    WREADY      ;
//---- AXI WRITE RESPONSE SIGNALS ----
logic [AXI_IW-1     : 0] BID         ;
logic [AXI_BRESPW-1  : 0] BRESP       ;
logic                    BVALID      ;
logic                    BREADY      ;
//---- READ ADDRESS CHANNEL ----------
logic [AXI_IW-1     : 0] ARID        ;
logic [AXI_AW-1     : 0] ARADDR      ;
logic [AXI_LW-1     : 0] ARLEN       ;
logic [AXI_SW-1     : 0] ARSIZE      ;
logic [AXI_BURSTW-1 : 0] ARBURST     ;
logic                    ARVALID     ;
logic                    ARREADY     ;
logic [3            : 0] ARCACHE     ;// NO LOADS 
logic [2            : 0] ARPROT      ;// NO LOADS 
logic [3            : 0] ARQOS       ;// NO LOADS 
logic [3            : 0] ARREGION    ;// NO LOADS
//---- READ DATA CHANNEL -------------
logic [AXI_IW-1     : 0] RID         ;
logic [AXI_DW-1     : 0] RDATA       ;
logic [AXI_RRESPW-1  : 0] RRESP       ;
logic                    RLAST       ;
logic                    RVALID      ;
logic                    RREADY      ;

axi_master_model axim ( 
    .* 
);

axi_slave DUT ( 
    .*
);

always #(AXI_CLKT/2) ACLK++;
task AXI_RESET;
    ARESETn=1'b0;
    #15;
    ARESETn=1'b1;
    #15;
endtask
initial begin
    $timeformat(-9, 5, "ns", 10);
    show_sim_features;
    AXI_RESET;
end


//------ test
//int rdata_n;
//always_ff @(posedge ACLK)
//    if(RVALID & RREADY)
//        $display("%0t: rdata_n = %0d; RDATA = %h; *tb*", $realtime, ++rdata_n, RDATA);
endmodule
