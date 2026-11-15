// checker/axi_checker_bind.sv
// Non-intrusive bind: attaches axi_protocol_checker to every axi_if instance.
// Compile alongside rtl/axi_if.sv; no modification to axi_if is required.
`ifndef AXI_CHECKER_BIND_SV
`define AXI_CHECKER_BIND_SV

bind axi_if axi_protocol_checker #(
  .DATA_WIDTH (DATA_WIDTH),
  .ADDR_WIDTH (ADDR_WIDTH),
  .ID_WIDTH   (ID_WIDTH),
  .USER_WIDTH (USER_WIDTH)
) u_axi_protocol_checker (
  .aclk     (aclk),
  .aresetn  (aresetn),

  // Write Address Channel
  .awid     (awid),
  .awaddr   (awaddr),
  .awlen    (awlen),
  .awsize   (awsize),
  .awburst  (awburst),
  .awlock   (awlock),
  .awcache  (awcache),
  .awprot   (awprot),
  .awqos    (awqos),
  .awregion (awregion),
  .awvalid  (awvalid),
  .awready  (awready),

  // Write Data Channel
  .wdata    (wdata),
  .wstrb    (wstrb),
  .wlast    (wlast),
  .wvalid   (wvalid),
  .wready   (wready),

  // Write Response Channel
  .bid      (bid),
  .bresp    (bresp),
  .bvalid   (bvalid),
  .bready   (bready),

  // Read Address Channel
  .arid     (arid),
  .araddr   (araddr),
  .arlen    (arlen),
  .arsize   (arsize),
  .arburst  (arburst),
  .arlock   (arlock),
  .arcache  (arcache),
  .arprot   (arprot),
  .arqos    (arqos),
  .arregion (arregion),
  .arvalid  (arvalid),
  .arready  (arready),

  // Read Data Channel
  .rid      (rid),
  .rdata    (rdata),
  .rresp    (rresp),
  .rlast    (rlast),
  .rvalid   (rvalid),
  .rready   (rready)
);

`endif // AXI_CHECKER_BIND_SV
