`ifndef AXI_AGENT_TOPOLOGY_TEST_SV
`define AXI_AGENT_TOPOLOGY_TEST_SV

class axi_topology_idle_report_catcher extends uvm_report_catcher;

  int unsigned idle_message_count;

  function new(string name = "axi_topology_idle_report_catcher");
    super.new(name);
  endfunction

  virtual function action_e catch();
    string message;

    message = get_message();
    if (get_severity() == UVM_INFO &&
        get_id() == "AXI_BASE_TEST" &&
        message.len() >= 14 &&
        message.substr(0, 13) == "Bus idle after")
      idle_message_count++;
    return THROW;
  endfunction

endclass

class axi_agent_topology_base_test extends axi_base_test;

  localparam int unsigned EXTERNAL_MASTER_TIMEOUT_CYCLES = 1000;

  typedef enum {
    TOPOLOGY_WAIT_AW,
    TOPOLOGY_WAIT_W,
    TOPOLOGY_WAIT_B,
    TOPOLOGY_WAIT_AR,
    TOPOLOGY_WAIT_R
  } topology_wait_channel_e;

  bit exp_master_enabled;
  bit exp_slave_enabled;
  uvm_active_passive_enum exp_master_active;
  uvm_active_passive_enum exp_slave_active;
  bit run_external_master_traffic;
  bit traffic_write_complete;
  bit traffic_read_complete;
  uvm_port_list coverage_provided_to;
  axi_topology_idle_report_catcher idle_report_catcher;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    idle_report_catcher = new();
    uvm_report_cb::add(this, idle_report_catcher);
  endfunction

  protected function void configure_topology(
    bit master_enabled,
    uvm_active_passive_enum master_active,
    bit slave_enabled,
    uvm_active_passive_enum slave_active
  );
    super.configure_test();
    cfg.resolve_agent_configs();

    cfg.master_cfg.enabled   = master_enabled;
    cfg.master_cfg.is_active = master_active;
    cfg.slave_cfg.enabled    = slave_enabled;
    cfg.slave_cfg.is_active  = slave_active;

    cfg.has_scoreboard = 0;
    cfg.has_coverage = 0;
    cfg.has_protocol_check = 1;

    exp_master_enabled = master_enabled;
    exp_master_active  = master_active;
    exp_slave_enabled  = slave_enabled;
    exp_slave_active   = slave_active;
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    if ((env.master_agent != null) != exp_master_enabled)
      `uvm_error("TOPOLOGY", $sformatf(
        "master agent presence=%0b expected=%0b",
        env.master_agent != null, exp_master_enabled))
    if ((env.slave_agent != null) != exp_slave_enabled)
      `uvm_error("TOPOLOGY", $sformatf(
        "slave agent presence=%0b expected=%0b",
        env.slave_agent != null, exp_slave_enabled))

    if (exp_master_enabled && env.master_agent != null) begin
      if (env.master_agent.monitor == null)
        `uvm_error("TOPOLOGY", "enabled master agent has no monitor")
      if ((env.master_agent.driver != null) !=
          (exp_master_active == UVM_ACTIVE))
        `uvm_error("TOPOLOGY", $sformatf(
          "master driver presence=%0b expected active=%0b",
          env.master_agent.driver != null,
          exp_master_active == UVM_ACTIVE))
      if ((env.master_agent.sequencer != null) !=
          (exp_master_active == UVM_ACTIVE))
        `uvm_error("TOPOLOGY", $sformatf(
          "master sequencer presence=%0b expected active=%0b",
          env.master_agent.sequencer != null,
          exp_master_active == UVM_ACTIVE))
      if (env.master_agent.agent_cfg != cfg.master_cfg)
        `uvm_error("TOPOLOGY", "master agent has the wrong endpoint config")
      if (exp_master_active == UVM_ACTIVE &&
          env.master_agent.driver != null &&
          env.master_agent.driver.agent_cfg != cfg.master_cfg)
        `uvm_error("TOPOLOGY",
          "master driver has the wrong endpoint config")
    end

    if (exp_slave_enabled && env.slave_agent != null) begin
      if (env.slave_agent.monitor == null)
        `uvm_error("TOPOLOGY", "enabled slave agent has no monitor")
      if ((env.slave_agent.driver != null) !=
          (exp_slave_active == UVM_ACTIVE))
        `uvm_error("TOPOLOGY", $sformatf(
          "slave driver presence=%0b expected active=%0b",
          env.slave_agent.driver != null,
          exp_slave_active == UVM_ACTIVE))
      if ((env.slave_agent.sequencer != null) !=
          (exp_slave_active == UVM_ACTIVE))
        `uvm_error("TOPOLOGY", $sformatf(
          "slave sequencer presence=%0b expected active=%0b",
          env.slave_agent.sequencer != null,
          exp_slave_active == UVM_ACTIVE))
      if (env.slave_agent.agent_cfg != cfg.slave_cfg)
        `uvm_error("TOPOLOGY", "slave agent has the wrong endpoint config")
      if (exp_slave_active == UVM_ACTIVE &&
          env.slave_agent.driver != null &&
          env.slave_agent.driver.agent_cfg != cfg.slave_cfg)
        `uvm_error("TOPOLOGY",
          "slave driver has the wrong endpoint config")
    end

    if (exp_master_enabled) begin
      if (env.master_agent != null &&
          env.analysis_monitor != env.master_agent.monitor)
        `uvm_error("TOPOLOGY", "analysis monitor is not the master monitor")
    end else if (exp_slave_enabled) begin
      if (env.slave_agent != null &&
          env.analysis_monitor != env.slave_agent.monitor)
        `uvm_error("TOPOLOGY", "analysis monitor is not the slave monitor")
    end else if (env.analysis_monitor != null) begin
      `uvm_error("TOPOLOGY", "checker-only topology has an analysis monitor")
    end

    if (idle_report_catcher.idle_message_count != 1)
      `uvm_error("TOPOLOGY", $sformatf(
        "run drain completed %0d times, expected exactly 1",
        idle_report_catcher.idle_message_count))
    if (run_drain_start_count != 1 || !run_drain_complete)
      `uvm_error("TOPOLOGY", $sformatf(
        "run drain starts=%0d complete=%0b, expected 1/1",
        run_drain_start_count, run_drain_complete))

    if (run_external_master_traffic) begin
      if (!traffic_write_complete || !traffic_read_complete)
        `uvm_error("TOPOLOGY", "slave-only traffic did not complete")
      if (env.scoreboard == null || env.scoreboard.match_count != 1 ||
          env.scoreboard.mismatch_count != 0)
        `uvm_error("TOPOLOGY", $sformatf(
          "slave-only scoreboard MATCH=%0d MISMATCH=%0d, expected 1/0",
          (env.scoreboard == null) ? 0 : env.scoreboard.match_count,
          (env.scoreboard == null) ? 0 : env.scoreboard.mismatch_count))
      if (env.perf_monitor == null || env.perf_monitor.total_wr_txn != 1 ||
          env.perf_monitor.total_rd_txn != 1)
        `uvm_error("TOPOLOGY", $sformatf(
          "slave-only perf writes=%0d reads=%0d, expected 1/1",
          (env.perf_monitor == null) ? 0 : env.perf_monitor.total_wr_txn,
          (env.perf_monitor == null) ? 0 : env.perf_monitor.total_rd_txn))
      if (env.coverage == null) begin
        `uvm_error("TOPOLOGY", "slave-only coverage component was not built")
      end else begin
        coverage_provided_to.delete();
        env.coverage.analysis_export.get_provided_to(
          coverage_provided_to);
        if (coverage_provided_to.num() != 1)
          `uvm_error("TOPOLOGY", $sformatf(
            "coverage analysis imp has %0d providers, expected 1",
            coverage_provided_to.num()))
      end
      `uvm_info("TOPOLOGY_ROUTING", $sformatf(
        "slave-only analysis fanout=%0d coverage providers=%0d",
        (env.analysis_monitor == null) ? 0 :
          env.analysis_monitor.item_collected_port.size(),
        coverage_provided_to.num()), UVM_LOW)
      if (env.analysis_monitor == null ||
          env.analysis_monitor.item_collected_port.size() != 3)
        `uvm_error("TOPOLOGY", $sformatf(
          "slave-only analysis fanout=%0d, expected scoreboard/coverage/perf=3",
          (env.analysis_monitor == null) ? 0 :
            env.analysis_monitor.item_collected_port.size()))
      if (!env.is_idle())
        `uvm_error("TOPOLOGY", "slave-only environment is not idle")
    end
  endfunction

  // The topology fixture has no external DUT. Tie off only the interface
  // direction that would otherwise have no active driver; passive agents
  // remain observation-only.
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "initializing undriven topology directions");
    if (!exp_master_enabled || exp_master_active == UVM_PASSIVE)
      cfg.vif.claim_master_drive();
    if (!exp_slave_enabled || exp_slave_active == UVM_PASSIVE)
      cfg.vif.claim_slave_drive();
    if (run_external_master_traffic)
      drive_slave_only_traffic();
    else
      @(posedge cfg.vif.aclk);
    phase.drop_objection(this, "topology directions initialized");
  endtask

  // In the active Slave-only topology, the fixture owns the external Master
  // request and response-ready signals. The production Slave driver remains
  // the sole owner of the Slave response direction.
  protected task drive_slave_only_traffic();
    bit [63:0] write_data;

    write_data = 64'h0123_4567_89ab_cdef;
    if (env.master_agent != null)
      `uvm_fatal("TOPOLOGY_OWNERSHIP", $sformatf(
        "external Master requires no agent/driver; agent=1 driver=%0b",
        env.master_agent.driver != null))

    wait_for_external_reset();

    @(negedge cfg.vif.aclk);
    cfg.vif.master_bready <= 1'b1;
    cfg.vif.master_rready <= 1'b1;

    cfg.vif.master_awid     <= 4'h3;
    cfg.vif.master_awaddr   <= 32'h0000_1000;
    cfg.vif.master_awlen    <= 8'h00;
    cfg.vif.master_awsize   <= 3'h3;
    cfg.vif.master_awburst  <= AXI_INCR;
    cfg.vif.master_awlock   <= 1'b0;
    cfg.vif.master_awcache  <= 4'h0;
    cfg.vif.master_awprot   <= 3'h0;
    cfg.vif.master_awqos    <= 4'h0;
    cfg.vif.master_awregion <= 4'h0;
    cfg.vif.master_awvalid  <= 1'b1;
    wait_for_external_handshake(TOPOLOGY_WAIT_AW);
    @(negedge cfg.vif.aclk);
    cfg.vif.master_awvalid <= 1'b0;

    cfg.vif.master_wdata  <= write_data;
    cfg.vif.master_wstrb  <= 8'hff;
    cfg.vif.master_wlast  <= 1'b1;
    cfg.vif.master_wvalid <= 1'b1;
    wait_for_external_handshake(TOPOLOGY_WAIT_W);
    @(negedge cfg.vif.aclk);
    cfg.vif.master_wvalid <= 1'b0;
    cfg.vif.master_wlast  <= 1'b0;

    wait_for_external_handshake(TOPOLOGY_WAIT_B);
    if (cfg.vif.bid !== 4'h3 || cfg.vif.bresp !== AXI_OKAY)
      `uvm_error("TOPOLOGY", $sformatf(
        "slave-only write response BID=0x%0h BRESP=0x%0h",
        cfg.vif.bid, cfg.vif.bresp))
    traffic_write_complete = 1;

    @(negedge cfg.vif.aclk);
    cfg.vif.master_arid     <= 4'h3;
    cfg.vif.master_araddr   <= 32'h0000_1000;
    cfg.vif.master_arlen    <= 8'h00;
    cfg.vif.master_arsize   <= 3'h3;
    cfg.vif.master_arburst  <= AXI_INCR;
    cfg.vif.master_arlock   <= 1'b0;
    cfg.vif.master_arcache  <= 4'h0;
    cfg.vif.master_arprot   <= 3'h0;
    cfg.vif.master_arqos    <= 4'h0;
    cfg.vif.master_arregion <= 4'h0;
    cfg.vif.master_arvalid  <= 1'b1;
    wait_for_external_handshake(TOPOLOGY_WAIT_AR);
    @(negedge cfg.vif.aclk);
    cfg.vif.master_arvalid <= 1'b0;

    wait_for_external_handshake(TOPOLOGY_WAIT_R);
    if (cfg.vif.rid !== 4'h3 || cfg.vif.rresp !== AXI_OKAY ||
        cfg.vif.rlast !== 1'b1 || cfg.vif.rdata !== write_data)
      `uvm_error("TOPOLOGY", $sformatf(
        "slave-only read RID=0x%0h RRESP=0x%0h RLAST=%0b data=0x%0h",
        cfg.vif.rid, cfg.vif.rresp, cfg.vif.rlast, cfg.vif.rdata))
    traffic_read_complete = 1;

    @(negedge cfg.vif.aclk);
    cfg.vif.master_bready <= 1'b0;
    cfg.vif.master_rready <= 1'b0;
  endtask

  protected task wait_for_external_reset();
    if (cfg.vif.aresetn === 1'b1)
      return;

    repeat (EXTERNAL_MASTER_TIMEOUT_CYCLES) begin
      @(posedge cfg.vif.aclk);
      if (cfg.vif.aresetn === 1'b1)
        return;
    end

    `uvm_fatal("TOPOLOGY_TIMEOUT", $sformatf(
      "RESET timed out after %0d cycles: ARESETn=%b",
      EXTERNAL_MASTER_TIMEOUT_CYCLES, cfg.vif.aresetn))
  endtask

  protected task wait_for_external_handshake(
    topology_wait_channel_e channel
  );
    repeat (EXTERNAL_MASTER_TIMEOUT_CYCLES) begin
      @(posedge cfg.vif.aclk);
      case (channel)
        TOPOLOGY_WAIT_AW:
          if (cfg.vif.awvalid === 1'b1 && cfg.vif.awready === 1'b1)
            return;
        TOPOLOGY_WAIT_W:
          if (cfg.vif.wvalid === 1'b1 && cfg.vif.wready === 1'b1)
            return;
        TOPOLOGY_WAIT_B:
          if (cfg.vif.bvalid === 1'b1 && cfg.vif.bready === 1'b1)
            return;
        TOPOLOGY_WAIT_AR:
          if (cfg.vif.arvalid === 1'b1 && cfg.vif.arready === 1'b1)
            return;
        TOPOLOGY_WAIT_R:
          if (cfg.vif.rvalid === 1'b1 && cfg.vif.rready === 1'b1)
            return;
        default:
          `uvm_fatal("TOPOLOGY_TIMEOUT", "unknown topology wait channel")
      endcase
    end

    case (channel)
      TOPOLOGY_WAIT_AW:
        `uvm_fatal("TOPOLOGY_TIMEOUT", $sformatf(
          "AW timed out after %0d cycles: AWVALID=%b AWREADY=%b AWID=0x%0h",
          EXTERNAL_MASTER_TIMEOUT_CYCLES, cfg.vif.awvalid,
          cfg.vif.awready, cfg.vif.awid))
      TOPOLOGY_WAIT_W:
        `uvm_fatal("TOPOLOGY_TIMEOUT", $sformatf(
          "W timed out after %0d cycles: WVALID=%b WREADY=%b WLAST=%b",
          EXTERNAL_MASTER_TIMEOUT_CYCLES, cfg.vif.wvalid,
          cfg.vif.wready, cfg.vif.wlast))
      TOPOLOGY_WAIT_B:
        `uvm_fatal("TOPOLOGY_TIMEOUT", $sformatf(
          "B timed out after %0d cycles: BVALID=%b BREADY=%b BID=0x%0h BRESP=0x%0h",
          EXTERNAL_MASTER_TIMEOUT_CYCLES, cfg.vif.bvalid,
          cfg.vif.bready, cfg.vif.bid, cfg.vif.bresp))
      TOPOLOGY_WAIT_AR:
        `uvm_fatal("TOPOLOGY_TIMEOUT", $sformatf(
          "AR timed out after %0d cycles: ARVALID=%b ARREADY=%b ARID=0x%0h",
          EXTERNAL_MASTER_TIMEOUT_CYCLES, cfg.vif.arvalid,
          cfg.vif.arready, cfg.vif.arid))
      TOPOLOGY_WAIT_R:
        `uvm_fatal("TOPOLOGY_TIMEOUT", $sformatf(
          "R timed out after %0d cycles: RVALID=%b RREADY=%b RID=0x%0h RRESP=0x%0h RLAST=%b",
          EXTERNAL_MASTER_TIMEOUT_CYCLES, cfg.vif.rvalid,
          cfg.vif.rready, cfg.vif.rid, cfg.vif.rresp, cfg.vif.rlast))
      default:
        `uvm_fatal("TOPOLOGY_TIMEOUT", "unknown topology timeout channel")
    endcase
  endtask

endclass

class axi_topology_both_active_test extends axi_agent_topology_base_test;
  `uvm_component_utils(axi_topology_both_active_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    configure_topology(1, UVM_ACTIVE, 1, UVM_ACTIVE);
  endfunction
endclass

class axi_topology_master_active_slave_passive_test extends
  axi_agent_topology_base_test;
  `uvm_component_utils(axi_topology_master_active_slave_passive_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    configure_topology(1, UVM_ACTIVE, 1, UVM_PASSIVE);
  endfunction
endclass

class axi_topology_master_passive_slave_active_test extends
  axi_agent_topology_base_test;
  `uvm_component_utils(axi_topology_master_passive_slave_active_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    configure_topology(1, UVM_PASSIVE, 1, UVM_ACTIVE);
  endfunction
endclass

class axi_topology_master_only_test extends axi_agent_topology_base_test;
  `uvm_component_utils(axi_topology_master_only_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    configure_topology(1, UVM_ACTIVE, 0, UVM_PASSIVE);
  endfunction
endclass

class axi_topology_checker_only_test extends axi_agent_topology_base_test;
  `uvm_component_utils(axi_topology_checker_only_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    configure_topology(0, UVM_PASSIVE, 0, UVM_PASSIVE);
  endfunction
endclass

class axi_topology_slave_only_test extends axi_agent_topology_base_test;
  `uvm_component_utils(axi_topology_slave_only_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    configure_topology(0, UVM_PASSIVE, 1, UVM_ACTIVE);
    cfg.has_scoreboard = 1;
    cfg.has_coverage = 1;
    run_external_master_traffic = 1;
  endfunction
endclass

class axi_topology_slave_only_passive_test extends
  axi_agent_topology_base_test;
  `uvm_component_utils(axi_topology_slave_only_passive_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    configure_topology(0, UVM_PASSIVE, 1, UVM_PASSIVE);
  endfunction
endclass

`endif // AXI_AGENT_TOPOLOGY_TEST_SV
