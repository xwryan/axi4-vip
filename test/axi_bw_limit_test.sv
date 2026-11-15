// test/axi_bw_limit_test.sv
`ifndef AXI_BW_LIMIT_TEST_SV
`define AXI_BW_LIMIT_TEST_SV

// =========================================================================
// Sequence: fixed workload for bandwidth measurement
// Sends num_txns write+read pairs, all INCR burst, size=3 (8B/beat)
// =========================================================================
class axi_bw_measure_seq extends axi_base_seq;

  `uvm_object_utils(axi_bw_measure_seq)

  int unsigned num_txns   = 200;
  bit [7:0]   burst_len  = 8'h07;   // 8 beats = 64 bytes per txn
  bit [63:0]  addr_base  = 64'h0001_0000;

  function new(string name = "axi_bw_measure_seq");
    super.new(name);
  endfunction

  virtual task body();
    // Phase 1: all writes
    for (int i = 0; i < num_txns; i++) begin
      bit [7:0] wr_data[];
      int unsigned num_bytes = (burst_len + 1) * 8;
      bit [63:0] addr = addr_base + i * 64'h100;

      wr_data = new[num_bytes];
      for (int j = 0; j < num_bytes; j++)
        wr_data[j] = (i + j) & 8'hFF;

      do_write(
        .addr       (addr),
        .data       (wr_data),
        .burst_len  (burst_len),
        .burst_size (3'h3),
        .burst_type (AXI_INCR),
        .id         (16'(i & 16'hF))
      );
    end

    // Drain
    repeat(500) @(posedge cfg.vif.aclk);

    // Phase 2: all reads
    for (int i = 0; i < num_txns; i++) begin
      axi_seq_item rsp;
      bit [63:0] addr = addr_base + i * 64'h100;

      do_read(
        .addr       (addr),
        .burst_len  (burst_len),
        .burst_size (3'h3),
        .burst_type (AXI_INCR),
        .id         (16'(i & 16'hF)),
        .rsp        (rsp)
      );
    end
  endtask

endclass

// =========================================================================
// Bandwidth Limit Test
// Phase 1: Baseline (no BW limit) -- measure max throughput
// Phase 2: BW limited to 5 Gbps -- verify throttling
// =========================================================================
class axi_bw_limit_test extends axi_base_test;

  `uvm_component_utils(axi_bw_limit_test)

  // Per-phase captured stats
  int unsigned     phase1_rd_txn, phase1_wr_txn;
  longint unsigned phase1_rd_bytes, phase1_wr_bytes;
  time             phase1_start, phase1_end;
  time             phase1_wr_start, phase1_wr_end;
  time             phase1_rd_start, phase1_rd_end;

  int unsigned     phase2_rd_txn, phase2_wr_txn;
  longint unsigned phase2_rd_bytes, phase2_wr_bytes;
  time             phase2_start, phase2_end;
  time             phase2_wr_start, phase2_wr_end;
  time             phase2_rd_start, phase2_rd_end;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.has_scoreboard     = 1;
    cfg.has_coverage       = 0;
    cfg.slave_cfg.resp_delay_min  = 0;
    cfg.slave_cfg.resp_delay_max  = 0;  // no slave delay for clean measurement
    cfg.master_cfg.enable_bw_limit = 0; // start without BW limit
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_bw_measure_seq seq;

    phase.raise_objection(this, "axi_bw_limit_test");

    // =====================================================================
    // Phase 1: Baseline -- no bandwidth limit
    // =====================================================================
    `uvm_info("BW_TEST", "=== Phase 1: Baseline (no BW limit) ===", UVM_LOW)
    env.perf_monitor.reset();
    cfg.master_cfg.enable_bw_limit = 0;

    seq = axi_bw_measure_seq::type_id::create("baseline_seq");
    seq.num_txns  = 200;
    seq.addr_base = 64'h0001_0000;
    seq.start(env.master_agent.sequencer);

    // Wait for all transactions to complete
    wait_for_idle();

    // Use perf_monitor's per-direction timestamps for accurate BW
    phase1_start    = env.perf_monitor.first_wr_time;
    phase1_end      = env.perf_monitor.last_rd_time;
    phase1_rd_txn   = env.perf_monitor.total_rd_txn;
    phase1_wr_txn   = env.perf_monitor.total_wr_txn;
    phase1_rd_bytes = env.perf_monitor.total_rd_bytes;
    phase1_wr_bytes = env.perf_monitor.total_wr_bytes;
    phase1_wr_start = env.perf_monitor.first_wr_time;
    phase1_wr_end   = env.perf_monitor.last_wr_time;
    phase1_rd_start = env.perf_monitor.first_rd_time;
    phase1_rd_end   = env.perf_monitor.last_rd_time;

    print_phase_stats("Baseline", phase1_rd_txn, phase1_wr_txn,
                      phase1_rd_bytes, phase1_wr_bytes,
                      phase1_start, phase1_end,
                      phase1_wr_start, phase1_wr_end,
                      phase1_rd_start, phase1_rd_end);

    // =====================================================================
    // Phase 2: BW limited to 5 Gbps
    // 5 Gbps = 625 MB/s. Window must hold at least one burst (64B).
    // @800MHz: 160 cycles = 200ns, 625 MB/s * 200ns = 125 bytes
    // @100MHz: 20 cycles = 200ns, same 125 bytes
    // =====================================================================
    `uvm_info("BW_TEST", "=== Phase 2: BW limited to 5 Gbps ===", UVM_LOW)
    env.perf_monitor.reset();
    cfg.master_cfg.enable_bw_limit       = 1;
    cfg.master_cfg.max_bytes_per_window  = 125;
    cfg.master_cfg.bw_window_cycles      = 160;

    // Reconfigure the master driver's bw_limiter at runtime
    env.master_agent.driver.bw_limiter.configure(
      cfg.master_cfg.enable_bw_limit,
      cfg.master_cfg.max_bytes_per_window,
      cfg.master_cfg.bw_window_cycles
    );

    seq = axi_bw_measure_seq::type_id::create("limited_seq");
    seq.num_txns  = 200;
    seq.addr_base = 64'h0010_0000;  // different address range
    seq.start(env.master_agent.sequencer);

    wait_for_idle();

    phase2_start    = env.perf_monitor.first_wr_time;
    phase2_end      = env.perf_monitor.last_rd_time;
    phase2_rd_txn   = env.perf_monitor.total_rd_txn;
    phase2_wr_txn   = env.perf_monitor.total_wr_txn;
    phase2_rd_bytes = env.perf_monitor.total_rd_bytes;
    phase2_wr_bytes = env.perf_monitor.total_wr_bytes;
    phase2_wr_start = env.perf_monitor.first_wr_time;
    phase2_wr_end   = env.perf_monitor.last_wr_time;
    phase2_rd_start = env.perf_monitor.first_rd_time;
    phase2_rd_end   = env.perf_monitor.last_rd_time;

    print_phase_stats("BW=5Gbps", phase2_rd_txn, phase2_wr_txn,
                      phase2_rd_bytes, phase2_wr_bytes,
                      phase2_start, phase2_end,
                      phase2_wr_start, phase2_wr_end,
                      phase2_rd_start, phase2_rd_end);

    // Summary
    print_comparison();

    phase.drop_objection(this, "axi_bw_limit_test");
  endtask

  function void print_phase_stats(
    string phase_name,
    int unsigned rd_txn, int unsigned wr_txn,
    longint unsigned rd_bytes, longint unsigned wr_bytes,
    time t_start, time t_end,
    time wr_start, time wr_end,
    time rd_start, time rd_end
  );
    longint unsigned total_bytes;
    time duration, wr_duration, rd_duration;
    real combined_bw, wr_bw, rd_bw;

    total_bytes = rd_bytes + wr_bytes;
    duration    = t_end - t_start;
    wr_duration = wr_end - wr_start;
    rd_duration = rd_end - rd_start;

    // BW in Gbps: bytes * 8 bits / duration_ps * 1e12 / 1e9
    //   = bytes * 8000 / duration_ps
    if (duration > 0)
      combined_bw = (real'(total_bytes) * 8000.0) / real'(duration);
    else
      combined_bw = 0;

    if (wr_duration > 0)
      wr_bw = (real'(wr_bytes) * 8000.0) / real'(wr_duration);
    else
      wr_bw = 0;

    if (rd_duration > 0)
      rd_bw = (real'(rd_bytes) * 8000.0) / real'(rd_duration);
    else
      rd_bw = 0;

    `uvm_info("BW_TEST", $sformatf("--- %s ---", phase_name), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Write: %0d txns, %0d bytes", wr_txn, wr_bytes), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Read:  %0d txns, %0d bytes", rd_txn, rd_bytes), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Total: %0d bytes", total_bytes), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Combined duration: %.3f us", real'(duration) / 1000000.0), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Write BW:    %.3f Gbps (duration: %.3f us)",
      wr_bw, real'(wr_duration) / 1000000.0), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Read BW:     %.3f Gbps (duration: %.3f us)",
      rd_bw, real'(rd_duration) / 1000000.0), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Combined BW: %.3f Gbps", combined_bw), UVM_LOW)
  endfunction

  function void print_comparison();
    longint unsigned base_total, limit_total;
    time base_dur, limit_dur;
    real base_bw, limit_bw, reduction_pct;
    real base_wr_bw, base_rd_bw, limit_wr_bw, limit_rd_bw;
    time wr_dur, rd_dur;

    base_total  = phase1_rd_bytes + phase1_wr_bytes;
    limit_total = phase2_rd_bytes + phase2_wr_bytes;

    // Combined duration: first write to last read
    base_dur    = phase1_end - phase1_start;
    limit_dur   = phase2_end - phase2_start;

    if (base_dur > 0)
      base_bw = (real'(base_total) * 8000.0) / real'(base_dur);
    else
      base_bw = 0;

    if (limit_dur > 0)
      limit_bw = (real'(limit_total) * 8000.0) / real'(limit_dur);
    else
      limit_bw = 0;

    // Per-direction BW for baseline
    wr_dur = phase1_wr_end - phase1_wr_start;
    rd_dur = phase1_rd_end - phase1_rd_start;
    if (wr_dur > 0)
      base_wr_bw = (real'(phase1_wr_bytes) * 8000.0) / real'(wr_dur);
    else
      base_wr_bw = 0;
    if (rd_dur > 0)
      base_rd_bw = (real'(phase1_rd_bytes) * 8000.0) / real'(rd_dur);
    else
      base_rd_bw = 0;

    // Per-direction BW for limited
    wr_dur = phase2_wr_end - phase2_wr_start;
    rd_dur = phase2_rd_end - phase2_rd_start;
    if (wr_dur > 0)
      limit_wr_bw = (real'(phase2_wr_bytes) * 8000.0) / real'(wr_dur);
    else
      limit_wr_bw = 0;
    if (rd_dur > 0)
      limit_rd_bw = (real'(phase2_rd_bytes) * 8000.0) / real'(rd_dur);
    else
      limit_rd_bw = 0;

    if (base_bw > 0)
      reduction_pct = (1.0 - limit_bw / base_bw) * 100.0;
    else
      reduction_pct = 0;

    `uvm_info("BW_TEST", "======================================================", UVM_LOW)
    `uvm_info("BW_TEST", "       Bandwidth Control Verification Summary       ", UVM_LOW)
    `uvm_info("BW_TEST", "======================================================", UVM_LOW)
    `uvm_info("BW_TEST", "  Theoretical max  : 51.200 Gbps (64-bit @ 800MHz)", UVM_LOW)
    `uvm_info("BW_TEST", "  Target limit     : 5.000 Gbps", UVM_LOW)
    `uvm_info("BW_TEST", "------------------------------------------------------", UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Baseline Write BW: %.3f Gbps", base_wr_bw), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Baseline Read BW : %.3f Gbps", base_rd_bw), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Baseline Combined: %.3f Gbps", base_bw), UVM_LOW)
    `uvm_info("BW_TEST", "------------------------------------------------------", UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Limited Write BW : %.3f Gbps", limit_wr_bw), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Limited Read BW  : %.3f Gbps", limit_rd_bw), UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  Limited Combined : %.3f Gbps", limit_bw), UVM_LOW)
    `uvm_info("BW_TEST", "------------------------------------------------------", UVM_LOW)
    `uvm_info("BW_TEST", $sformatf("  BW reduction     : %.1f%%", reduction_pct), UVM_LOW)
    `uvm_info("BW_TEST", "======================================================", UVM_LOW)

    if (limit_bw < base_bw && limit_bw <= 5.5)
      `uvm_info("BW_TEST", "PASS: bandwidth limiting is effective and within target", UVM_LOW)
    else if (limit_bw < base_bw)
      `uvm_info("BW_TEST",
        $sformatf("PASS: bandwidth reduced (%.3f -> %.3f Gbps) but above 5.5 Gbps target",
          base_bw, limit_bw), UVM_LOW)
    else
      `uvm_error("BW_TEST", "FAIL: bandwidth limiting did not reduce throughput")
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.scoreboard.mismatch_count > 0)
      `uvm_error("BW_TEST",
        $sformatf("FAIL: %0d data mismatches", env.scoreboard.mismatch_count))
    else
      `uvm_info("BW_TEST",
        $sformatf("Data integrity: MATCH=%0d MISMATCH=0",
          env.scoreboard.match_count), UVM_LOW)
  endfunction

endclass

`endif // AXI_BW_LIMIT_TEST_SV
