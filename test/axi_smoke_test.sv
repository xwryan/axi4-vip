// test/axi_smoke_test.sv
`ifndef AXI_SMOKE_TEST_SV
`define AXI_SMOKE_TEST_SV

// Smoke test: exercises single R/W, burst, and random stress sequences
// in sequence on the master sequencer.  Passes when all three complete
// without UVM_ERROR/UVM_FATAL and the scoreboard reports no mismatches.
class axi_smoke_test extends axi_base_test;

  `uvm_component_utils(axi_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // -----------------------------------------------------------------------
  // configure_test -- enable all optional checkers for maximum coverage
  // -----------------------------------------------------------------------
  virtual function void configure_test();
    super.configure_test();
    cfg.has_scoreboard     = 1;
    cfg.has_coverage       = 1;
    cfg.has_protocol_check = 1;
  endfunction

  // -----------------------------------------------------------------------
  // run_phase -- single_rw -> burst -> random stress
  // -----------------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
    axi_single_rw_seq     single_rw_seq;
    axi_burst_seq         burst_seq;
    axi_random_stress_seq stress_seq;

    phase.raise_objection(this, "axi_smoke_test: start");

    // ------------------------------------------------------------------
    // Phase 1: single read/write
    // ------------------------------------------------------------------
    `uvm_info("AXI_SMOKE_TEST", "=== Phase 1: Single R/W ===", UVM_LOW)
    single_rw_seq = axi_single_rw_seq::type_id::create("single_rw_seq");
    if (!single_rw_seq.randomize())
      `uvm_fatal("AXI_SMOKE_TEST", "single_rw_seq randomize failed")
    single_rw_seq.start(env.master_agent.sequencer);

    // ------------------------------------------------------------------
    // Phase 2: burst
    // ------------------------------------------------------------------
    `uvm_info("AXI_SMOKE_TEST", "=== Phase 2: Burst ===", UVM_LOW)
    burst_seq = axi_burst_seq::type_id::create("burst_seq");
    if (!burst_seq.randomize())
      `uvm_fatal("AXI_SMOKE_TEST", "burst_seq randomize failed")
    burst_seq.start(env.master_agent.sequencer);

    // ------------------------------------------------------------------
    // Phase 3: random stress
    // ------------------------------------------------------------------
    `uvm_info("AXI_SMOKE_TEST", "=== Phase 3: Random Stress ===", UVM_LOW)
    stress_seq = axi_random_stress_seq::type_id::create("stress_seq");
    if (!stress_seq.randomize())
      `uvm_fatal("AXI_SMOKE_TEST", "stress_seq randomize failed")
    stress_seq.start(env.master_agent.sequencer);

    `uvm_info("AXI_SMOKE_TEST", "=== Smoke test PASSED ===", UVM_LOW)

    phase.drop_objection(this, "axi_smoke_test: done");
  endtask

endclass

`endif // AXI_SMOKE_TEST_SV
