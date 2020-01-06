package axi_pkg;
    import asi_pkg::*;
    export asi_pkg::*;
    localparam AXI_VERSION = 3; // AXI4
    localparam [AXI_BRESPW-1  : 0] BRESP_OKAY   = AXI_BRESPW'(0);
    localparam [AXI_BRESPW-1  : 0] BRESP_EXOKAY = AXI_BRESPW'(1);
    localparam [AXI_BRESPW-1  : 0] BRESP_SLVERR = AXI_BRESPW'(2);
    localparam [AXI_BRESPW-1  : 0] BRESP_DECERR = AXI_BRESPW'(3);
    // SLV ADDRESS RANGE
    localparam SLV_AW=10;
    // ASI PERFORMANCE CONTROL
    localparam 
               
               
              
               
               RLAST_EN=1,
               WLAST_EN=1;
    // AXI DERIVED PARAMETERS
    localparam AXI_BYTES = AXI_DW/8,
               AXI_MAXLEN = AXI_VERSION==3 ? 15 : 255;
    // AXI CLK PARAMETERS
    localparam AXI_CLKT = 2.4; // ACLK period
    // USR CLK PARAMETERS
    localparam USR_CLKT = 2;
    // AXI SIM PARAMETERS
    localparam WSTRB_EN=1,  // WSTRB ENABLE
               NARROW_EN=1, // NARROW TRANSFER ENABLE
               RAN_SIZE=1;  // RANDOM SIZE ENABLE

    function void show_sim_features;
        $display("##############################################");
        $display("######### SIM FEATURES #######################");
        $display("##############################################");
        $display("###### WSTRB_EN  = %0d", WSTRB_EN);
        $display("###### NARROW_EN = %0d", NARROW_EN);
        $display("###### RAN_SIZE  = %0d", RAN_SIZE);
        $display("###### SLV_WS    = %0d", SLV_WS);
    endfunction
    class Wtransactions; // AXI write transactions
        //---- AXI ADDRESS WRITE SIGNALS ------------
        rand logic [AXI_IW-1     : 0] AWID        ;
        rand logic [AXI_AW-1     : 0] AWADDR      ;
        rand logic [AXI_LW-1     : 0] AWLEN       ;
        rand logic [AXI_SW-1     : 0] AWSIZE      ;
        logic [AXI_BURSTW-1 : 0] AWBURST     ; // CONST 
        logic                    AWVALID     ;
        logic                    AWREADY     ;
        logic [3            : 0] AWCACHE     ; // NOT USED 
        logic [2            : 0] AWPROT      ; // NOT USED 
        logic [3            : 0] AWQOS       ; // NOT USED 
        logic [3            : 0] AWREGION    ; // NOT USED 
        //---- AXI DATA WRITE SIGNALS ---------------
        logic [AXI_DW-1     : 0] WDATA[$]    ;
        logic [AXI_WSTRBW-1 : 0] WSTRB[$]    ;
        logic                    WLAST       ;
        logic                    WVALID      ;
        logic                    WREADY      ;
        //---- AXI WRITE RESPONSE SIGNALS -----------
        logic [AXI_IW-1     : 0] BID         ;
        logic [AXI_BRESPW-1  : 0] BRESP       ;
        logic                    BVALID      ;
        logic                    BREADY      ;
        //---- RANDOMIZE CONTROL -------------------
        bit RAN_DATA; // 1~random wdata; 0~ordinal number wdata
        //---- TRANSACTION COUNTING ----------------
        static int wtn;
        constraint c1_addr { AWADDR>=0; AWADDR<2**SLV_AW; }
        constraint c2_len  { AWLEN>=0 ; AWLEN<=AXI_MAXLEN; }
        constraint c3_size { AWSIZE>=0; AWSIZE<=$clog2(AXI_BYTES); }
        constraint c1_narrow { if(!NARROW_EN) (AWADDR%(2**AWSIZE))==0; }
        constraint c3_ransiz { if(!RAN_SIZE) AWSIZE==$clog2(AXI_BYTES); }
        function void show_aw; // show AXI transaction AW info
            //$display("transaction %0d: ", wtn);
            $display("AWID   = 0x%h", AWID);
            $display("AWADDR = 0x%h", AWADDR);
            $display("AWLEN  = %0d", AWLEN);
            $display("AWSIZE = %0d", AWSIZE);
        endfunction
        function void show_w; // show AXI transaction W 
            assert(WDATA.size==WSTRB.size) else begin $error("WDATA.size=%0d; WSTRB.size=%0d", WDATA.size, WSTRB.size); $finish; end
            foreach(WDATA[i]) begin
                $display("WDATA[%0d] = %h", i, WDATA[i]);
                $display("WSTRB[%0d] = %b", i, WSTRB[i]);
            end
        endfunction
        function new(input bit RAN_DATA);
            this.RAN_DATA = RAN_DATA;
            AWBURST  = BT_INCR;
            AWCACHE  = 4'b0001; // NOT USED 
            AWPROT   = 3'b000 ; // NOT USED
            AWQOS    = 4'b0000; // NOT USED
            AWREGION = 4'b0000; // NOT USED
            wtn++;
        endfunction
        function void post_randomize;
            gen_wdata;
            //show_aw;
            //show_w;
        endfunction
        function void gen_wdata; // generate WDATA and WSTRB
            int start_addr; // address for the 1st transfer
            int aligned_address; // start_addr aligned to AXSIZE
            int address_n; // address for the rest transfer(if any)
            int number_bytes;
            int lower_byte_lane;
            int upper_byte_lane;
            int data_bytes;
            bit aligned;
            logic [AXI_DW-1:0] data;
            logic [AXI_WSTRBW-1:0] data_wstrb;
            number_bytes = 2**AWSIZE;
            start_addr = AWADDR;
            aligned_address = start_addr/number_bytes*number_bytes;
            aligned = aligned_address==start_addr;
            for(int i=0;i<=AWLEN;i++) begin
                lower_byte_lane = start_addr-start_addr/AXI_BYTES*AXI_BYTES;
                if(aligned)
                    upper_byte_lane = lower_byte_lane+number_bytes-1;
                else
                    upper_byte_lane = aligned_address+number_bytes-1-start_addr/AXI_BYTES*AXI_BYTES;
                //$display("lower_byte_lane = %0d", lower_byte_lane);
                //$display("upper_byte_lane = %0d", upper_byte_lane);
                for(int j=0; j<AXI_BYTES; j++) begin
                    if(j>=lower_byte_lane && j<=upper_byte_lane) begin
                        data[j*8 +: 8] = RAN_DATA ? $urandom_range(0, 2**8-1) : i[j*8 +: 8];
                        if(WSTRB_EN) begin
                            data_wstrb[j] = $urandom_range(0,1);
                            if(data_wstrb[j]==0)
                                data_wstrb[j] = $random();
                        end
                        else begin
                            data_wstrb[j] = 1'b1;
                        end
                    end else begin
                        data[j*8 +: 8] = 'x;
                        data_wstrb[j] = '0;
                    end
                end
                //$display("%0d: data_wstrb = %b", i, data_wstrb);
                WDATA.push_back(data);
                WSTRB.push_back(data_wstrb);
                if(aligned)
                    start_addr = start_addr+number_bytes;
                else
                    start_addr = aligned_address+number_bytes;
                aligned = 1'b1;
            end
        endfunction
    endclass
    class Rtransactions; // read transactions
        //---- READ ADDRESS CHANNEL -----------------
        rand logic [AXI_IW-1     : 0] ARID        ;
        rand logic [AXI_AW-1     : 0] ARADDR      ;
        rand logic [AXI_LW-1     : 0] ARLEN       ;
        rand logic [AXI_SW-1     : 0] ARSIZE      ;
        logic [AXI_BURSTW-1 : 0] ARBURST     ; // CONST
        logic                    ARVALID     ;
        logic                    ARREADY     ;
        logic [3            : 0] ARCACHE     ; // NOT USED 
        logic [2            : 0] ARPROT      ; // NOT USED 
        logic [3            : 0] ARQOS       ; // NOT USED 
        logic [3            : 0] ARREGION    ; // NOT USED
        //---- READ DATA CHANNEL --------------------
        logic [AXI_IW-1     : 0] RID[$]      ;
        logic [AXI_DW-1     : 0] RDATA[$]    ;
        logic [AXI_RRESPW-1  : 0] RRESP[$]    ;
        logic                    RLAST       ;
        logic                    RVALID      ;
        logic                    RREADY      ;
        function new;
            ARBURST  = BT_INCR;
            ARCACHE  = 4'b0001; // NOT USED 
            ARPROT   = 3'b000 ; // NOT USED
            ARQOS    = 4'b0000; // NOT USED
            ARREGION = 4'b0000; // NOT USED
        endfunction
        function void show_ar; // show AXI transaction AR info
            $display("ARID   = 0x%h", ARID);
            $display("ARADDR = 0x%h", ARADDR);
            $display("ARLEN  = %0d",  ARLEN);
            $display("ARSIZE = %0d",  ARSIZE);
        endfunction
    endclass

endpackage
