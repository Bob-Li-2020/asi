// input: axi slave interface output(128-bit data)
// output: register configure(32-bit data)

module asi_reg32 
#(
    AXI_SW     = 3,
    AXI_AW     = 32,
    AXI_DW     = 128,
    AXI_WSTRBW = AXI_DW/8,
    REG_AW     = 20,
    REG_DW     = 32,
    REG_WSTRBW = REG_DW/8,
    M          = $clog2(AXI_DW/REG_DW),
    L          = $clog2(REG_DW/8)
)(
    input  logic                    rst_n    ,
    input  logic                    clk      ,
    //--------- ASI WRITE --------------------
    input  logic [AXI_SW-1     : 0] s_wsize  ,
    input  logic [AXI_AW-1     : 0] s_waddr  ,
    input  logic [AXI_DW-1     : 0] s_wdata  ,
    input  logic [AXI_WSTRBW-1 : 0] s_wstrb  ,
    input  logic                    s_wlast  ,
    input  logic                    s_wvalid ,
    output logic                    s_wready ,
    //--------- REG WRITE --------------------
    output logic [AXI_SW-1     : 0] m_wsize  ,
    output logic [REG_AW-1     : L] m_waddr  ,
    output logic [REG_DW-1     : 0] m_wdata  ,
    output logic [REG_WSTRBW-1 : 0] m_wstrb  ,
    output logic                    m_wlast  ,
    output logic                    m_wvalid ,
    input  logic                    m_wready ,
    //--------- ASI READ ---------------------
    input  logic [AXI_SW-1     : 0] s_rsize  ,
    input  logic [AXI_AW-1     : 0] s_raddr  ,
    input  logic                    s_rvalid ,
    output logic [AXI_DW-1     : 0] s_rdata  ,
    output logic                    s_rready ,
    output logic                    s_slverr ,
    //--------- REG READ ---------------------
    output logic [AXI_SW-1     : 0] m_rsize  ,
    output logic [REG_AW-1     : L] m_raddr  ,
    output logic                    m_rvalid ,
    input  logic [REG_DW-1     : 0] m_rdata  ,
    input  logic                    m_rready 
);

//------------------------------------
//-------- REG WRITE/READ SIGNALS ----
//------------------------------------
logic [AXI_AW-1 : L] s_waddr_aligned ; // waddress aligned to 32-bits(4bytes)
logic [AXI_AW-1 : L] s_raddr_aligned ; // raddress aligned to 32-bits(4bytes)
logic [M-1      : 0] wbls            ; // Write Byte Lane Select
logic [M-1      : 0] rbls            ; // Read  Byte Lane Select
//------------------------------------
//-------- OUTPUT ASSIGN -------------
//------------------------------------
//--write
assign m_wsize         = s_wsize            ;
assign m_waddr         = s_waddr_aligned[L +: (REG_AW-L)];
assign m_wlast         = s_wlast            ;
assign m_wvalid        = s_wvalid           ;
assign s_wready        = m_wready           ;
assign s_waddr_aligned = s_waddr[AXI_AW-1:L];
assign wbls            = s_waddr_aligned[L +: M];
//--read
assign m_rsize         = s_rsize            ;
assign m_raddr         = s_raddr_aligned[L +: (REG_AW-L)];
assign s_rvalid        = s_rvalid           ;
assign s_rready        = m_rready           ;
assign s_slverr        = (s_wsize != L && s_wvalid & s_wready) || (s_rsize != L && s_rvalid & s_rready);
assign s_raddr_aligned = s_raddr[AXI_AW-1:L];
assign rbls            = s_raddr_aligned[L +: M];
//------------------------------------
//-------- ADDR CALCULATION ----------
//------------------------------------
//--write
always_comb begin
    m_wdata = s_wdata[0 +: REG_DW];
    m_wstrb = s_wstrb[0 +: REG_WSTRBW];
    for(int i=0;i<2**M;i++) begin
        if(i==wbls) begin
            m_wdata = s_wdata[i*REG_DW +: REG_DW];
            m_wstrb = s_wstrb[i*REG_WSTRBW +: REG_WSTRBW];
        end
    end
end
//--read
always_comb begin
    s_rdata = s_rdata;
    for(int i=0;i<2**M;i++) begin
        if(i==rbls) begin
            s_rdata[i*REG_DW +: REG_DW] = m_rdata;
        end
    end
end
    
endmodule

