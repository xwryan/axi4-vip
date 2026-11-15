// Compile-only probe: a real DUT must be able to drive an AXI interface signal
// while the VIP clocking block owns the same direction.
module axi_probe_dut_slave (
  input  wire awvalid,
  output wire awready
);
  assign awready = awvalid;
endmodule

module axi_probe_dut_master (
  output wire awvalid,
  input  wire awready
);
  assign awvalid = awready;
endmodule

module axi_real_dut_compile_probe;
  logic aclk    = 1'b0;
  logic aresetn = 1'b0;

  axi_if vip_master_if (.aclk(aclk), .aresetn(aresetn));
  axi_if vip_slave_if  (.aclk(aclk), .aresetn(aresetn));

  axi_probe_dut_slave dut_slave (
    .awvalid(vip_master_if.awvalid),
    .awready(vip_master_if.awready)
  );

  axi_probe_dut_master dut_master (
    .awvalid(vip_slave_if.awvalid),
    .awready(vip_slave_if.awready)
  );
endmodule
