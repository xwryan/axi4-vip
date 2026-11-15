// test/tb_top.sv
`ifndef TB_TOP_SV
`define TB_TOP_SV

// Testbench top module.
// Instantiates the AXI interface, generates clock and reset, publishes
// the virtual interface handle via uvm_config_db, imports the AXI package,
// and kicks off UVM with run_test().
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

import axi_pkg::*;

module tb_top;

  // -----------------------------------------------------------------------
  // Parameters -- match the default axi_config values
  // -----------------------------------------------------------------------
  localparam int DATA_WIDTH = 64;
  localparam int ADDR_WIDTH = 32;
  localparam int ID_WIDTH   = 4;
  localparam int USER_WIDTH = 0;

  // -----------------------------------------------------------------------
  // Clock and reset
  // -----------------------------------------------------------------------
  logic aclk;
  logic aresetn;

  // 1.25 ns period -> 800 MHz
  initial aclk = 1'b0;
  always #625ps aclk = ~aclk;

  // Assert reset for 10 cycles, then deassert
  initial begin
    aresetn = 1'b0;
    repeat (10) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;
  end

  // -----------------------------------------------------------------------
  // AXI interface instance
  // -----------------------------------------------------------------------
  axi_if #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .USER_WIDTH (USER_WIDTH)
  ) axi_bus (
    .aclk    (aclk),
    .aresetn (aresetn)
  );

  // -----------------------------------------------------------------------
  // Protocol checker -- directly instantiated (VCS doesn't support bind-to-interface)
  // -----------------------------------------------------------------------
  axi_protocol_checker #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
  ) u_axi_checker (
    .aclk     (aclk),
    .aresetn  (aresetn),
    .awid     (axi_bus.awid),
    .awaddr   (axi_bus.awaddr),
    .awlen    (axi_bus.awlen),
    .awsize   (axi_bus.awsize),
    .awburst  (axi_bus.awburst),
    .awlock   (axi_bus.awlock),
    .awcache  (axi_bus.awcache),
    .awprot   (axi_bus.awprot),
    .awqos    (axi_bus.awqos),
    .awregion (axi_bus.awregion),
    .awvalid  (axi_bus.awvalid),
    .awready  (axi_bus.awready),
    .wdata    (axi_bus.wdata),
    .wstrb    (axi_bus.wstrb),
    .wlast    (axi_bus.wlast),
    .wvalid   (axi_bus.wvalid),
    .wready   (axi_bus.wready),
    .bid      (axi_bus.bid),
    .bresp    (axi_bus.bresp),
    .bvalid   (axi_bus.bvalid),
    .bready   (axi_bus.bready),
    .arid     (axi_bus.arid),
    .araddr   (axi_bus.araddr),
    .arlen    (axi_bus.arlen),
    .arsize   (axi_bus.arsize),
    .arburst  (axi_bus.arburst),
    .arlock   (axi_bus.arlock),
    .arcache  (axi_bus.arcache),
    .arprot   (axi_bus.arprot),
    .arqos    (axi_bus.arqos),
    .arregion (axi_bus.arregion),
    .arvalid  (axi_bus.arvalid),
    .arready  (axi_bus.arready),
    .rid      (axi_bus.rid),
    .rdata    (axi_bus.rdata),
    .rresp    (axi_bus.rresp),
    .rlast    (axi_bus.rlast),
    .rvalid   (axi_bus.rvalid),
    .rready   (axi_bus.rready)
  );

  // -----------------------------------------------------------------------
  // Publish virtual interface to UVM config_db so tests can retrieve it
  // -----------------------------------------------------------------------
  initial begin
    uvm_config_db #(virtual axi_if)::set(
      null,           // context -- null means global (uvm_root)
      "uvm_test_top", // target component path
      "vif",          // field name matched in axi_base_test
      axi_bus
    );
  end

  // -----------------------------------------------------------------------
  // Start UVM -- test name supplied via +UVM_TESTNAME=<test_class>
  // -----------------------------------------------------------------------
  initial begin
    run_test();
  end

endmodule

`endif // TB_TOP_SV
