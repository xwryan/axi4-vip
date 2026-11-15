`ifndef AXI_HIGH_TRAFFIC_TEST_SV
`define AXI_HIGH_TRAFFIC_TEST_SV

class axi_high_traffic_seq extends axi_base_seq;

  `uvm_object_utils(axi_high_traffic_seq)

  int unsigned txn_count = 20_000;
  int unsigned window    = 32;
  int unsigned burst_max = 16;

  int unsigned issued_wr;
  int unsigned completed_wr;
  int unsigned issued_rd;
  int unsigned completed_rd;

  function new(string name = "axi_high_traffic_seq");
    super.new(name);
  endfunction

  protected function int unsigned beats_for(int unsigned index);
    int unsigned beats;

    case (index % 4)
      0: beats = 1;
      1: beats = 4;
      2: beats = 8;
      default: beats = 16;
    endcase
    while (beats > burst_max)
      beats = (beats == 16) ? 8 :
              (beats == 8)  ? 4 : 1;
    return beats;
  endfunction

  protected task issue_pattern_write(
    input  int unsigned index,
    input  bit [63:0] base,
    output axi_seq_item req
  );
    int unsigned beats;
    bit [7:0] data[];

    beats = beats_for(index);
    data = new[beats * 8];
    foreach (data[j])
      data[j] = (index * 17 + j * 3) & 8'hff;
    issue_write(base + index * 64'h100, data, beats - 1, 3,
                AXI_INCR, index % (1 << cfg.id_width), req);
    issued_wr++;
  endtask

  protected task issue_pattern_read(
    input  int unsigned index,
    input  bit [63:0] base,
    output axi_seq_item req
  );
    int unsigned beats;

    beats = beats_for(index);
    issue_read(base + index * 64'h100, beats - 1, 3,
               AXI_INCR, index % (1 << cfg.id_width), req);
    issued_rd++;
  endtask

  protected task reap_write(ref axi_seq_item pending[$]);
    axi_seq_item req;
    axi_seq_item rsp;

    if (pending.size() == 0)
      `uvm_fatal("HIGH_TRAFFIC", "write reap called with an empty queue")
    req = pending.pop_front();
    wait_response(req, rsp);
    if (rsp.aborted)
      `uvm_error("HIGH_TRAFFIC", "write response was aborted")
    if (rsp.resp.size() != 1)
      `uvm_error("HIGH_TRAFFIC", $sformatf(
        "write response count=%0d expected=1", rsp.resp.size()))
    completed_wr++;
  endtask

  protected task reap_read(ref axi_seq_item pending[$]);
    axi_seq_item req;
    axi_seq_item rsp;

    if (pending.size() == 0)
      `uvm_fatal("HIGH_TRAFFIC", "read reap called with an empty queue")
    req = pending.pop_front();
    wait_response(req, rsp);
    if (rsp.aborted)
      `uvm_error("HIGH_TRAFFIC", "read response was aborted")
    if (rsp.resp.size() != req.burst_len + 1)
      `uvm_error("HIGH_TRAFFIC", $sformatf(
        "read response count=%0d expected=%0d",
        rsp.resp.size(), req.burst_len + 1))
    if (rsp.rdata.size() != rsp.get_total_bytes())
      `uvm_error("HIGH_TRAFFIC", $sformatf(
        "read data bytes=%0d expected=%0d",
        rsp.rdata.size(), rsp.get_total_bytes()))
    completed_rd++;
  endtask

  virtual task body();
    const bit [63:0] STABLE_BASE      = 64'h0100_0000;
    const bit [63:0] MIXED_WRITE_BASE = 64'h4000_0000;
    int unsigned stable_count;
    int unsigned mixed_count;
    axi_seq_item pending_wr[$];
    axi_seq_item pending_rd[$];

    stable_count = txn_count / 2;
    mixed_count  = txn_count - stable_count;

    for (int unsigned i = 0; i < stable_count; i++) begin
      axi_seq_item req;

      issue_pattern_write(i, STABLE_BASE, req);
      pending_wr.push_back(req);
      if (pending_wr.size() >= window)
        reap_write(pending_wr);
    end
    while (pending_wr.size() != 0)
      reap_write(pending_wr);

    for (int unsigned i = 0; i < stable_count; i++) begin
      axi_seq_item req;

      issue_pattern_read(i, STABLE_BASE, req);
      pending_rd.push_back(req);
      if (pending_rd.size() >= window)
        reap_read(pending_rd);
    end
    while (pending_rd.size() != 0)
      reap_read(pending_rd);

    for (int unsigned i = 0; i < mixed_count; i++) begin
      int unsigned write_index;
      int unsigned read_index;
      axi_seq_item wr_req;
      axi_seq_item rd_req;

      write_index = stable_count + i;
      read_index  = i % stable_count;
      issue_pattern_write(write_index, MIXED_WRITE_BASE, wr_req);
      pending_wr.push_back(wr_req);
      issue_pattern_read(read_index, STABLE_BASE, rd_req);
      pending_rd.push_back(rd_req);
      if (pending_wr.size() >= window)
        reap_write(pending_wr);
      if (pending_rd.size() >= window)
        reap_read(pending_rd);
      if (((i + 1) % 5000) == 0)
        `uvm_info("HIGH_TRAFFIC", $sformatf(
          "Mixed progress: %0d / %0d", i + 1, mixed_count), UVM_LOW)
    end
    while (pending_wr.size() != 0)
      reap_write(pending_wr);
    while (pending_rd.size() != 0)
      reap_read(pending_rd);
  endtask

endclass

class axi_high_traffic_test extends axi_base_test;

  `uvm_component_utils(axi_high_traffic_test)

  int unsigned txn_count = 20_000;
  int unsigned window    = 32;
  int unsigned burst_max = 16;

  axi_high_traffic_seq seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  protected function bit parse_decimal_plusarg(
    input  string       args[$],
    input  string       arg_name,
    output int unsigned parsed_value
  );
    string exact_name;
    string prefix;
    string raw_value;
    int unsigned match_count;
    int unsigned max_value;

    parsed_value = 0;
    match_count = 0;
    raw_value = "";
    exact_name = {"+", arg_name};
    prefix     = {exact_name, "="};
    foreach (args[i]) begin
      if (args[i] == exact_name) begin
        match_count++;
        raw_value = "";
      end else if (args[i].len() >= prefix.len() &&
                   args[i].substr(0, prefix.len() - 1) == prefix) begin
        match_count++;
        if (args[i].len() == prefix.len())
          raw_value = "";
        else
          raw_value = args[i].substr(prefix.len(), args[i].len() - 1);
      end
    end

    if (match_count == 0)
      return 0;
    if (match_count > 1) begin
      `uvm_fatal("HIGH_TRAFFIC_CFG", $sformatf(
        "+%s was specified %0d times; exactly one definition is allowed",
        arg_name, match_count))
      return 1;
    end
    if (raw_value.len() == 0) begin
      `uvm_fatal("HIGH_TRAFFIC_CFG", $sformatf(
        "+%s requires non-empty ASCII decimal digits", arg_name))
      return 1;
    end

    max_value = '1;
    for (int unsigned i = 0; i < raw_value.len(); i++) begin
      byte         character;
      int unsigned digit;

      character = raw_value.getc(i);
      if (character < 8'd48 || character > 8'd57) begin
        `uvm_fatal("HIGH_TRAFFIC_CFG", $sformatf(
          "+%s value '%s' must contain only ASCII decimal digits 0-9",
          arg_name, raw_value))
        return 1;
      end
      digit = character - 8'd48;
      if (parsed_value > (max_value - digit) / 10) begin
        `uvm_fatal("HIGH_TRAFFIC_CFG", $sformatf(
          "+%s decimal value '%s' exceeds uint32 maximum 4294967295",
          arg_name, raw_value))
        return 1;
      end
      parsed_value = parsed_value * 10 + digit;
    end
    return 1;
  endfunction

  virtual function void configure_test();
    uvm_cmdline_processor cmdline;
    string                args[$];
    int unsigned          parsed_value;

    super.configure_test();
    cmdline = uvm_cmdline_processor::get_inst();
    cmdline.get_args(args);
    if (parse_decimal_plusarg(args, "AXI_TRAFFIC_TXNS", parsed_value)) begin
      if (parsed_value < 4)
        `uvm_fatal("HIGH_TRAFFIC_CFG", $sformatf(
          "AXI_TRAFFIC_TXNS=%0d must be at least 4 to exercise concurrent traffic",
          parsed_value))
      else
        txn_count = parsed_value;
    end
    if (parse_decimal_plusarg(
          args, "AXI_TRAFFIC_OUTSTANDING", parsed_value)) begin
      if (parsed_value < 2)
        `uvm_fatal("HIGH_TRAFFIC_CFG", $sformatf(
          "AXI_TRAFFIC_OUTSTANDING=%0d must be at least 2 to measure a non-trivial peak",
          parsed_value))
      else
        window = parsed_value;
    end
    if (parse_decimal_plusarg(
          args, "AXI_TRAFFIC_BURST_MAX", parsed_value)) begin
      if (!(parsed_value inside {1, 4, 8, 16}))
        `uvm_fatal("HIGH_TRAFFIC_CFG", $sformatf(
          "AXI_TRAFFIC_BURST_MAX=%0d must be one of 1, 4, 8, or 16",
          parsed_value))
      else
        burst_max = $unsigned(parsed_value);
    end

    cfg.resolve_agent_configs();
    cfg.has_scoreboard = 1;
    cfg.has_coverage = 0;
    cfg.master_cfg.max_outstanding_wr = window;
    cfg.master_cfg.max_outstanding_rd = window;
    cfg.slave_cfg.resp_delay_min = 2;
    cfg.slave_cfg.resp_delay_max = 2;
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit seq_done;
    longint unsigned max_cycles;

    phase.raise_objection(this, "axi_high_traffic_test: start");
    seq = axi_high_traffic_seq::type_id::create("seq");
    seq.txn_count = txn_count;
    seq.window    = window;
    seq.burst_max = burst_max;
    max_cycles = 100_000 + longint'(txn_count) *
                 (128 + longint'(burst_max) * 4);

    fork : high_traffic_watchdog
      begin
        seq.start(env.master_agent.sequencer);
        seq_done = 1;
      end
      begin
        for (longint unsigned cycle = 0;
             cycle < max_cycles && !seq_done; cycle++)
          @(posedge cfg.vif.aclk);
        if (!seq_done)
          `uvm_fatal("HIGH_TRAFFIC_TIMEOUT", $sformatf(
            "traffic did not complete within %0d cycles", max_cycles))
      end
    join_any
    disable high_traffic_watchdog;

    wait_for_idle();
    phase.drop_objection(this, "axi_high_traffic_test: done");
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("HIGH_TRAFFIC", $sformatf(
      "Traffic counts: issued_wr=%0d completed_wr=%0d issued_rd=%0d completed_rd=%0d expected=%0d",
      seq.issued_wr, seq.completed_wr, seq.issued_rd, seq.completed_rd,
      txn_count), UVM_LOW)
    if (seq.issued_wr != txn_count || seq.completed_wr != txn_count ||
        seq.issued_rd != txn_count || seq.completed_rd != txn_count)
      `uvm_error("HIGH_TRAFFIC", "issued/completed transaction counts are not exact")

    `uvm_info("HIGH_TRAFFIC", $sformatf(
      "Scoreboard: MATCH=%0d MISMATCH=%0d expected=%0d/0",
      env.scoreboard.match_count, env.scoreboard.mismatch_count, txn_count),
      UVM_LOW)
    if (env.scoreboard.match_count != txn_count ||
        env.scoreboard.mismatch_count != 0)
      `uvm_error("HIGH_TRAFFIC", "scoreboard counts are not exact")

    `uvm_info("HIGH_TRAFFIC", $sformatf(
      "Performance: total_wr_txn=%0d total_rd_txn=%0d peak_wr_outstanding=%0d peak_rd_outstanding=%0d window=%0d",
      env.perf_monitor.total_wr_txn, env.perf_monitor.total_rd_txn,
      env.perf_monitor.peak_wr_outstanding,
      env.perf_monitor.peak_rd_outstanding, window), UVM_LOW)
    if (env.perf_monitor.total_wr_txn != txn_count ||
        env.perf_monitor.total_rd_txn != txn_count)
      `uvm_error("HIGH_TRAFFIC", "performance transaction counts are not exact")
    if (env.perf_monitor.peak_wr_outstanding < 2 ||
        env.perf_monitor.peak_wr_outstanding > window)
      `uvm_error("HIGH_TRAFFIC", "write outstanding peak is outside [2, window]")
    if (env.perf_monitor.peak_rd_outstanding < 2 ||
        env.perf_monitor.peak_rd_outstanding > window)
      `uvm_error("HIGH_TRAFFIC", "read outstanding peak is outside [2, window]")
    if (!env.is_idle())
      `uvm_error("HIGH_TRAFFIC", "environment did not drain")

    env.perf_monitor.print_stats("High Traffic");
  endfunction

endclass

`endif // AXI_HIGH_TRAFFIC_TEST_SV
