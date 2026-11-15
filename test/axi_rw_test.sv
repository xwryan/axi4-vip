// test/axi_rw_test.sv
`ifndef AXI_RW_TEST_SV
`define AXI_RW_TEST_SV

// =========================================================================
// Helper sequence: writes N transactions, then reads them all back
// (must be defined before axi_rw_test which uses it)
// =========================================================================
class axi_rw_integrity_seq extends axi_base_seq;

  `uvm_object_utils(axi_rw_integrity_seq)

  // Typedef for a dynamic byte array (avoids VCS jagged-array limitation)
  typedef bit [7:0] byte_da_t[];

  int unsigned        num_txns       = 4;
  bit                 use_burst      = 0;
  axi_burst_type_e   burst_type_sel = AXI_INCR;

  function new(string name = "axi_rw_integrity_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [63:0]  addrs[];
    bit [7:0]   burst_lens[];
    bit [2:0]   burst_sizes[];
    byte_da_t   wr_datas[];

    addrs       = new[num_txns];
    burst_lens  = new[num_txns];
    burst_sizes = new[num_txns];
    wr_datas    = new[num_txns];

    // Generate addresses and data for each transaction
    for (int t = 0; t < num_txns; t++) begin
      bit [2:0] bsize;
      bit [7:0] blen;
      int unsigned num_bytes;

      // Use full bus-width burst_size for reliable byte-lane alignment
      bsize = 3'h3;  // 8 bytes per beat (matches 64-bit bus width)

      if (use_burst) begin
        case (burst_type_sel)
          AXI_FIXED: blen = 8'h03;  // 4 beats
          AXI_WRAP:  blen = 8'h03;  // 4 beats (valid for WRAP)
          default:   blen = 8'h03;  // 4 beats INCR
        endcase
      end else begin
        blen = 8'h00;  // single beat
      end

      num_bytes = (blen + 1) * (1 << bsize);

      // Addresses: well-separated, aligned to beat size, within 4KB boundary
      addrs[t]       = 64'h0000_1000 + t * 64'h100;
      burst_lens[t]  = blen;
      burst_sizes[t] = bsize;

      // Create write data with recognizable pattern
      wr_datas[t] = new[num_bytes];
      for (int i = 0; i < num_bytes; i++)
        wr_datas[t][i] = (t * 32 + i) & 8'hFF;
    end

    // Phase 1: Write all transactions
    for (int t = 0; t < num_txns; t++) begin
      `uvm_info("RW_SEQ", $sformatf(
        "WRITE[%0d] addr=0x%0h len=%0d size=%0d type=%s bytes=%0d",
        t, addrs[t], burst_lens[t], burst_sizes[t],
        burst_type_sel.name(), wr_datas[t].size()), UVM_MEDIUM)

      do_write(
        .addr       (addrs[t]),
        .data       (wr_datas[t]),
        .burst_len  (burst_lens[t]),
        .burst_size (burst_sizes[t]),
        .burst_type (burst_type_sel),
        .id         (16'(t))
      );
    end

    // Phase 2: Read all back (scoreboard will compare with ref model)
    for (int t = 0; t < num_txns; t++) begin
      axi_seq_item rsp;
      `uvm_info("RW_SEQ", $sformatf(
        "READ[%0d] addr=0x%0h len=%0d size=%0d type=%s",
        t, addrs[t], burst_lens[t], burst_sizes[t],
        burst_type_sel.name()), UVM_MEDIUM)

      do_read(
        .addr       (addrs[t]),
        .burst_len  (burst_lens[t]),
        .burst_size (burst_sizes[t]),
        .burst_type (burst_type_sel),
        .id         (16'(t)),
        .rsp        (rsp)
      );

      `uvm_info("RW_SEQ", $sformatf(
        "READ[%0d] complete resp=%s rdata_bytes=%0d",
        t, (rsp.resp.size() > 0) ? rsp.resp[0].name() : "N/A",
        rsp.rdata.size()), UVM_MEDIUM)
    end
  endtask

endclass

// =========================================================================
// Read/Write data integrity test.
// =========================================================================
class axi_rw_test extends axi_base_test;

  `uvm_component_utils(axi_rw_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.has_scoreboard     = 1;
    cfg.has_coverage       = 1;
    cfg.has_protocol_check = 1;
    cfg.slave_cfg.resp_delay_min = 0;
    cfg.slave_cfg.resp_delay_max = 3;
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "axi_rw_test: start");

    test_single_beat_incr();
    test_burst_incr();
    test_burst_fixed();
    test_burst_wrap();
    test_mixed_addresses();

    phase.drop_objection(this, "axi_rw_test: done");
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("AXI_RW_TEST", $sformatf(
      "Scoreboard: MATCH=%0d  MISMATCH=%0d",
      env.scoreboard.match_count, env.scoreboard.mismatch_count), UVM_LOW)

    if (env.scoreboard.match_count == 0)
      `uvm_error("AXI_RW_TEST",
        "FAIL: scoreboard match_count is 0 -- no read comparisons occurred")

    if (env.scoreboard.mismatch_count > 0)
      `uvm_error("AXI_RW_TEST",
        $sformatf("FAIL: scoreboard mismatch_count=%0d",
          env.scoreboard.mismatch_count))

    if (env.scoreboard.match_count > 0 && env.scoreboard.mismatch_count == 0)
      `uvm_info("AXI_RW_TEST",
        $sformatf("PASS: all %0d read-back comparisons matched",
          env.scoreboard.match_count), UVM_LOW)
  endfunction

  virtual task test_single_beat_incr();
    axi_rw_integrity_seq seq;
    `uvm_info("AXI_RW_TEST", "=== Sub-test: Single-beat INCR ===", UVM_LOW)
    seq = axi_rw_integrity_seq::type_id::create("single_incr_seq");
    seq.num_txns    = 4;
    seq.use_burst   = 0;
    seq.burst_type_sel = AXI_INCR;
    seq.start(env.master_agent.sequencer);
  endtask

  virtual task test_burst_incr();
    axi_rw_integrity_seq seq;
    `uvm_info("AXI_RW_TEST", "=== Sub-test: Burst INCR ===", UVM_LOW)
    seq = axi_rw_integrity_seq::type_id::create("burst_incr_seq");
    seq.num_txns    = 4;
    seq.use_burst   = 1;
    seq.burst_type_sel = AXI_INCR;
    seq.start(env.master_agent.sequencer);
  endtask

  virtual task test_burst_fixed();
    axi_rw_integrity_seq seq;
    `uvm_info("AXI_RW_TEST", "=== Sub-test: Burst FIXED ===", UVM_LOW)
    seq = axi_rw_integrity_seq::type_id::create("burst_fixed_seq");
    seq.num_txns    = 4;
    seq.use_burst   = 1;
    seq.burst_type_sel = AXI_FIXED;
    seq.start(env.master_agent.sequencer);
  endtask

  virtual task test_burst_wrap();
    axi_rw_integrity_seq seq;
    `uvm_info("AXI_RW_TEST", "=== Sub-test: Burst WRAP ===", UVM_LOW)
    seq = axi_rw_integrity_seq::type_id::create("burst_wrap_seq");
    seq.num_txns    = 4;
    seq.use_burst   = 1;
    seq.burst_type_sel = AXI_WRAP;
    seq.start(env.master_agent.sequencer);
  endtask

  virtual task test_mixed_addresses();
    axi_rw_integrity_seq seq;
    `uvm_info("AXI_RW_TEST", "=== Sub-test: Mixed addresses ===", UVM_LOW)
    seq = axi_rw_integrity_seq::type_id::create("mixed_seq");
    seq.num_txns    = 8;
    seq.use_burst   = 1;
    seq.burst_type_sel = AXI_INCR;
    seq.start(env.master_agent.sequencer);
  endtask

endclass

`endif // AXI_RW_TEST_SV
