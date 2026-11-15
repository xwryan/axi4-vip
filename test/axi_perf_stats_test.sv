// test/axi_perf_stats_test.sv
`ifndef AXI_PERF_STATS_TEST_SV
`define AXI_PERF_STATS_TEST_SV

// =========================================================================
// Helper sequence: runs exactly N write+read pairs (INCR, size=3).
// Forward-declared before the test class that uses it.
// =========================================================================
class axi_perf_stats_seq extends axi_base_seq;

  `uvm_object_utils(axi_perf_stats_seq)

  int unsigned num_pairs   = 100;
  int unsigned addr_offset = 0;

  function new(string name = "axi_perf_stats_seq");
    super.new(name);
  endfunction

  virtual task body();
    // Phase 1: issue all writes
    for (int i = 0; i < num_pairs; i++) begin
      bit [7:0]    wr_data[];
      bit [63:0]   addr;
      int unsigned  num_bytes;

      // 4-beat burst, 8 bytes/beat = 32 bytes
      num_bytes = 32;
      addr = 64'h0001_0000 + addr_offset + i * 64'h100;

      wr_data = new[num_bytes];
      for (int j = 0; j < num_bytes; j++)
        wr_data[j] = (i + j) & 8'hFF;

      do_write(
        .addr       (addr),
        .data       (wr_data),
        .burst_len  (8'h03),
        .burst_size (3'h3),
        .burst_type (AXI_INCR),
        .id         (16'(i & 16'hF))
      );
    end

    // Drain: wait for all write beats to complete on the bus before reading
    repeat(500) @(posedge cfg.vif.aclk);

    // Phase 2: issue all reads
    for (int i = 0; i < num_pairs; i++) begin
      axi_seq_item rsp;
      bit [63:0]   addr;

      addr = 64'h0001_0000 + addr_offset + i * 64'h100;

      do_read(
        .addr       (addr),
        .burst_len  (8'h03),
        .burst_size (3'h3),
        .burst_type (AXI_INCR),
        .id         (16'(i & 16'hF)),
        .rsp        (rsp)
      );
    end
  endtask

endclass

// =========================================================================
// Captured statistics for one phase -- stored as plain fields so we can
// build a comparison table at the end.
// =========================================================================
class perf_phase_record extends uvm_object;

  `uvm_object_utils(perf_phase_record)

  string       phase_name;
  int unsigned rd_txn;
  int unsigned wr_txn;
  longint unsigned rd_bytes;
  longint unsigned wr_bytes;
  real         avg_rd_lat;
  real         avg_wr_lat;
  longint unsigned max_rd_lat;
  longint unsigned max_wr_lat;

  function new(string name = "perf_phase_record");
    super.new(name);
  endfunction

endclass

