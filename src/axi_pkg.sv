`ifndef AXI_PKG_SV
`define AXI_PKG_SV

package axi_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;

  // -------------------------------------------------------------------------
  // src/ -- core VIP components (dependency order)
  // -------------------------------------------------------------------------
  `include "axi_bp_config.sv"
  `include "axi_master_config.sv"
  `include "axi_slave_config.sv"
  `include "axi_config.sv"
  `include "axi_channel_records.sv"
  `include "axi_seq_item.sv"
  `include "axi_ref_model.sv"
  `include "axi_bp_generator.sv"
  `include "axi_bw_limiter.sv"
  `include "axi_master_sequencer.sv"
  `include "axi_master_monitor.sv"
  `include "axi_master_driver.sv"
  `include "axi_master_agent.sv"
  `include "axi_slave_sequencer.sv"
  `include "axi_slave_monitor.sv"
  `include "axi_slave_driver.sv"
  `include "axi_slave_agent.sv"
  `include "axi_scoreboard.sv"
  `include "axi_coverage.sv"
  `include "axi_perf_monitor.sv"
  `include "axi_env.sv"

  // -------------------------------------------------------------------------
  // seq_lib/ -- base and advanced sequences
  // -------------------------------------------------------------------------
  `include "axi_base_seq.sv"
  `include "axi_single_rw_seq.sv"
  `include "axi_burst_seq.sv"
  `include "axi_b2b_seq.sv"
  `include "axi_narrow_seq.sv"
  `include "axi_unaligned_seq.sv"
  `include "axi_exclusive_seq.sv"
  `include "axi_wrap_burst_seq.sv"
  `include "axi_outstanding_seq.sv"
  `include "axi_random_stress_seq.sv"

  // -------------------------------------------------------------------------
  // error_inject/ -- error injection sequences
  // -------------------------------------------------------------------------
  `include "axi_err_seq_item.sv"
  `include "axi_err_resp_seq.sv"
  `include "axi_err_timeout_seq.sv"
  `include "axi_err_data_corrupt_seq.sv"

  // -------------------------------------------------------------------------
  // test/ -- test classes (must come last)
  // -------------------------------------------------------------------------
  `include "axi_base_test.sv"
  `include "axi_agent_topology_test.sv"
  `include "axi_config_validation_test.sv"
  `include "axi_response_lifecycle_test.sv"
  `include "axi_smoke_test.sv"
  `include "axi_rw_test.sv"
  `include "axi_perf_test.sv"
  `include "axi_bp_test.sv"
  `include "axi_mass_rw_test.sv"
  `include "axi_perf_stats_test.sv"
  `include "axi_bw_limit_test.sv"
  `include "axi_outstanding_limit_test.sv"
  `include "axi_high_traffic_test.sv"

endpackage

`endif // AXI_PKG_SV
