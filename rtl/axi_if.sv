// rtl/axi_if.sv
`ifndef AXI_IF_SV
`define AXI_IF_SV

interface axi_if #(
  parameter int DATA_WIDTH = 64,
  parameter int ADDR_WIDTH = 32,
  parameter int ID_WIDTH   = 4,
  parameter int USER_WIDTH = 0
)(
  input logic aclk,
  input logic aresetn
);

  localparam int STRB_WIDTH = DATA_WIDTH / 8;

  // Write Address Channel (AW)
  wire logic [ID_WIDTH-1:0]   awid;
  wire logic [ADDR_WIDTH-1:0] awaddr;
  wire logic [7:0]            awlen;
  wire logic [2:0]            awsize;
  wire logic [1:0]            awburst;
  wire logic                  awlock;
  wire logic [3:0]            awcache;
  wire logic [2:0]            awprot;
  wire logic [3:0]            awqos;
  wire logic [3:0]            awregion;
  wire logic                  awvalid;
  wire logic                  awready;

  // Write Data Channel (W)
  wire logic [DATA_WIDTH-1:0] wdata;
  wire logic [STRB_WIDTH-1:0] wstrb;
  wire logic                  wlast;
  wire logic                  wvalid;
  wire logic                  wready;

  // Write Response Channel (B)
  wire logic [ID_WIDTH-1:0] bid;
  wire logic [1:0]          bresp;
  wire logic                bvalid;
  wire logic                bready;

  // Read Address Channel (AR)
  wire logic [ID_WIDTH-1:0]   arid;
  wire logic [ADDR_WIDTH-1:0] araddr;
  wire logic [7:0]            arlen;
  wire logic [2:0]            arsize;
  wire logic [1:0]            arburst;
  wire logic                  arlock;
  wire logic [3:0]            arcache;
  wire logic [2:0]            arprot;
  wire logic [3:0]            arqos;
  wire logic [3:0]            arregion;
  wire logic                  arvalid;
  wire logic                  arready;

  // Read Data Channel (R)
  wire logic [ID_WIDTH-1:0]   rid;
  wire logic [DATA_WIDTH-1:0] rdata;
  wire logic [1:0]            rresp;
  wire logic                  rlast;
  wire logic                  rvalid;
  wire logic                  rready;

  bit master_drive_enabled = 1'b0;
  bit slave_drive_enabled = 1'b0;

  logic [ID_WIDTH-1:0]   master_awid = '0;
  logic [ADDR_WIDTH-1:0] master_awaddr = '0;
  logic [7:0]            master_awlen = '0;
  logic [2:0]            master_awsize = '0;
  logic [1:0]            master_awburst = '0;
  logic                  master_awlock = '0;
  logic [3:0]            master_awcache = '0;
  logic [2:0]            master_awprot = '0;
  logic [3:0]            master_awqos = '0;
  logic [3:0]            master_awregion = '0;
  logic                  master_awvalid = '0;
  logic [DATA_WIDTH-1:0] master_wdata = '0;
  logic [STRB_WIDTH-1:0] master_wstrb = '0;
  logic                  master_wlast = '0;
  logic                  master_wvalid = '0;
  logic                  master_bready = '0;
  logic [ID_WIDTH-1:0]   master_arid = '0;
  logic [ADDR_WIDTH-1:0] master_araddr = '0;
  logic [7:0]            master_arlen = '0;
  logic [2:0]            master_arsize = '0;
  logic [1:0]            master_arburst = '0;
  logic                  master_arlock = '0;
  logic [3:0]            master_arcache = '0;
  logic [2:0]            master_arprot = '0;
  logic [3:0]            master_arqos = '0;
  logic [3:0]            master_arregion = '0;
  logic                  master_arvalid = '0;
  logic                  master_rready = '0;

  logic                  slave_awready = '0;
  logic                  slave_wready = '0;
  logic [ID_WIDTH-1:0]   slave_bid = '0;
  logic [1:0]            slave_bresp = '0;
  logic                  slave_bvalid = '0;
  logic                  slave_arready = '0;
  logic [ID_WIDTH-1:0]   slave_rid = '0;
  logic [DATA_WIDTH-1:0] slave_rdata = '0;
  logic [1:0]            slave_rresp = '0;
  logic                  slave_rlast = '0;
  logic                  slave_rvalid = '0;

  assign awid = master_drive_enabled ? master_awid : 'z;
  assign awaddr = master_drive_enabled ? master_awaddr : 'z;
  assign awlen = master_drive_enabled ? master_awlen : 'z;
  assign awsize = master_drive_enabled ? master_awsize : 'z;
  assign awburst = master_drive_enabled ? master_awburst : 'z;
  assign awlock = master_drive_enabled ? master_awlock : 'z;
  assign awcache = master_drive_enabled ? master_awcache : 'z;
  assign awprot = master_drive_enabled ? master_awprot : 'z;
  assign awqos = master_drive_enabled ? master_awqos : 'z;
  assign awregion = master_drive_enabled ? master_awregion : 'z;
  assign awvalid = master_drive_enabled ? master_awvalid : 'z;
  assign wdata = master_drive_enabled ? master_wdata : 'z;
  assign wstrb = master_drive_enabled ? master_wstrb : 'z;
  assign wlast = master_drive_enabled ? master_wlast : 'z;
  assign wvalid = master_drive_enabled ? master_wvalid : 'z;
  assign bready = master_drive_enabled ? master_bready : 'z;
  assign arid = master_drive_enabled ? master_arid : 'z;
  assign araddr = master_drive_enabled ? master_araddr : 'z;
  assign arlen = master_drive_enabled ? master_arlen : 'z;
  assign arsize = master_drive_enabled ? master_arsize : 'z;
  assign arburst = master_drive_enabled ? master_arburst : 'z;
  assign arlock = master_drive_enabled ? master_arlock : 'z;
  assign arcache = master_drive_enabled ? master_arcache : 'z;
  assign arprot = master_drive_enabled ? master_arprot : 'z;
  assign arqos = master_drive_enabled ? master_arqos : 'z;
  assign arregion = master_drive_enabled ? master_arregion : 'z;
  assign arvalid = master_drive_enabled ? master_arvalid : 'z;
  assign rready = master_drive_enabled ? master_rready : 'z;

  assign awready = slave_drive_enabled ? slave_awready : 'z;
  assign wready = slave_drive_enabled ? slave_wready : 'z;
  assign bid = slave_drive_enabled ? slave_bid : 'z;
  assign bresp = slave_drive_enabled ? slave_bresp : 'z;
  assign bvalid = slave_drive_enabled ? slave_bvalid : 'z;
  assign arready = slave_drive_enabled ? slave_arready : 'z;
  assign rid = slave_drive_enabled ? slave_rid : 'z;
  assign rdata = slave_drive_enabled ? slave_rdata : 'z;
  assign rresp = slave_drive_enabled ? slave_rresp : 'z;
  assign rlast = slave_drive_enabled ? slave_rlast : 'z;
  assign rvalid = slave_drive_enabled ? slave_rvalid : 'z;

  // Optional User signals
  generate
    if (USER_WIDTH > 0) begin : gen_user
      logic [USER_WIDTH-1:0] awuser;
      logic [USER_WIDTH-1:0] wuser;
      logic [USER_WIDTH-1:0] buser;
      logic [USER_WIDTH-1:0] aruser;
      logic [USER_WIDTH-1:0] ruser;
    end
  endgenerate

  // ===== Clocking Blocks =====

  clocking master_cb @(posedge aclk);
    default input #1step output #1;
    output awid = master_awid, awaddr = master_awaddr,
           awlen = master_awlen, awsize = master_awsize,
           awburst = master_awburst, awlock = master_awlock,
           awcache = master_awcache, awprot = master_awprot,
           awqos = master_awqos, awregion = master_awregion,
           awvalid = master_awvalid;
    input  awready;
    output wdata = master_wdata, wstrb = master_wstrb,
           wlast = master_wlast, wvalid = master_wvalid;
    input  wready;
    input  bid, bresp, bvalid;
    output bready = master_bready;
    output arid = master_arid, araddr = master_araddr,
           arlen = master_arlen, arsize = master_arsize,
           arburst = master_arburst, arlock = master_arlock,
           arcache = master_arcache, arprot = master_arprot,
           arqos = master_arqos, arregion = master_arregion,
           arvalid = master_arvalid;
    input  arready;
    input  rid, rdata, rresp, rlast, rvalid;
    output rready = master_rready;
  endclocking

  clocking slave_cb @(posedge aclk);
    default input #1step output #1;
    input  awid, awaddr, awlen, awsize, awburst, awlock,
           awcache, awprot, awqos, awregion, awvalid;
    output awready = slave_awready;
    input  wdata, wstrb, wlast, wvalid;
    output wready = slave_wready;
    output bid = slave_bid, bresp = slave_bresp, bvalid = slave_bvalid;
    input  bready;
    input  arid, araddr, arlen, arsize, arburst, arlock,
           arcache, arprot, arqos, arregion, arvalid;
    output arready = slave_arready;
    output rid = slave_rid, rdata = slave_rdata, rresp = slave_rresp,
           rlast = slave_rlast, rvalid = slave_rvalid;
    input  rready;
  endclocking

  clocking monitor_cb @(posedge aclk);
    default input #1step;
    input awid, awaddr, awlen, awsize, awburst, awlock,
          awcache, awprot, awqos, awregion, awvalid, awready;
    input wdata, wstrb, wlast, wvalid, wready;
    input bid, bresp, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arlock,
          arcache, arprot, arqos, arregion, arvalid, arready;
    input rid, rdata, rresp, rlast, rvalid, rready;
  endclocking

  // ===== Modports =====

  modport master_mp  (clocking master_cb, input aclk, aresetn,
                      import task claim_master_drive(),
                      import task release_master_drive());
  modport slave_mp   (clocking slave_cb, input aclk, aresetn,
                      import task claim_slave_drive(),
                      import task release_slave_drive());
  modport monitor_mp (clocking monitor_cb, input aclk, aresetn);

  // ===== Reset tasks =====

  task automatic wait_for_reset();
    @(posedge aresetn);
    @(posedge aclk);
  endtask

  task automatic reset_master_signals();
    master_awid = '0;
    master_awaddr = '0;
    master_awlen = '0;
    master_awsize = '0;
    master_awburst = '0;
    master_awlock = '0;
    master_awcache = '0;
    master_awprot = '0;
    master_awqos = '0;
    master_awregion = '0;
    master_awvalid = '0;
    master_wdata = '0;
    master_wstrb = '0;
    master_wlast = '0;
    master_wvalid = '0;
    master_bready = '0;
    master_arid = '0;
    master_araddr = '0;
    master_arlen = '0;
    master_arsize = '0;
    master_arburst = '0;
    master_arlock = '0;
    master_arcache = '0;
    master_arprot = '0;
    master_arqos = '0;
    master_arregion = '0;
    master_arvalid = '0;
    master_rready = '0;
  endtask

  task automatic reset_slave_signals();
    slave_awready = '0;
    slave_wready = '0;
    slave_bid = '0;
    slave_bresp = '0;
    slave_bvalid = '0;
    slave_arready = '0;
    slave_rid = '0;
    slave_rdata = '0;
    slave_rresp = '0;
    slave_rlast = '0;
    slave_rvalid = '0;
  endtask

  task automatic claim_master_drive();
    reset_master_signals();
    master_drive_enabled = 1'b1;
  endtask

  task automatic release_master_drive();
    master_drive_enabled = 1'b0;
    reset_master_signals();
  endtask

  task automatic claim_slave_drive();
    reset_slave_signals();
    slave_drive_enabled = 1'b1;
  endtask

  task automatic release_slave_drive();
    slave_drive_enabled = 1'b0;
    reset_slave_signals();
  endtask

endinterface

`endif // AXI_IF_SV
