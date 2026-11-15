`ifndef AXI_CONFIG_VALIDATION_TEST_SV
`define AXI_CONFIG_VALIDATION_TEST_SV

class axi_config_validation_test extends axi_base_test;
  `uvm_component_utils(axi_config_validation_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.has_coverage = 0;
  endfunction

  protected function axi_config make_valid_probe(string name);
    axi_config probe = axi_config::type_id::create(name);
    probe.vif = cfg.vif;
    probe.resolve_agent_configs();
    return probe;
  endfunction

  protected function void expect_valid(axi_config probe, string label);
    string reason;
    if (!probe.validate(reason))
      `uvm_error("CFG_VALIDATE", {label, " rejected: ", reason})
  endfunction

  protected function void expect_invalid(axi_config probe, string label);
    string reason;
    if (probe.validate(reason))
      `uvm_error("CFG_VALIDATE", {label, " was accepted"})
    else if (reason.len() == 0)
      `uvm_error("CFG_VALIDATE", {label, " returned an empty diagnostic"})
  endfunction

  protected function void expect_invalid_reason(
    axi_config probe, string label, string expected_reason);
    string reason;
    if (probe.validate(reason))
      `uvm_error("CFG_VALIDATE", {label, " was accepted"})
    else if (reason != expected_reason)
      `uvm_error("CFG_VALIDATE",
        {label, " returned unexpected diagnostic: ", reason})
  endfunction

  protected function void expect_bp_copy(
    axi_bp_config source, axi_bp_config target, string label);
    if (target == null)
      `uvm_error("CFG_COPY", {label, " target is null"})
    else begin
      if (target == source)
        `uvm_error("CFG_COPY", {label, " aliases its legacy source"})
      if (target.mode                != source.mode ||
          target.fixed_delay         != source.fixed_delay ||
          target.random_ready_pct    != source.random_ready_pct ||
          target.burst_accept_cycles != source.burst_accept_cycles ||
          target.burst_block_cycles  != source.burst_block_cycles ||
          target.on_window           != source.on_window ||
          target.off_window          != source.off_window)
        `uvm_error("CFG_COPY", {label, " values were not copied"})
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_config probe;
    axi_master_config master_sentinel;
    axi_slave_config slave_sentinel;
    axi_bp_config master_global_sentinel;
    axi_bp_config master_b_sentinel;
    axi_bp_config master_r_sentinel;
    axi_bp_config slave_global_sentinel;
    axi_bp_config slave_aw_sentinel;
    axi_bp_config slave_w_sentinel;
    axi_bp_config slave_ar_sentinel;
    phase.raise_objection(this);

    probe = make_valid_probe("valid_defaults");
    expect_valid(probe, "valid defaults");
    if (probe.master_cfg.global_bp_cfg == probe.global_bp_cfg ||
        probe.slave_cfg.global_bp_cfg == probe.global_bp_cfg ||
        probe.master_cfg.global_bp_cfg == probe.slave_cfg.global_bp_cfg)
      `uvm_error("CFG_COPY", "legacy backpressure objects were not deep-copied")

    probe = make_valid_probe("zero_wr_limit");
    probe.master_cfg.max_outstanding_wr = 0;
    expect_invalid(probe, "zero write outstanding limit");

    probe = make_valid_probe("zero_rd_limit");
    probe.master_cfg.max_outstanding_rd = 0;
    expect_invalid(probe, "zero read outstanding limit");

    probe = make_valid_probe("bad_ready_pct");
    probe.slave_cfg.per_channel_bp_enable = 1;
    probe.slave_cfg.aw_bp_cfg.mode = BP_RANDOM;
    probe.slave_cfg.aw_bp_cfg.random_ready_pct = 101;
    expect_invalid(probe, "ready percentage above 100");

    probe = make_valid_probe("bad_burst_window");
    probe.slave_cfg.per_channel_bp_enable = 1;
    probe.slave_cfg.w_bp_cfg.mode = BP_BURST;
    probe.slave_cfg.w_bp_cfg.burst_accept_cycles = 0;
    expect_invalid(probe, "zero burst accept window");

    probe = make_valid_probe("bad_delay");
    probe.slave_cfg.resp_delay_min = 8;
    probe.slave_cfg.resp_delay_max = 7;
    expect_invalid(probe, "reversed response delay");

    probe = make_valid_probe("bad_bw");
    probe.master_cfg.enable_bw_limit = 1;
    probe.master_cfg.max_bytes_per_window = 0;
    expect_invalid(probe, "zero bandwidth allowance");

    probe = make_valid_probe("bad_bw_cycles");
    probe.master_cfg.enable_bw_limit = 1;
    probe.master_cfg.bw_window_cycles = 0;
    expect_invalid(probe, "zero bandwidth window");

    probe = make_valid_probe("bad_burst_block_window");
    probe.slave_cfg.per_channel_bp_enable = 1;
    probe.slave_cfg.aw_bp_cfg.mode = BP_BURST;
    probe.slave_cfg.aw_bp_cfg.burst_block_cycles = 0;
    expect_invalid(probe, "zero burst block window");

    probe = make_valid_probe("bad_intermittent_on_window");
    probe.master_cfg.per_channel_bp_enable = 1;
    probe.master_cfg.r_bp_cfg.mode = BP_INTERMITTENT;
    probe.master_cfg.r_bp_cfg.on_window = 0;
    expect_invalid(probe, "zero intermittent on window");

    probe = make_valid_probe("bad_intermittent_off_window");
    probe.master_cfg.per_channel_bp_enable = 1;
    probe.master_cfg.r_bp_cfg.mode = BP_INTERMITTENT;
    probe.master_cfg.r_bp_cfg.off_window = 0;
    expect_invalid(probe, "zero intermittent off window");

    probe = make_valid_probe("valid_boundaries");
    probe.master_cfg.max_outstanding_rd = 1;
    probe.master_cfg.max_outstanding_wr = 1;
    probe.master_cfg.enable_bw_limit = 1;
    probe.master_cfg.max_bytes_per_window = 1;
    probe.master_cfg.bw_window_cycles = 1;
    probe.master_cfg.per_channel_bp_enable = 1;
    probe.master_cfg.b_bp_cfg.mode = BP_RANDOM;
    probe.master_cfg.b_bp_cfg.random_ready_pct = 100;
    probe.master_cfg.r_bp_cfg.mode = BP_INTERMITTENT;
    probe.master_cfg.r_bp_cfg.on_window = 1;
    probe.master_cfg.r_bp_cfg.off_window = 1;
    probe.slave_cfg.resp_delay_min = 5;
    probe.slave_cfg.resp_delay_max = 5;
    probe.slave_cfg.per_channel_bp_enable = 1;
    probe.slave_cfg.aw_bp_cfg.mode = BP_BURST;
    probe.slave_cfg.aw_bp_cfg.burst_accept_cycles = 1;
    probe.slave_cfg.aw_bp_cfg.burst_block_cycles = 1;
    probe.slave_cfg.w_bp_cfg.mode = BP_FIXED_DELAY;
    probe.slave_cfg.ar_bp_cfg.mode = BP_CUSTOM;
    expect_valid(probe, "legal boundary values");

    probe = make_valid_probe("illegal_bp_mode");
    probe.slave_cfg.per_channel_bp_enable = 1;
    probe.slave_cfg.aw_bp_cfg.mode = axi_bp_mode_e'(99);
    expect_invalid_reason(probe, "illegal backpressure mode encoding",
      "slave AW mode=99 is not a valid axi_bp_mode_e");

    probe = axi_config::type_id::create("null_vif");
    expect_invalid(probe, "enabled endpoint without vif");

    probe = make_valid_probe("checker_only");
    probe.master_cfg.enabled = 0;
    probe.slave_cfg.enabled = 0;
    probe.has_scoreboard = 0;
    probe.has_coverage = 0;
    probe.has_protocol_check = 1;
    expect_valid(probe, "checker-only mode");

    probe = make_valid_probe("no_observer");
    probe.master_cfg.enabled = 0;
    probe.slave_cfg.enabled = 0;
    probe.has_scoreboard = 1;
    probe.has_coverage = 0;
    expect_invalid_reason(probe, "scoreboard without a monitor",
      "scoreboard or coverage requires an enabled endpoint monitor");

    probe = make_valid_probe("coverage_only_observer");
    probe.master_cfg.enabled = 0;
    probe.slave_cfg.enabled = 0;
    probe.has_scoreboard = 0;
    probe.has_coverage = 1;
    expect_invalid_reason(probe, "coverage without a monitor",
      "scoreboard or coverage requires an enabled endpoint monitor");

    probe = make_valid_probe("no_component");
    probe.master_cfg.enabled = 0;
    probe.slave_cfg.enabled = 0;
    probe.has_scoreboard = 0;
    probe.has_coverage = 0;
    probe.has_protocol_check = 0;
    expect_invalid(probe, "empty environment");

    probe = make_valid_probe("disabled_dormant_invalid_knobs");
    probe.master_cfg.enabled = 0;
    probe.master_cfg.max_outstanding_rd = 0;
    probe.master_cfg.max_outstanding_wr = 0;
    probe.master_cfg.enable_bw_limit = 1;
    probe.master_cfg.max_bytes_per_window = 0;
    probe.master_cfg.bw_window_cycles = 0;
    probe.master_cfg.per_channel_bp_enable = 1;
    probe.master_cfg.b_bp_cfg.mode = axi_bp_mode_e'(99);
    probe.slave_cfg.enabled = 0;
    probe.slave_cfg.resp_delay_min = 9;
    probe.slave_cfg.resp_delay_max = 1;
    probe.slave_cfg.per_channel_bp_enable = 1;
    probe.slave_cfg.aw_bp_cfg.mode = axi_bp_mode_e'(99);
    probe.has_scoreboard = 0;
    probe.has_coverage = 0;
    probe.has_protocol_check = 1;
    expect_valid(probe, "disabled endpoints ignore dormant invalid knobs");

    probe = axi_config::type_id::create("legacy_mapping");
    probe.vif = cfg.vif;
    probe.max_outstanding_rd = 3;
    probe.max_outstanding_wr = 5;
    probe.enable_bw_limit = 1;
    probe.max_bytes_per_window = 777;
    probe.bw_window_cycles = 13;
    probe.resp_delay_min = 2;
    probe.resp_delay_max = 9;
    probe.enable_err_inject = 1;
    probe.per_channel_bp_enable = 1;
    probe.global_bp_cfg.mode = BP_FIXED_DELAY;
    probe.global_bp_cfg.fixed_delay = 31;
    probe.aw_bp_cfg.mode = BP_FIXED_DELAY;
    probe.aw_bp_cfg.fixed_delay = 32;
    probe.w_bp_cfg.mode = BP_FIXED_DELAY;
    probe.w_bp_cfg.fixed_delay = 33;
    probe.ar_bp_cfg.mode = BP_FIXED_DELAY;
    probe.ar_bp_cfg.fixed_delay = 34;
    probe.b_bp_cfg.mode = BP_FIXED_DELAY;
    probe.b_bp_cfg.fixed_delay = 35;
    probe.r_bp_cfg.mode = BP_FIXED_DELAY;
    probe.r_bp_cfg.fixed_delay = 36;
    probe.resolve_agent_configs();
    expect_valid(probe, "legacy mapping sentinels");
    if (probe.master_cfg.max_outstanding_rd != 3 ||
        probe.master_cfg.max_outstanding_wr != 5 ||
        probe.master_cfg.enable_bw_limit != 1 ||
        probe.master_cfg.max_bytes_per_window != 777 ||
        probe.master_cfg.bw_window_cycles != 13 ||
        probe.master_cfg.per_channel_bp_enable != 1)
      `uvm_error("CFG_COPY", "master legacy scalar mapping is incomplete")
    if (probe.slave_cfg.resp_delay_min != 2 ||
        probe.slave_cfg.resp_delay_max != 9 ||
        probe.slave_cfg.enable_err_inject != 1 ||
        probe.slave_cfg.per_channel_bp_enable != 1)
      `uvm_error("CFG_COPY", "slave legacy scalar mapping is incomplete")
    expect_bp_copy(probe.global_bp_cfg, probe.master_cfg.global_bp_cfg,
                   "master global BP");
    expect_bp_copy(probe.b_bp_cfg, probe.master_cfg.b_bp_cfg, "master B BP");
    expect_bp_copy(probe.r_bp_cfg, probe.master_cfg.r_bp_cfg, "master R BP");
    expect_bp_copy(probe.global_bp_cfg, probe.slave_cfg.global_bp_cfg,
                   "slave global BP");
    expect_bp_copy(probe.aw_bp_cfg, probe.slave_cfg.aw_bp_cfg, "slave AW BP");
    expect_bp_copy(probe.w_bp_cfg, probe.slave_cfg.w_bp_cfg, "slave W BP");
    expect_bp_copy(probe.ar_bp_cfg, probe.slave_cfg.ar_bp_cfg, "slave AR BP");
    if (probe.master_cfg.global_bp_cfg == probe.slave_cfg.global_bp_cfg)
      `uvm_error("CFG_COPY", "master and slave global BP configs alias")
    probe.master_cfg.global_bp_cfg.fixed_delay = 91;
    if (probe.global_bp_cfg.fixed_delay == 91 ||
        probe.slave_cfg.global_bp_cfg.fixed_delay == 91)
      `uvm_error("CFG_COPY", "endpoint BP mutation leaked to another config")
    probe.aw_bp_cfg.fixed_delay = 92;
    if (probe.slave_cfg.aw_bp_cfg.fixed_delay == 92)
      `uvm_error("CFG_COPY", "legacy BP mutation leaked to endpoint config")

    probe = axi_config::type_id::create("preconfigured_endpoints");
    probe.vif = cfg.vif;
    probe.max_outstanding_rd = 0;
    probe.max_outstanding_wr = 0;
    probe.enable_bw_limit = 1;
    probe.max_bytes_per_window = 0;
    probe.bw_window_cycles = 0;
    probe.resp_delay_min = 9;
    probe.resp_delay_max = 1;
    probe.per_channel_bp_enable = 0;
    probe.master_cfg = axi_master_config::type_id::create("master_sentinel");
    probe.master_cfg.enabled = 0;
    probe.master_cfg.is_active = UVM_PASSIVE;
    probe.master_cfg.max_outstanding_rd = 7;
    probe.master_cfg.max_outstanding_wr = 8;
    probe.master_cfg.enable_bw_limit = 1;
    probe.master_cfg.max_bytes_per_window = 9;
    probe.master_cfg.bw_window_cycles = 10;
    probe.master_cfg.per_channel_bp_enable = 1;
    probe.master_cfg.global_bp_cfg.fixed_delay = 71;
    probe.master_cfg.b_bp_cfg.fixed_delay = 72;
    probe.master_cfg.r_bp_cfg.fixed_delay = 73;
    probe.slave_cfg = axi_slave_config::type_id::create("slave_sentinel");
    probe.slave_cfg.enabled = 1;
    probe.slave_cfg.is_active = UVM_PASSIVE;
    probe.slave_cfg.resp_delay_min = 11;
    probe.slave_cfg.resp_delay_max = 12;
    probe.slave_cfg.enable_err_inject = 1;
    probe.slave_cfg.per_channel_bp_enable = 1;
    probe.slave_cfg.global_bp_cfg.fixed_delay = 81;
    probe.slave_cfg.aw_bp_cfg.fixed_delay = 82;
    probe.slave_cfg.w_bp_cfg.fixed_delay = 83;
    probe.slave_cfg.ar_bp_cfg.fixed_delay = 84;
    master_sentinel = probe.master_cfg;
    slave_sentinel = probe.slave_cfg;
    master_global_sentinel = probe.master_cfg.global_bp_cfg;
    master_b_sentinel = probe.master_cfg.b_bp_cfg;
    master_r_sentinel = probe.master_cfg.r_bp_cfg;
    slave_global_sentinel = probe.slave_cfg.global_bp_cfg;
    slave_aw_sentinel = probe.slave_cfg.aw_bp_cfg;
    slave_w_sentinel = probe.slave_cfg.w_bp_cfg;
    slave_ar_sentinel = probe.slave_cfg.ar_bp_cfg;
    expect_valid(probe, "preconfigured endpoints");
    if (probe.master_cfg != master_sentinel ||
        probe.master_cfg.enabled != 0 ||
        probe.master_cfg.is_active != UVM_PASSIVE ||
        probe.master_cfg.max_outstanding_rd != 7 ||
        probe.master_cfg.max_outstanding_wr != 8 ||
        probe.master_cfg.enable_bw_limit != 1 ||
        probe.master_cfg.max_bytes_per_window != 9 ||
        probe.master_cfg.bw_window_cycles != 10 ||
        probe.master_cfg.per_channel_bp_enable != 1 ||
        probe.master_cfg.global_bp_cfg != master_global_sentinel ||
        probe.master_cfg.b_bp_cfg != master_b_sentinel ||
        probe.master_cfg.r_bp_cfg != master_r_sentinel ||
        probe.master_cfg.global_bp_cfg.fixed_delay != 71 ||
        probe.master_cfg.b_bp_cfg.fixed_delay != 72 ||
        probe.master_cfg.r_bp_cfg.fixed_delay != 73)
      `uvm_error("CFG_COPY", "preconfigured master endpoint was overwritten")
    if (probe.slave_cfg != slave_sentinel ||
        probe.slave_cfg.enabled != 1 ||
        probe.slave_cfg.is_active != UVM_PASSIVE ||
        probe.slave_cfg.resp_delay_min != 11 ||
        probe.slave_cfg.resp_delay_max != 12 ||
        probe.slave_cfg.enable_err_inject != 1 ||
        probe.slave_cfg.per_channel_bp_enable != 1 ||
        probe.slave_cfg.global_bp_cfg != slave_global_sentinel ||
        probe.slave_cfg.aw_bp_cfg != slave_aw_sentinel ||
        probe.slave_cfg.w_bp_cfg != slave_w_sentinel ||
        probe.slave_cfg.ar_bp_cfg != slave_ar_sentinel ||
        probe.slave_cfg.global_bp_cfg.fixed_delay != 81 ||
        probe.slave_cfg.aw_bp_cfg.fixed_delay != 82 ||
        probe.slave_cfg.w_bp_cfg.fixed_delay != 83 ||
        probe.slave_cfg.ar_bp_cfg.fixed_delay != 84)
      `uvm_error("CFG_COPY", "preconfigured slave endpoint was overwritten")

    probe = axi_config::type_id::create("legacy_null_bp");
    probe.vif = cfg.vif;
    probe.global_bp_cfg = null;
    probe.aw_bp_cfg = null;
    probe.w_bp_cfg = null;
    probe.ar_bp_cfg = null;
    probe.b_bp_cfg = null;
    probe.r_bp_cfg = null;
    expect_valid(probe, "null legacy BP configs");
    if (probe.master_cfg.global_bp_cfg == null ||
        probe.master_cfg.b_bp_cfg == null ||
        probe.master_cfg.r_bp_cfg == null ||
        probe.slave_cfg.global_bp_cfg == null ||
        probe.slave_cfg.aw_bp_cfg == null ||
        probe.slave_cfg.w_bp_cfg == null ||
        probe.slave_cfg.ar_bp_cfg == null)
      `uvm_error("CFG_COPY", "null legacy BP removed endpoint defaults")
    else if (probe.master_cfg.global_bp_cfg.mode != BP_NONE ||
             probe.master_cfg.b_bp_cfg.mode != BP_NONE ||
             probe.master_cfg.r_bp_cfg.mode != BP_NONE ||
             probe.slave_cfg.global_bp_cfg.mode != BP_NONE ||
             probe.slave_cfg.aw_bp_cfg.mode != BP_NONE ||
             probe.slave_cfg.w_bp_cfg.mode != BP_NONE ||
             probe.slave_cfg.ar_bp_cfg.mode != BP_NONE)
      `uvm_error("CFG_COPY", "null legacy BP defaults are not BP_NONE")
    else if (probe.master_cfg.global_bp_cfg ==
             probe.slave_cfg.global_bp_cfg ||
             probe.master_cfg.global_bp_cfg == probe.master_cfg.b_bp_cfg ||
             probe.master_cfg.global_bp_cfg == probe.master_cfg.r_bp_cfg ||
             probe.master_cfg.b_bp_cfg == probe.master_cfg.r_bp_cfg ||
             probe.slave_cfg.global_bp_cfg == probe.slave_cfg.aw_bp_cfg ||
             probe.slave_cfg.global_bp_cfg == probe.slave_cfg.w_bp_cfg ||
             probe.slave_cfg.global_bp_cfg == probe.slave_cfg.ar_bp_cfg ||
             probe.slave_cfg.aw_bp_cfg == probe.slave_cfg.w_bp_cfg ||
             probe.slave_cfg.aw_bp_cfg == probe.slave_cfg.ar_bp_cfg ||
             probe.slave_cfg.w_bp_cfg == probe.slave_cfg.ar_bp_cfg)
      `uvm_error("CFG_COPY", "null legacy BP endpoint defaults are aliased")

    probe = axi_config::type_id::create("explicit_null_bp");
    probe.vif = cfg.vif;
    probe.master_cfg = axi_master_config::type_id::create("null_bp_master");
    probe.master_cfg.global_bp_cfg = null;
    probe.slave_cfg = axi_slave_config::type_id::create("null_bp_slave");
    probe.slave_cfg.per_channel_bp_enable = 1;
    probe.slave_cfg.aw_bp_cfg = null;
    expect_valid(probe, "explicit null active BP configs");

    phase.drop_objection(this);
  endtask
endclass

`endif // AXI_CONFIG_VALIDATION_TEST_SV
