// test/axi_mass_rw_test.sv
`ifndef AXI_MASS_RW_TEST_SV
`define AXI_MASS_RW_TEST_SV

// =========================================================================
// Helper sequence: write-only phase -- sends N writes with varying burst
// lengths, INCR burst type, full bus-width (size=3), 8-byte aligned addrs.
// =========================================================================
class axi_mass_wr_seq extends axi_base_seq;

  `uvm_object_utils(axi_mass_wr_seq)

  int unsigned num_txns = 1000;

  function new(string name = "axi_mass_wr_seq");
    super.new(name);
  endfunction

  virtual task body();
    int unsigned bl_pool[5] = '{0, 1, 3, 7, 15};

    for (int i = 0; i < num_txns; i++) begin
      bit [7:0]    wr_data[];
      bit [63:0]   addr;
      bit [7:0]    burst_len;
      int unsigned num_bytes;

      burst_len = bl_pool[i % 5];
      num_bytes = (burst_len + 1) * 8;
      addr = 64'h0000_4000 + i * 64'h100;

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

      if ((i > 0) && ((i % 2000) == 0))
        `uvm_info("MASS_WR_SEQ",
          $sformatf("Write progress: %0d / %0d", i, num_txns), UVM_LOW)
    end

    `uvm_info("MASS_WR_SEQ",
      $sformatf("All %0d writes sent", num_txns), UVM_LOW)
  endtask

endclass

// =========================================================================
// Helper sequence: read-only phase -- sends N reads matching the writes.
// =========================================================================
class axi_mass_rd_seq extends axi_base_seq;

  `uvm_object_utils(axi_mass_rd_seq)

  int unsigned num_txns = 1000;

  function new(string name = "axi_mass_rd_seq");
    super.new(name);
  endfunction

  virtual task body();
    int unsigned bl_pool[5] = '{0, 1, 3, 7, 15};

    for (int i = 0; i < num_txns; i++) begin
      axi_seq_item rsp;
      bit [63:0]   addr;
      bit [7:0]    burst_len;

      burst_len = bl_pool[i % 5];
      addr = 64'h0000_4000 + i * 64'h100;

      do_read(
        .addr       (addr),
        .burst_len  (burst_len),
        .burst_size (3'h3),
        .burst_type (AXI_INCR),
        .id         (16'(i & 16'hF)),
        .rsp        (rsp)
      );

      if ((i > 0) && ((i % 2000) == 0))
        `uvm_info("MASS_RD_SEQ",
          $sformatf("Read progress: %0d / %0d", i, num_txns), UVM_LOW)
    end

    `uvm_info("MASS_RD_SEQ",
      $sformatf("All %0d reads sent", num_txns), UVM_LOW)
  endtask

endclass

// =========================================================================
// Mass read/write stress test -- 1000 writes then 1000 reads.
// Uses wait_for_idle (from axi_base_test) to drain writes before reads.
// =========================================================================
class axi_mass_rw_test extends axi_base_test;

  `uvm_component_utils(axi_mass_rw_test)

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
    axi_mass_wr_seq wr_seq;
    axi_mass_rd_seq rd_seq;
    phase.raise_objection(this, "axi_mass_rw_test: start");

    `uvm_info("AXI_MASS_RW_TEST",
      "=== Starting 10000-pair mass read/write stress test ===", UVM_LOW)

    // Phase 1: Send all 10000 writes
    wr_seq = axi_mass_wr_seq::type_id::create("mass_wr_seq");
    wr_seq.num_txns = 10000;
    wr_seq.start(env.master_agent.sequencer);

    // Drain: wait for all writes to complete on the bus
    `uvm_info("AXI_MASS_RW_TEST",
      "All writes sent, waiting for bus drain...", UVM_LOW)
    wait_for_idle();
    `uvm_info("AXI_MASS_RW_TEST",
      "Write drain complete, starting reads...", UVM_LOW)

    // Phase 2: Send all 10000 reads
    rd_seq = axi_mass_rd_seq::type_id::create("mass_rd_seq");
    rd_seq.num_txns = 10000;
    rd_seq.start(env.master_agent.sequencer);

    phase.drop_objection(this, "axi_mass_rw_test: done");
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("AXI_MASS_RW_TEST", $sformatf(
      "Scoreboard: MATCH=%0d  MISMATCH=%0d",
      env.scoreboard.match_count, env.scoreboard.mismatch_count), UVM_LOW)

    if (env.scoreboard.match_count == 0)
      `uvm_error("AXI_MASS_RW_TEST",
        "FAIL: scoreboard match_count is 0 -- no read comparisons occurred")

    if (env.scoreboard.mismatch_count > 0)
      `uvm_error("AXI_MASS_RW_TEST",
        $sformatf("FAIL: %0d scoreboard mismatch(es) detected",
          env.scoreboard.mismatch_count))

    if (env.scoreboard.match_count > 0 && env.scoreboard.mismatch_count == 0)
      `uvm_info("AXI_MASS_RW_TEST",
        $sformatf("PASS: all %0d read-back comparisons matched",
          env.scoreboard.match_count), UVM_LOW)

    // Print performance statistics
    env.perf_monitor.print_stats("Mass RW Stress");
  endfunction

endclass

`endif // AXI_MASS_RW_TEST_SV
