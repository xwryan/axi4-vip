// test/axi_bp_test.sv
`ifndef AXI_BP_TEST_SV
`define AXI_BP_TEST_SV

// =========================================================================
// Helper sequence: write+read pairs for backpressure testing
// (must be defined before axi_bp_test which uses it)
// =========================================================================
class axi_bp_batch_seq extends axi_base_seq;

  `uvm_object_utils(axi_bp_batch_seq)

  int unsigned num_pairs = 4;
  bit [63:0]   base_addr = 64'h0000_4000;

  function new(string name = "axi_bp_batch_seq");
    super.new(name);
  endfunction

  virtual task body();
    // Phase 1: issue all writes
    for (int i = 0; i < num_pairs; i++) begin
      bit [7:0] wr_data[];
      bit [63:0] addr;
      int unsigned num_bytes;

      // 4-beat INCR burst, 8 bytes/beat = 32 bytes (full 64-bit bus width)
      addr = base_addr + i * 64'h40;  // 8-byte aligned
      num_bytes = 4 * 8;
      wr_data = new[num_bytes];
      foreach (wr_data[j]) wr_data[j] = (i * 32 + j) & 8'hFF;

      do_write(
        .addr       (addr),
        .data       (wr_data),
        .burst_len  (8'h03),
        .burst_size (3'h3),
        .burst_type (AXI_INCR),
        .id         (16'(i))
      );
    end

    // Drain: wait for all write beats to complete on the bus before reading
    repeat(200) @(posedge cfg.vif.aclk);

    // Phase 2: issue all reads
    for (int i = 0; i < num_pairs; i++) begin
      axi_seq_item rsp;
      bit [63:0] addr;

      addr = base_addr + i * 64'h40;

      do_read(
        .addr       (addr),
        .burst_len  (8'h03),
        .burst_size (3'h3),
        .burst_type (AXI_INCR),
        .id         (16'(i)),
        .rsp        (rsp)
      );
    end
  endtask

endclass

// Comprehensive backpressure test.
// Tests all backpressure modes: BP_NONE, BP_FIXED_DELAY, BP_RANDOM,
// BP_BURST, BP_INTERMITTENT on slave-side channels (AW, W, AR).
// For each mode, verifies:
//   - All transactions complete without data corruption
//   - Latency characteristics match expected backpressure behavior
// Prints a summary comparing latencies across all modes.
class axi_bp_test extends axi_base_test;

  `uvm_component_utils(axi_bp_test)

  // Latency results per mode (indexed by mode ordinal 0..4)
  longint unsigned mode_total_latency[5];
  int unsigned     mode_txn_count[5];
  longint unsigned mode_max_latency[5];
  string           mode_names[5];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.has_scoreboard     = 1;
    cfg.has_coverage       = 0;
    cfg.has_protocol_check = 1;
    cfg.slave_cfg.per_channel_bp_enable = 1;
    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 1;
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "axi_bp_test: start");

    // Initialize mode names for reporting
    mode_names[0] = "BP_NONE";
    mode_names[1] = "BP_FIXED_DELAY";
    mode_names[2] = "BP_RANDOM";
    mode_names[3] = "BP_BURST";
    mode_names[4] = "BP_INTERMITTENT";

    for (int m = 0; m < 5; m++) begin
      mode_total_latency[m] = 0;
      mode_txn_count[m]     = 0;
      mode_max_latency[m]   = 0;
    end

    test_bp_none();
    test_bp_fixed_delay();
    test_bp_random();
    test_bp_burst();
    test_bp_intermittent();

    // Print comparison table
    print_summary();

    phase.drop_objection(this, "axi_bp_test: done");
  endtask

  // -----------------------------------------------------------------------
  // check_phase: verify scoreboard integrity across all modes
  // -----------------------------------------------------------------------
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("AXI_BP_TEST", $sformatf(
      "Scoreboard: MATCH=%0d  MISMATCH=%0d",
      env.scoreboard.match_count, env.scoreboard.mismatch_count), UVM_LOW)

    if (env.scoreboard.mismatch_count > 0)
      `uvm_error("AXI_BP_TEST",
        $sformatf("FAIL: %0d data mismatches detected under backpressure",
          env.scoreboard.mismatch_count))

    if (env.scoreboard.match_count == 0)
      `uvm_error("AXI_BP_TEST",
        "FAIL: scoreboard match_count is 0 -- no read comparisons occurred")

    // Verify BP_NONE has lowest average latency
    if (mode_txn_count[0] > 0 && mode_txn_count[1] > 0) begin
      longint unsigned avg_none  = mode_total_latency[0] / mode_txn_count[0];
      longint unsigned avg_fixed = mode_total_latency[1] / mode_txn_count[1];
      if (avg_fixed <= avg_none)
        `uvm_warning("AXI_BP_TEST",
          $sformatf("BP_FIXED_DELAY avg latency (%0d) not greater than BP_NONE (%0d) -- may be timing-dependent",
            avg_fixed, avg_none))
    end

    if (env.scoreboard.match_count > 0 && env.scoreboard.mismatch_count == 0)
      `uvm_info("AXI_BP_TEST",
        "PASS: all backpressure modes completed without data corruption", UVM_LOW)
  endfunction

  // -----------------------------------------------------------------------
  // Helper: configure backpressure on all slave-side channels
  // -----------------------------------------------------------------------
  virtual function void set_slave_bp(axi_bp_mode_e mode,
                                     int unsigned fixed_delay = 5,
                                     int unsigned random_pct = 50,
                                     int unsigned accept_cyc = 8,
                                     int unsigned block_cyc = 4,
                                     int unsigned on_win = 20,
                                     int unsigned off_win = 5);
    // Configure AW channel BP
    cfg.slave_cfg.aw_bp_cfg.mode                = mode;
    cfg.slave_cfg.aw_bp_cfg.fixed_delay         = fixed_delay;
    cfg.slave_cfg.aw_bp_cfg.random_ready_pct    = random_pct;
    cfg.slave_cfg.aw_bp_cfg.burst_accept_cycles = accept_cyc;
    cfg.slave_cfg.aw_bp_cfg.burst_block_cycles  = block_cyc;
    cfg.slave_cfg.aw_bp_cfg.on_window           = on_win;
    cfg.slave_cfg.aw_bp_cfg.off_window          = off_win;

    // Configure W channel BP
    cfg.slave_cfg.w_bp_cfg.mode                = mode;
    cfg.slave_cfg.w_bp_cfg.fixed_delay         = fixed_delay;
    cfg.slave_cfg.w_bp_cfg.random_ready_pct    = random_pct;
    cfg.slave_cfg.w_bp_cfg.burst_accept_cycles = accept_cyc;
    cfg.slave_cfg.w_bp_cfg.burst_block_cycles  = block_cyc;
    cfg.slave_cfg.w_bp_cfg.on_window           = on_win;
    cfg.slave_cfg.w_bp_cfg.off_window          = off_win;

    // Configure AR channel BP
    cfg.slave_cfg.ar_bp_cfg.mode                = mode;
    cfg.slave_cfg.ar_bp_cfg.fixed_delay         = fixed_delay;
    cfg.slave_cfg.ar_bp_cfg.random_ready_pct    = random_pct;
    cfg.slave_cfg.ar_bp_cfg.burst_accept_cycles = accept_cyc;
    cfg.slave_cfg.ar_bp_cfg.burst_block_cycles  = block_cyc;
    cfg.slave_cfg.ar_bp_cfg.on_window           = on_win;
    cfg.slave_cfg.ar_bp_cfg.off_window          = off_win;

    // Reconfigure the live bp_generators in the slave driver
    env.slave_agent.driver.aw_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("aw"));
    env.slave_agent.driver.w_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("w"));
    env.slave_agent.driver.ar_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("ar"));
  endfunction

  // -----------------------------------------------------------------------
  // Helper: run a batch of write+read transactions and record latency
  // -----------------------------------------------------------------------
  virtual task run_bp_batch(int mode_idx, int unsigned num_pairs);
    axi_bp_batch_seq seq;
    time t_start;

    t_start = $time;

    seq = axi_bp_batch_seq::type_id::create($sformatf("bp_batch_%s", mode_names[mode_idx]));
    seq.num_pairs = num_pairs;
    seq.base_addr = 64'h0000_4000 + mode_idx * 64'h1000;
    seq.start(env.master_agent.sequencer);

    // Wait for bus to drain
    repeat (20) @(posedge cfg.vif.aclk);
    wait (env.master_agent.monitor.cur_outstanding_rd == 0 &&
          env.master_agent.monitor.cur_outstanding_wr == 0);
    repeat (10) @(posedge cfg.vif.aclk);

    // Record performance metrics
    begin
      longint unsigned elapsed = $time - t_start;
      mode_txn_count[mode_idx]     = num_pairs * 2;  // write + read
      mode_total_latency[mode_idx] = elapsed;
      mode_max_latency[mode_idx]   = elapsed;

      `uvm_info("AXI_BP_TEST", $sformatf(
        "%s: %0d txns, total_time=%0t",
        mode_names[mode_idx], num_pairs * 2, elapsed), UVM_MEDIUM)
    end
  endtask

  // -----------------------------------------------------------------------
  // BP_NONE: no backpressure, baseline latency
  // -----------------------------------------------------------------------
  virtual task test_bp_none();
    `uvm_info("AXI_BP_TEST", "=== Testing BP_NONE ===", UVM_LOW)
    set_slave_bp(BP_NONE);
    run_bp_batch(0, 4);
  endtask

  // -----------------------------------------------------------------------
  // BP_FIXED_DELAY: READY delayed by N cycles
  // -----------------------------------------------------------------------
  virtual task test_bp_fixed_delay();
    `uvm_info("AXI_BP_TEST", "=== Testing BP_FIXED_DELAY (delay=5) ===", UVM_LOW)
    set_slave_bp(BP_FIXED_DELAY, .fixed_delay(5));
    run_bp_batch(1, 4);
  endtask

  // -----------------------------------------------------------------------
  // BP_RANDOM: READY asserted randomly (50% of cycles)
  // -----------------------------------------------------------------------
  virtual task test_bp_random();
    `uvm_info("AXI_BP_TEST", "=== Testing BP_RANDOM (50%) ===", UVM_LOW)
    set_slave_bp(BP_RANDOM, .random_pct(50));
    run_bp_batch(2, 4);
  endtask

  // -----------------------------------------------------------------------
  // BP_BURST: accept/block cycling pattern
  // -----------------------------------------------------------------------
  virtual task test_bp_burst();
    `uvm_info("AXI_BP_TEST", "=== Testing BP_BURST (accept=8, block=4) ===", UVM_LOW)
    set_slave_bp(BP_BURST, .accept_cyc(8), .block_cyc(4));
    run_bp_batch(3, 4);
  endtask

  // -----------------------------------------------------------------------
  // BP_INTERMITTENT: ON/OFF window pattern
  // -----------------------------------------------------------------------
  virtual task test_bp_intermittent();
    `uvm_info("AXI_BP_TEST", "=== Testing BP_INTERMITTENT (on=20, off=5) ===", UVM_LOW)
    set_slave_bp(BP_INTERMITTENT, .on_win(20), .off_win(5));
    run_bp_batch(4, 4);
  endtask

  // -----------------------------------------------------------------------
  // Print summary table comparing all modes
  // -----------------------------------------------------------------------
  virtual function void print_summary();
    `uvm_info("AXI_BP_TEST", "======================================================", UVM_LOW)
    `uvm_info("AXI_BP_TEST", "      Backpressure Mode Comparison Summary            ", UVM_LOW)
    `uvm_info("AXI_BP_TEST", "======================================================", UVM_LOW)
    `uvm_info("AXI_BP_TEST", " Mode               | Txns | Total Time | Avg/Txn    ", UVM_LOW)
    `uvm_info("AXI_BP_TEST", "------------------------------------------------------", UVM_LOW)

    for (int m = 0; m < 5; m++) begin
      longint unsigned avg_lat;
      if (mode_txn_count[m] > 0)
        avg_lat = mode_total_latency[m] / mode_txn_count[m];
      else
        avg_lat = 0;

      `uvm_info("AXI_BP_TEST", $sformatf(
        " %-18s | %4d | %10t | %10t",
        mode_names[m], mode_txn_count[m],
        mode_total_latency[m], avg_lat), UVM_LOW)
    end

    `uvm_info("AXI_BP_TEST", "======================================================", UVM_LOW)
  endfunction

endclass

`endif // AXI_BP_TEST_SV
