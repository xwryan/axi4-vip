`ifndef AXI_ENV_SV
`define AXI_ENV_SV

class axi_env extends uvm_env;

  `uvm_component_utils(axi_env)

  // Configuration
  axi_config       cfg;

  // Sub-components
  axi_ref_model    ref_mem;
  axi_master_agent master_agent;
  axi_slave_agent  slave_agent;
  axi_master_monitor analysis_monitor;

  // Optional components
  axi_scoreboard   scoreboard;
  axi_coverage     coverage;
  axi_perf_monitor perf_monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    string reason;

    super.build_phase(phase);

    // Retrieve configuration from config_db
    if (!uvm_config_db #(axi_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("CFG", "axi_env: axi_config not found in config_db")

    cfg.resolve_agent_configs();
    if (!cfg.validate(reason))
      `uvm_fatal("CFG", $sformatf("axi_env: invalid configuration: %s", reason))

    // Propagate the common config before creating children that retrieve it.
    uvm_config_db #(axi_config)::set(this, "*", "cfg", cfg);

    // Create shared reference memory model (factory overridable)
    ref_mem = axi_ref_model::type_id::create("ref_mem");

    if (cfg.master_cfg.enabled) begin
      master_agent            = axi_master_agent::type_id::create(
        "master_agent", this);
      master_agent.cfg        = cfg;
      master_agent.agent_cfg  = cfg.master_cfg;
      master_agent.is_active  = cfg.master_cfg.is_active;
    end

    if (cfg.slave_cfg.enabled) begin
      slave_agent           = axi_slave_agent::type_id::create(
        "slave_agent", this);
      slave_agent.cfg       = cfg;
      slave_agent.agent_cfg = cfg.slave_cfg;
      slave_agent.is_active = cfg.slave_cfg.is_active;
      slave_agent.ref_mem   = ref_mem;
    end

    // Optional scoreboard. It owns an independent expected-memory model.
    if (cfg.has_scoreboard) begin
      scoreboard     = axi_scoreboard::type_id::create("scoreboard", this);
      scoreboard.cfg = cfg;
    end

    // Optional functional coverage
    if (cfg.has_coverage)
      coverage = axi_coverage::type_id::create("coverage", this);

    if (cfg.master_cfg.enabled || cfg.slave_cfg.enabled)
      perf_monitor = axi_perf_monitor::type_id::create("perf_monitor", this);

  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    analysis_monitor = null;
    if (master_agent != null)
      analysis_monitor = master_agent.monitor;
    else if (slave_agent != null)
      analysis_monitor = slave_agent.monitor;

    if (cfg.has_scoreboard) begin
      analysis_monitor.write_commit_port.connect(
        scoreboard.write_commit_imp);
      analysis_monitor.read_request_port.connect(
        scoreboard.read_request_imp);
      analysis_monitor.item_collected_port.connect(scoreboard.complete_imp);
    end

    if (cfg.has_coverage)
      analysis_monitor.item_collected_port.connect(coverage.analysis_export);

    if (perf_monitor != null)
      analysis_monitor.item_collected_port.connect(perf_monitor.analysis_export);

  endfunction

  virtual function bit is_idle();
    if (master_agent != null) begin
      if (master_agent.monitor != null && !master_agent.monitor.is_idle())
        return 0;
      if (master_agent.driver != null && !master_agent.driver.is_idle())
        return 0;
    end

    if (slave_agent != null) begin
      if (slave_agent.monitor != null && !slave_agent.monitor.is_idle())
        return 0;
      if (slave_agent.driver != null && !slave_agent.driver.is_idle())
        return 0;
    end

    return 1;
  endfunction

endclass

`endif // AXI_ENV_SV