// =========================================================================
// Detailed performance statistics test.
// Runs 4 phases with different backpressure / BW / delay settings,
// captures per-phase statistics, and prints a comparison table.
// =========================================================================
class axi_perf_stats_test extends axi_base_test;

  `uvm_component_utils(axi_perf_stats_test)

  perf_phase_record phase_records[4];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Wait until all outstanding transactions have drained from the bus.
  virtual task wait_for_drain();
    int idle_cycles = 0;
    while (idle_cycles < 20) begin
      @(posedge cfg.vif.aclk);
      if (env.master_agent.monitor.cur_outstanding_rd == 0 &&
          env.master_agent.monitor.cur_outstanding_wr == 0)
        idle_cycles++;
      else
        idle_cycles = 0;
    end
  endtask

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.has_scoreboard     = 1;
    cfg.has_coverage       = 0;
    cfg.has_protocol_check = 1;
    // Start with baseline (no delays, no BP, no BW limit)
    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 0;
    cfg.master_cfg.enable_bw_limit = 0;
    cfg.master_cfg.per_channel_bp_enable = 0;
    cfg.slave_cfg.per_channel_bp_enable = 0;
    cfg.master_cfg.global_bp_cfg.mode = BP_NONE;
    cfg.slave_cfg.global_bp_cfg.mode = BP_NONE;
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "axi_perf_stats_test: start");

    run_phase1_baseline();
    run_phase2_resp_delay();
    run_phase3_backpressure();
    run_phase4_bw_limit();

    phase.drop_objection(this, "axi_perf_stats_test: done");
  endtask

  // -------------------------------------------------------------------
  // Phase 1: Baseline -- no backpressure, no BW limit, resp_delay=0
  // -------------------------------------------------------------------
  virtual task run_phase1_baseline();
    axi_perf_stats_seq seq;
    `uvm_info("PERF_STATS", "=== Phase 1: Baseline ===", UVM_LOW)

    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 0;
    cfg.master_cfg.enable_bw_limit = 0;
    cfg.master_cfg.per_channel_bp_enable = 0;
    cfg.slave_cfg.per_channel_bp_enable = 0;
    cfg.master_cfg.global_bp_cfg.mode = BP_NONE;
    cfg.slave_cfg.global_bp_cfg.mode = BP_NONE;
    env.perf_monitor.reset();

    seq = axi_perf_stats_seq::type_id::create("phase1_seq");
    seq.num_pairs   = 100;
    seq.addr_offset = 0;
    seq.start(env.master_agent.sequencer);
    wait_for_drain();

    capture_stats(0, "Baseline");
    env.perf_monitor.print_stats("Phase 1 -- Baseline");
  endtask

  // -------------------------------------------------------------------
  // Phase 2: With resp_delay 5..10
  // -------------------------------------------------------------------
  virtual task run_phase2_resp_delay();
    axi_perf_stats_seq seq;
    `uvm_info("PERF_STATS", "=== Phase 2: resp_delay=5..10 ===", UVM_LOW)

    cfg.slave_cfg.resp_delay_min = 5;
    cfg.slave_cfg.resp_delay_max = 10;
    cfg.master_cfg.enable_bw_limit = 0;
    cfg.master_cfg.per_channel_bp_enable = 0;
    cfg.slave_cfg.per_channel_bp_enable = 0;
    cfg.master_cfg.global_bp_cfg.mode = BP_NONE;
    cfg.slave_cfg.global_bp_cfg.mode = BP_NONE;
    env.perf_monitor.reset();

    seq = axi_perf_stats_seq::type_id::create("phase2_seq");
    seq.num_pairs   = 100;
    seq.addr_offset = 32'h0001_0000;
    seq.start(env.master_agent.sequencer);
    wait_for_drain();

    capture_stats(1, "RespDelay 5--10");
    env.perf_monitor.print_stats("Phase 2 -- RespDelay 5--10");

    // Restore
    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 0;
  endtask

  // -------------------------------------------------------------------
  // Phase 3: BP_RANDOM(50%) on slave channels
  // -------------------------------------------------------------------
  virtual task run_phase3_backpressure();
    axi_perf_stats_seq seq;
    `uvm_info("PERF_STATS", "=== Phase 3: BP_RANDOM 50%% ===", UVM_LOW)

    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 0;
    cfg.master_cfg.enable_bw_limit = 0;

    // Enable per-channel BP and set slave-side channels to random 50%
    cfg.slave_cfg.per_channel_bp_enable = 1;
    cfg.slave_cfg.aw_bp_cfg.mode = BP_RANDOM;
    cfg.slave_cfg.aw_bp_cfg.random_ready_pct = 50;
    cfg.slave_cfg.w_bp_cfg.mode  = BP_RANDOM;
    cfg.slave_cfg.w_bp_cfg.random_ready_pct  = 50;
    cfg.slave_cfg.ar_bp_cfg.mode = BP_RANDOM;
    cfg.slave_cfg.ar_bp_cfg.random_ready_pct = 50;
    // Keep master-side (b, r) with no BP
    cfg.master_cfg.per_channel_bp_enable = 1;
    cfg.master_cfg.b_bp_cfg.mode  = BP_NONE;
    cfg.master_cfg.r_bp_cfg.mode  = BP_NONE;

    // Re-apply BP configs to running generators
    env.slave_agent.driver.aw_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("aw"));
    env.slave_agent.driver.w_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("w"));
    env.slave_agent.driver.ar_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("ar"));
    env.master_agent.driver.b_bp_gen.set_config(
      cfg.master_cfg.get_bp_cfg("b"));
    env.master_agent.driver.r_bp_gen.set_config(
      cfg.master_cfg.get_bp_cfg("r"));

    env.perf_monitor.reset();

    seq = axi_perf_stats_seq::type_id::create("phase3_seq");
    seq.num_pairs   = 100;
    seq.addr_offset = 32'h0002_0000;
    seq.start(env.master_agent.sequencer);
    wait_for_drain();

    capture_stats(2, "BP_RANDOM 50%%");
    env.perf_monitor.print_stats("Phase 3 -- BP_RANDOM 50%%");

    // Restore BP to none
    cfg.master_cfg.per_channel_bp_enable = 0;
    cfg.slave_cfg.per_channel_bp_enable = 0;
    cfg.slave_cfg.aw_bp_cfg.mode = BP_NONE;
    cfg.slave_cfg.w_bp_cfg.mode  = BP_NONE;
    cfg.slave_cfg.ar_bp_cfg.mode = BP_NONE;
    env.slave_agent.driver.aw_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("aw"));
    env.slave_agent.driver.w_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("w"));
    env.slave_agent.driver.ar_bp_gen.set_config(
      cfg.slave_cfg.get_bp_cfg("ar"));
    env.master_agent.driver.b_bp_gen.set_config(
      cfg.master_cfg.get_bp_cfg("b"));
    env.master_agent.driver.r_bp_gen.set_config(
      cfg.master_cfg.get_bp_cfg("r"));
  endtask

  // -------------------------------------------------------------------
  // Phase 4: BW limit -- 256 bytes per 100 cycles
  // -------------------------------------------------------------------
  virtual task run_phase4_bw_limit();
    axi_perf_stats_seq seq;
    `uvm_info("PERF_STATS", "=== Phase 4: BW limit 256B/100cyc ===", UVM_LOW)

    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 0;
    cfg.master_cfg.per_channel_bp_enable = 0;
    cfg.slave_cfg.per_channel_bp_enable = 0;
    cfg.master_cfg.global_bp_cfg.mode = BP_NONE;
    cfg.slave_cfg.global_bp_cfg.mode = BP_NONE;

    cfg.master_cfg.enable_bw_limit      = 1;
    cfg.master_cfg.max_bytes_per_window = 256;
    cfg.master_cfg.bw_window_cycles     = 100;
    env.master_agent.driver.bw_limiter.configure(
      cfg.master_cfg.enable_bw_limit,
      cfg.master_cfg.max_bytes_per_window,
      cfg.master_cfg.bw_window_cycles);

    env.perf_monitor.reset();

    seq = axi_perf_stats_seq::type_id::create("phase4_seq");
    seq.num_pairs   = 100;
    seq.addr_offset = 32'h0003_0000;
    seq.start(env.master_agent.sequencer);
    wait_for_drain();

    capture_stats(3, "BW 256B/100cyc");
    env.perf_monitor.print_stats("Phase 4 -- BW 256B/100cyc");

    // Restore
    cfg.master_cfg.enable_bw_limit = 0;
    env.master_agent.driver.bw_limiter.configure(0, 1024, 100);
  endtask

  // -------------------------------------------------------------------
  // Capture statistics snapshot from perf_monitor into phase_records
  // -------------------------------------------------------------------
  virtual function void capture_stats(int idx, string name);
    perf_phase_record rec;
    real rd_lat_avg, wr_lat_avg;

    rec = perf_phase_record::type_id::create($sformatf("rec_%0d", idx));
    rec.phase_name = name;
    rec.rd_txn     = env.perf_monitor.total_rd_txn;
    rec.wr_txn     = env.perf_monitor.total_wr_txn;
    rec.rd_bytes   = env.perf_monitor.total_rd_bytes;
    rec.wr_bytes   = env.perf_monitor.total_wr_bytes;
    rec.max_rd_lat = env.perf_monitor.max_rd_latency;
    rec.max_wr_lat = env.perf_monitor.max_wr_latency;

    rd_lat_avg = (rec.rd_txn > 0) ?
      (real'(env.perf_monitor.sum_rd_latency) / real'(rec.rd_txn)) : 0.0;
    wr_lat_avg = (rec.wr_txn > 0) ?
      (real'(env.perf_monitor.sum_wr_latency) / real'(rec.wr_txn)) : 0.0;
    rec.avg_rd_lat = rd_lat_avg;
    rec.avg_wr_lat = wr_lat_avg;

    phase_records[idx] = rec;
  endfunction

  // -------------------------------------------------------------------
  // check_phase: verify counts and print comparison table
  // -------------------------------------------------------------------
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("PERF_STATS", "Scoreboard totals across all phases:", UVM_LOW)
    `uvm_info("PERF_STATS", $sformatf(
      "  MATCH=%0d  MISMATCH=%0d",
      env.scoreboard.match_count, env.scoreboard.mismatch_count), UVM_LOW)

    if (env.scoreboard.mismatch_count > 0)
      `uvm_error("PERF_STATS",
        $sformatf("FAIL: %0d mismatch(es) detected",
          env.scoreboard.mismatch_count))

    // Print comparison table
    `uvm_info("PERF_STATS",
      "=============================================================================", UVM_NONE)
    `uvm_info("PERF_STATS",
      "  Phase Performance Comparison Table", UVM_NONE)
    `uvm_info("PERF_STATS",
      "=============================================================================", UVM_NONE)
    `uvm_info("PERF_STATS",
      "  Phase            | RdTxn | WrTxn | AvgRdLat | AvgWrLat | MaxRdLat | MaxWrLat", UVM_NONE)
    `uvm_info("PERF_STATS",
      "  -----------------|-------|-------|----------|----------|----------|----------", UVM_NONE)

    for (int i = 0; i < 4; i++) begin
      if (phase_records[i] != null) begin
        `uvm_info("PERF_STATS", $sformatf(
          "  %-17s| %5d | %5d | %8.2f | %8.2f | %8d | %8d",
          phase_records[i].phase_name,
          phase_records[i].rd_txn,
          phase_records[i].wr_txn,
          phase_records[i].avg_rd_lat,
          phase_records[i].avg_wr_lat,
          phase_records[i].max_rd_lat,
          phase_records[i].max_wr_lat), UVM_NONE)
      end
    end

    `uvm_info("PERF_STATS",
      "=============================================================================", UVM_NONE)

    // Verify each phase ran the expected number of transactions
    for (int i = 0; i < 4; i++) begin
      if (phase_records[i] != null) begin
        if (phase_records[i].rd_txn != 100 || phase_records[i].wr_txn != 100)
          `uvm_warning("PERF_STATS", $sformatf(
            "Phase '%s' expected 100 rd + 100 wr, got %0d rd + %0d wr",
            phase_records[i].phase_name,
            phase_records[i].rd_txn,
            phase_records[i].wr_txn))
      end
    end
  endfunction

endclass

`endif // AXI_PERF_STATS_TEST_SV
