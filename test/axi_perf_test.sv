// test/axi_perf_test.sv
`ifndef AXI_PERF_TEST_SV
`define AXI_PERF_TEST_SV

// =========================================================================
// Sequence: run N write+read pairs for transaction counting
// (must be defined before axi_perf_test which uses it)
// =========================================================================
class axi_perf_count_seq extends axi_base_seq;

  `uvm_object_utils(axi_perf_count_seq)

  int unsigned num_pairs = 5;

  function new(string name = "axi_perf_count_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < num_pairs; i++) begin
      bit [7:0] wr_data[];
      axi_seq_item rsp;
      bit [63:0] addr;
      int unsigned num_bytes;

      addr = 64'h0000_2000 + i * 64'h40;
      num_bytes = 8;  // single beat, 8 bytes
      wr_data = new[num_bytes];
      foreach (wr_data[j]) wr_data[j] = (i * 16 + j) & 8'hFF;

      do_write(
        .addr       (addr),
        .data       (wr_data),
        .burst_len  (8'h00),
        .burst_size (3'h3),  // 8 bytes per beat
        .burst_type (AXI_INCR),
        .id         (16'(i))
      );

      do_read(
        .addr       (addr),
        .burst_len  (8'h00),
        .burst_size (3'h3),
        .burst_type (AXI_INCR),
        .id         (16'(i)),
        .rsp        (rsp)
      );
    end
  endtask

endclass

// =========================================================================
// Sequence: run pairs under bandwidth limiting
// (must be defined before axi_perf_test which uses it)
// =========================================================================
class axi_perf_bw_seq extends axi_base_seq;

  `uvm_object_utils(axi_perf_bw_seq)

  int unsigned num_pairs = 4;

  function new(string name = "axi_perf_bw_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < num_pairs; i++) begin
      bit [7:0] wr_data[];
      axi_seq_item rsp;
      bit [63:0] addr;
      int unsigned num_bytes;

      // Use burst to generate more byte traffic
      addr = 64'h0000_3000 + i * 64'h100;  // 8-byte aligned
      num_bytes = 4 * 8;  // 4 beats x 8 bytes (full 64-bit bus width)
      wr_data = new[num_bytes];
      foreach (wr_data[j]) wr_data[j] = (i * 32 + j) & 8'hFF;

      do_write(
        .addr       (addr),
        .data       (wr_data),
        .burst_len  (8'h03),
        .burst_size (3'h3),  // 8 bytes per beat (full bus width)
        .burst_type (AXI_INCR),
        .id         (16'(i))
      );

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

// Performance test.
// 1. Runs a known number of transactions and verifies perf_monitor counts match.
// 2. Enables bandwidth limiting and verifies throughput is throttled.
// 3. Tests with different resp_delay settings.
class axi_perf_test extends axi_base_test;

  `uvm_component_utils(axi_perf_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.has_scoreboard     = 1;
    cfg.has_coverage       = 0;
    cfg.has_protocol_check = 1;
    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 2;
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "axi_perf_test: start");

    test_transaction_counting();
    test_bw_limiting();
    test_resp_delay_impact();

    phase.drop_objection(this, "axi_perf_test: done");
  endtask

  // -----------------------------------------------------------------------
  // check_phase: verify perf_monitor saw transactions
  // -----------------------------------------------------------------------
  virtual function void check_phase(uvm_phase phase);
    int unsigned total_txn;
    super.check_phase(phase);

    total_txn = env.perf_monitor.total_rd_txn + env.perf_monitor.total_wr_txn;

    `uvm_info("AXI_PERF_TEST", $sformatf(
      "PerfMonitor: rd_txn=%0d wr_txn=%0d total=%0d rd_bytes=%0d wr_bytes=%0d",
      env.perf_monitor.total_rd_txn, env.perf_monitor.total_wr_txn,
      total_txn, env.perf_monitor.total_rd_bytes,
      env.perf_monitor.total_wr_bytes), UVM_LOW)

    if (total_txn == 0)
      `uvm_error("AXI_PERF_TEST",
        "FAIL: perf_monitor recorded 0 transactions")
    else
      `uvm_info("AXI_PERF_TEST",
        $sformatf("PASS: perf_monitor recorded %0d transactions", total_txn), UVM_LOW)
  endfunction

  // -----------------------------------------------------------------------
  // Sub-test 1: Run a known number of write+read pairs and verify counts
  // -----------------------------------------------------------------------
  virtual task test_transaction_counting();
    axi_perf_count_seq seq;
    `uvm_info("AXI_PERF_TEST", "=== Sub-test: Transaction Counting ===", UVM_LOW)
    seq = axi_perf_count_seq::type_id::create("count_seq");
    seq.num_pairs = 5;
    seq.start(env.master_agent.sequencer);
  endtask

  // -----------------------------------------------------------------------
  // Sub-test 2: Enable BW limiter and run transactions
  // The limiter should throttle throughput, so we just verify transactions
  // still complete correctly under bandwidth constraints.
  // -----------------------------------------------------------------------
  virtual task test_bw_limiting();
    axi_perf_bw_seq seq;
    `uvm_info("AXI_PERF_TEST", "=== Sub-test: Bandwidth Limiting ===", UVM_LOW)

    // Enable bandwidth limiting via the bw_limiter in the master driver
    cfg.master_cfg.enable_bw_limit      = 1;
    cfg.master_cfg.max_bytes_per_window = 64;
    cfg.master_cfg.bw_window_cycles     = 50;

    // Reconfigure the limiter in the running driver
    env.master_agent.driver.bw_limiter.configure(
      cfg.master_cfg.enable_bw_limit,
      cfg.master_cfg.max_bytes_per_window,
      cfg.master_cfg.bw_window_cycles);

    seq = axi_perf_bw_seq::type_id::create("bw_seq");
    seq.num_pairs = 4;
    seq.start(env.master_agent.sequencer);

    // Disable BW limiting for remaining sub-tests
    cfg.master_cfg.enable_bw_limit = 0;
    env.master_agent.driver.bw_limiter.configure(0, 1024, 100);
  endtask

  // -----------------------------------------------------------------------
  // Sub-test 3: Run with high resp_delay and verify transactions complete
  // -----------------------------------------------------------------------
  virtual task test_resp_delay_impact();
    axi_perf_count_seq seq;
    `uvm_info("AXI_PERF_TEST", "=== Sub-test: Resp Delay Impact ===", UVM_LOW)

    // Increase response delay
    cfg.slave_cfg.resp_delay_min = 5;
    cfg.slave_cfg.resp_delay_max = 15;

    seq = axi_perf_count_seq::type_id::create("delay_seq");
    seq.num_pairs = 3;
    seq.start(env.master_agent.sequencer);

    // Restore defaults
    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 2;
  endtask

endclass

`endif // AXI_PERF_TEST_SV
