// test/axi_base_test.sv
`ifndef AXI_BASE_TEST_SV
`define AXI_BASE_TEST_SV

// Base test class for the AXI VIP.
// Builds the environment, sets up the virtual interface via config_db,
// and provides a configure_test() virtual method that sub-classes override
// to tune configuration without duplicating boilerplate.
class axi_base_test extends uvm_test;

  `uvm_component_utils(axi_base_test)

  axi_env    env;
  axi_config cfg;
  bit          run_drain_started;
  bit          run_drain_complete;
  int unsigned run_drain_start_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // -----------------------------------------------------------------------
  // build_phase: create config, call configure_test(), wire vif, create env
  // -----------------------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Create central configuration object
    cfg = axi_config::type_id::create("cfg");

    // Let sub-classes customise the config before it is published
    configure_test();

    // Retrieve the virtual interface from the top-level config_db and
    // store it in the config object so the env/agents can find it
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", cfg.vif))
      `uvm_fatal("CFG", "axi_base_test: virtual axi_if not found in config_db")

    // Publish config so the env and all sub-components can retrieve it
    uvm_config_db #(axi_config)::set(this, "*", "cfg", cfg);

    // Create the environment
    env = axi_env::type_id::create("env", this);
  endfunction

  // -----------------------------------------------------------------------
  // configure_test -- override in sub-classes to set cfg fields.
  // The default configuration is a sensible baseline:
  //   AXI4 master, 64-bit data, 32-bit address, scoreboard + coverage on.
  // -----------------------------------------------------------------------
  virtual function void configure_test();
    cfg.mode               = AXI4;
    cfg.data_width         = 64;
    cfg.addr_width         = 32;
    cfg.id_width           = 4;
    cfg.has_scoreboard     = 1;
    cfg.has_coverage       = 1;
    cfg.has_protocol_check = 1;
  endfunction

  // -----------------------------------------------------------------------
  // end_of_elaboration_phase: print topology
  // -----------------------------------------------------------------------
  virtual function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  // -----------------------------------------------------------------------
  // phase_ready_to_end: wait for all outstanding bus transactions to drain
  // before allowing the run phase to finish.
  // -----------------------------------------------------------------------
  virtual function void phase_ready_to_end(uvm_phase phase);
    if (phase.get_name() == "run" && !run_drain_started) begin
      run_drain_started = 1;
      run_drain_start_count++;
      phase.raise_objection(this, "axi_base_test: waiting for bus idle");
      fork
        begin
          wait_for_idle();
          run_drain_complete = 1;
          phase.drop_objection(this, "axi_base_test: bus is idle");
        end
      join_none
    end
  endfunction

  // -----------------------------------------------------------------------
  // wait_for_idle: waits until all components present in the selected topology
  // report idle, with a generous timeout.
  // -----------------------------------------------------------------------
  virtual task wait_for_idle();
    int unsigned idle_cycles;
    int unsigned timeout_cycles;

    idle_cycles    = 0;
    timeout_cycles = 0;

    // Wait at least a few cycles for pipeline to flush
    repeat (20) @(posedge cfg.vif.aclk);

    // Then wait until we see 50 consecutive idle cycles, or 50000 cycle timeout
    while (idle_cycles < 50 && timeout_cycles < 50000) begin
      @(posedge cfg.vif.aclk);
      timeout_cycles++;
      if (env.is_idle())
        idle_cycles++;
      else
        idle_cycles = 0;
    end

    if (timeout_cycles >= 50000)
      `uvm_error("AXI_BASE_TEST",
        "wait_for_idle timed out after 50000 cycles -- transactions did not drain")
    else
      `uvm_info("AXI_BASE_TEST",
        $sformatf("Bus idle after %0d cycles", timeout_cycles), UVM_MEDIUM)
  endtask

  // -----------------------------------------------------------------------
  // run_phase: sub-classes override this to launch sequences
  // -----------------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
    // Nothing in the base test; sub-classes implement stimulus
  endtask

endclass

`endif // AXI_BASE_TEST_SV
