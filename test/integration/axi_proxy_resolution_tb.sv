// Desired proxy API: the public bus becomes Z from the VIP while unclaimed,
// and resolves X when a claimed VIP drive conflicts with the DUT.
module axi_proxy_resolution_dut_master (
  input  wire drive_value,
  output wire awvalid
);
  assign awvalid = drive_value;
endmodule

module axi_proxy_resolution_dut_slave (
  output wire awready
);
  assign awready = 1'b1;
endmodule

module axi_proxy_resolution_master_modport (
  axi_if.master_mp bus_if
);
  task automatic claim_drive();
    bus_if.claim_master_drive();
  endtask

  task automatic release_drive();
    bus_if.release_master_drive();
  endtask

  task automatic drive_awvalid(input logic value);
    @(posedge bus_if.aclk);
    bus_if.master_cb.awvalid <= value;
  endtask
endmodule

module axi_proxy_resolution_slave_modport (
  axi_if.slave_mp bus_if
);
  task automatic claim_drive();
    bus_if.claim_slave_drive();
  endtask

  task automatic release_drive();
    bus_if.release_slave_drive();
  endtask

  task automatic drive_awready(input logic value);
    @(posedge bus_if.aclk);
    bus_if.slave_cb.awready <= value;
  endtask
endmodule

module axi_proxy_resolution_tb;
  logic aclk        = 1'b0;
  logic aresetn     = 1'b1;
  logic dut_awvalid = 1'b0;

  axi_if bus_if (.aclk(aclk), .aresetn(aresetn));

  axi_proxy_resolution_dut_master dut_master (
    .drive_value(dut_awvalid),
    .awvalid(bus_if.awvalid)
  );

  axi_proxy_resolution_dut_slave dut_slave (
    .awready(bus_if.awready)
  );

  axi_proxy_resolution_master_modport master_user (bus_if);
  axi_proxy_resolution_slave_modport slave_user (bus_if);

  always #5 aclk = ~aclk;

  initial begin
    #1;
    if (bus_if.awvalid !== 1'b0)
      $fatal(1, "Expected DUT awvalid drive to reach the public bus");
    if (bus_if.awready !== 1'b1)
      $fatal(1, "Expected DUT awready drive to reach the public bus");

    master_user.claim_drive();
    master_user.drive_awvalid(1'b1);
    #2;
    if (bus_if.awvalid !== 1'bx)
      $fatal(1, "Expected conflicting DUT and VIP drives to resolve to X");

    master_user.release_drive();
    #1;
    if (bus_if.awvalid !== 1'b0)
      $fatal(1, "Expected releasing VIP drive to restore DUT awvalid");

    slave_user.claim_drive();
    slave_user.drive_awready(1'b0);
    #2;
    if (bus_if.awready !== 1'bx)
      $fatal(1, "Expected Slave modport claim to expose a conflict");
    slave_user.release_drive();
    #1;
    if (bus_if.awready !== 1'b1)
      $fatal(1, "Expected Slave modport release to restore DUT awready");

    $display("AXI_STATIC_DRIVER_PROXY_PASS");
    $finish;
  end
endmodule
