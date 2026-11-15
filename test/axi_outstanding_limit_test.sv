`ifndef AXI_OUTSTANDING_LIMIT_TEST_SV
`define AXI_OUTSTANDING_LIMIT_TEST_SV

class axi_response_audit_master_sequencer extends axi_master_sequencer;
  `uvm_component_utils(axi_response_audit_master_sequencer)

  int unsigned response_count_baseline;
  int unsigned total_response_count;
  int unsigned history_response_count;
  int unsigned response_count_by_txn[int];
  int unsigned response_count_by_seq[int];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void prepare_response_audit();
    set_num_last_rsps(0);
    set_num_last_rsps(16);
    response_count_baseline = get_num_rsps_received();
    total_response_count = 0;
    history_response_count = 0;
    response_count_by_txn.delete();
    response_count_by_seq.delete();
  endfunction

  virtual function void check_exact_responses(
    string scenario,
    axi_seq_item first_req,
    axi_seq_item second_req
  );
    int key;
    int unsigned first_count;
    int unsigned second_count;
    int unsigned expected_seq_count;
    int unsigned unknown_count;
    int unsigned unknown_seq_count;

    total_response_count = get_num_rsps_received() - response_count_baseline;
    history_response_count = 0;
    response_count_by_txn.delete();
    response_count_by_seq.delete();
    for (int unsigned i = 0; i < get_num_last_rsps(); i++) begin
      axi_seq_item rsp;

      rsp = last_rsp(i);
      if (rsp == null)
        break;
      history_response_count++;
      response_count_by_txn[rsp.get_transaction_id()]++;
      response_count_by_seq[rsp.get_sequence_id()]++;
      if (first_req != null &&
          rsp.get_transaction_id() == first_req.get_transaction_id()) begin
        if (rsp.addr != first_req.addr ||
            rsp.get_sequence_id() != first_req.get_sequence_id())
          `uvm_error("OUT_SQR_AUDIT", $sformatf(
            "%s first response identity addr/seq=0x%0h/%0d expected=0x%0h/%0d",
            scenario, rsp.addr, rsp.get_sequence_id(), first_req.addr,
            first_req.get_sequence_id()))
        if (!rsp.aborted || rsp.resp.size() != 0 || rsp.rdata.size() != 0)
          `uvm_error("OUT_SQR_AUDIT", $sformatf(
            "%s first response aborted/resp/rdata=%0b/%0d/%0d expected=1/0/0",
            scenario, rsp.aborted, rsp.resp.size(), rsp.rdata.size()))
      end else if (second_req != null &&
                   rsp.get_transaction_id() ==
                     second_req.get_transaction_id()) begin
        if (rsp.addr != second_req.addr ||
            rsp.get_sequence_id() != second_req.get_sequence_id())
          `uvm_error("OUT_SQR_AUDIT", $sformatf(
            "%s second response identity addr/seq=0x%0h/%0d expected=0x%0h/%0d",
            scenario, rsp.addr, rsp.get_sequence_id(), second_req.addr,
            second_req.get_sequence_id()))
        if (!rsp.aborted || rsp.resp.size() != 0 || rsp.rdata.size() != 0)
          `uvm_error("OUT_SQR_AUDIT", $sformatf(
            "%s second response aborted/resp/rdata=%0b/%0d/%0d expected=1/0/0",
            scenario, rsp.aborted, rsp.resp.size(), rsp.rdata.size()))
      end
    end

    if (first_req == null || second_req == null) begin
      `uvm_error("OUT_SQR_AUDIT",
        {scenario, " sequencer audit received null request handles"})
      return;
    end
    if (response_count_by_txn.exists(first_req.get_transaction_id()))
      first_count = response_count_by_txn[first_req.get_transaction_id()];
    if (response_count_by_txn.exists(second_req.get_transaction_id()))
      second_count = response_count_by_txn[second_req.get_transaction_id()];
    foreach (response_count_by_txn[key]) begin
      if (key != first_req.get_transaction_id() &&
          key != second_req.get_transaction_id())
        unknown_count += response_count_by_txn[key];
    end
    if (first_req.get_sequence_id() == second_req.get_sequence_id()) begin
      if (response_count_by_seq.exists(first_req.get_sequence_id()))
        expected_seq_count =
          response_count_by_seq[first_req.get_sequence_id()];
    end else begin
      if (response_count_by_seq.exists(first_req.get_sequence_id()))
        expected_seq_count +=
          response_count_by_seq[first_req.get_sequence_id()];
      if (response_count_by_seq.exists(second_req.get_sequence_id()))
        expected_seq_count +=
          response_count_by_seq[second_req.get_sequence_id()];
    end
    foreach (response_count_by_seq[key]) begin
      if (key != first_req.get_sequence_id() &&
          key != second_req.get_sequence_id())
        unknown_seq_count += response_count_by_seq[key];
    end

    if (total_response_count != 2 || history_response_count != 2 ||
        history_response_count != total_response_count || first_count != 1 ||
        second_count != 1 || unknown_count != 0 ||
        expected_seq_count != 2 || unknown_seq_count != 0)
      `uvm_error("OUT_SQR_AUDIT", $sformatf(
        {"%s sequencer audit total/history=%0d/%0d first=%0d second=%0d ",
         "unknown=%0d expected_seq=%0d unknown_seq=%0d ",
         "expected=2/2/1/1/0/2/0"},
        scenario, total_response_count, history_response_count,
        first_count, second_count, unknown_count, expected_seq_count,
        unknown_seq_count))
    `uvm_info("OUT_SQR_AUDIT", $sformatf(
      {"%s sequencer audit total/history=%0d/%0d first=%0d second=%0d ",
       "unknown=%0d expected_seq=%0d unknown_seq=%0d"},
      scenario, total_response_count, history_response_count,
      first_count, second_count, unknown_count, expected_seq_count,
      unknown_seq_count), UVM_LOW)
  endfunction
endclass

class axi_handoff_blocking_master_sequencer extends
  axi_response_audit_master_sequencer;
  `uvm_component_utils(axi_handoff_blocking_master_sequencer)

  int unsigned handoff_count;
  bit handoff_ready;
  bit release_handoff;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task try_next_item(output axi_seq_item t);
    super.try_next_item(t);
    if (t != null) begin
      handoff_count++;
      if (handoff_count == 2) begin
        handoff_ready = 1;
        wait (release_handoff);
      end
    end
  endtask
endclass

class axi_outstanding_limit_seq extends axi_base_seq;
  `uvm_object_utils(axi_outstanding_limit_seq)

  int unsigned num_txns = 32;

  function new(string name = "axi_outstanding_limit_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item wr_req[] = new[num_txns];
    axi_seq_item rd_req[] = new[num_txns];
    bit [7:0] data[] = new[32];

    for (int unsigned i = 0; i < num_txns; i++) begin
      foreach (data[j])
        data[j] = (i + j) & 8'hff;
      issue_write(64'h0010_0000 + i * 64'h100, data, 3, 3,
                  AXI_INCR, i % (1 << cfg.id_width), wr_req[i]);
    end
    foreach (wr_req[i]) begin
      axi_seq_item rsp;
      wait_response(wr_req[i], rsp);
      if (rsp.aborted || rsp.resp.size() != 1)
        `uvm_error("OUT_LIMIT", "invalid bounded write response")
    end

    for (int unsigned i = 0; i < num_txns; i++)
      issue_read(64'h0010_0000 + i * 64'h100, 3, 3,
                 AXI_INCR, i % (1 << cfg.id_width), rd_req[i]);
    foreach (rd_req[i]) begin
      axi_seq_item rsp;
      wait_response(rd_req[i], rsp);
      if (rsp.aborted || rsp.resp.size() != 4)
        `uvm_error("OUT_LIMIT", "invalid bounded read response")
    end
  endtask
endclass

class axi_outstanding_limit_test extends axi_base_test;
  `uvm_component_utils(axi_outstanding_limit_test)

  axi_outstanding_limit_seq seq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.has_coverage = 0;
    cfg.master_cfg.max_outstanding_wr = 4;
    cfg.master_cfg.max_outstanding_rd = 4;
    cfg.master_cfg.per_channel_bp_enable = 1;
    cfg.master_cfg.b_bp_cfg.mode = BP_FIXED_DELAY;
    cfg.master_cfg.b_bp_cfg.fixed_delay = 20;
    cfg.master_cfg.r_bp_cfg.mode = BP_FIXED_DELAY;
    cfg.master_cfg.r_bp_cfg.fixed_delay = 20;
    cfg.slave_cfg.resp_delay_min = 2;
    cfg.slave_cfg.resp_delay_max = 2;
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit seq_done;

    phase.raise_objection(this);
    seq = axi_outstanding_limit_seq::type_id::create("seq");
    fork : limit_watchdog
      begin
        seq.start(env.master_agent.sequencer);
        seq_done = 1;
      end
      begin
        repeat (20_000) @(posedge cfg.vif.aclk);
        if (!seq_done)
          `uvm_error("OUT_LIMIT",
            "bounded outstanding sequence exceeded 20000 cycles")
      end
    join_any
    disable limit_watchdog;
    wait_for_idle();
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.master_agent.driver.max_pending_wr_seen != 4)
      `uvm_error("OUT_LIMIT", $sformatf(
        "write peak=%0d expected=4",
        env.master_agent.driver.max_pending_wr_seen))
    if (env.master_agent.driver.max_pending_rd_seen != 4)
      `uvm_error("OUT_LIMIT", $sformatf(
        "read peak=%0d expected=4",
        env.master_agent.driver.max_pending_rd_seen))
    if (env.scoreboard.match_count != 32 || env.scoreboard.mismatch_count != 0)
      `uvm_error("OUT_LIMIT", $sformatf(
        "scoreboard match=%0d mismatch=%0d expected=32/0",
        env.scoreboard.match_count, env.scoreboard.mismatch_count))
    if (!env.is_idle())
      `uvm_error("OUT_LIMIT", "environment did not drain")
  endfunction
endclass

class axi_outstanding_reset_seq extends axi_base_seq;
  `uvm_object_utils(axi_outstanding_reset_seq)

  bit second_request_started;
  int unsigned aborted_count;
  int unsigned first_issue_return_count;
  int unsigned second_issue_return_count;
  int unsigned total_response_count;
  int unsigned unknown_response_count;
  int unsigned response_count_by_txn[int];
  axi_seq_item req0;
  axi_seq_item req1;
  axi_seq_item rsp0;
  axi_seq_item rsp1;

  function new(string name = "axi_outstanding_reset_seq");
    super.new(name);
  endfunction

  virtual function void put_response(uvm_sequence_item response_item);
    total_response_count++;
    response_count_by_txn[response_item.get_transaction_id()]++;
    super.put_response(response_item);
  endfunction

  virtual task body();
    bit [7:0] data[] = new[8];

    foreach (data[j])
      data[j] = j;
    issue_write(64'h0020_0000, data, 0, 3, AXI_INCR, 0, req0);
    first_issue_return_count++;
    second_request_started = 1;
    issue_write(64'h0020_0100, data, 0, 3, AXI_INCR, 1, req1);
    second_issue_return_count++;
    wait_response(req0, rsp0);
    if (rsp0.aborted)
      aborted_count++;
    wait_response(req1, rsp1);
    if (rsp1.aborted)
      aborted_count++;
  endtask

  virtual function void check_exact_reset_responses(string scenario);
    int txn_id;
    int unsigned req0_count;
    int unsigned req1_count;

    if (first_issue_return_count != 1 || second_issue_return_count != 1)
      `uvm_error("OUT_RESET", $sformatf(
        "%s issue returns first/second=%0d/%0d expected=1/1",
        scenario, first_issue_return_count, second_issue_return_count))
    if (total_response_count != 2)
      `uvm_error("OUT_RESET", $sformatf(
        "%s total responses=%0d expected=2",
        scenario, total_response_count))
    if (req0 == null || req1 == null) begin
      `uvm_error("OUT_RESET", {scenario, " did not return both requests"})
    end else begin
      if (req0.get_transaction_id() == req1.get_transaction_id())
        `uvm_error("OUT_RESET", {scenario,
          " requests reused a transaction ID"})
      if (response_count_by_txn.exists(req0.get_transaction_id()))
        req0_count = response_count_by_txn[req0.get_transaction_id()];
      if (response_count_by_txn.exists(req1.get_transaction_id()))
        req1_count = response_count_by_txn[req1.get_transaction_id()];
      if (req0_count != 1 || req1_count != 1)
        `uvm_error("OUT_RESET", $sformatf(
          "%s response counts first/second=%0d/%0d expected=1/1",
          scenario, req0_count, req1_count))
    end

    unknown_response_count = 0;
    foreach (response_count_by_txn[txn_id]) begin
      bit known_txn;

      known_txn = 0;
      if (req0 != null && txn_id == req0.get_transaction_id())
        known_txn = 1;
      if (req1 != null && txn_id == req1.get_transaction_id())
        known_txn = 1;
      if (!known_txn)
        unknown_response_count += response_count_by_txn[txn_id];
    end
    if (unknown_response_count != 0)
      `uvm_error("OUT_RESET", $sformatf(
        "%s unknown transaction responses=%0d expected=0",
        scenario, unknown_response_count))

    check_aborted_response(scenario, "first", req0, rsp0);
    check_aborted_response(scenario, "second", req1, rsp1);
    `uvm_info("OUT_RESET", $sformatf(
      "%s exact responses total=%0d first=%0d second=%0d unknown=%0d aborted=%0d",
      scenario, total_response_count, req0_count, req1_count,
      unknown_response_count, aborted_count), UVM_LOW)
  endfunction

  protected function void check_aborted_response(
    string scenario,
    string label,
    axi_seq_item req,
    axi_seq_item rsp
  );
    if (req == null || rsp == null) begin
      `uvm_error("OUT_RESET", $sformatf(
        "%s %s request or response is null", scenario, label))
      return;
    end
    if (rsp.addr != req.addr ||
        rsp.get_sequence_id() != req.get_sequence_id() ||
        rsp.get_transaction_id() != req.get_transaction_id())
      `uvm_error("OUT_RESET", $sformatf(
        "%s %s identity addr/seq/txn=0x%0h/%0d/%0d expected=0x%0h/%0d/%0d",
        scenario, label, rsp.addr, rsp.get_sequence_id(),
        rsp.get_transaction_id(), req.addr, req.get_sequence_id(),
        req.get_transaction_id()))
    if (!rsp.aborted || rsp.resp.size() != 0 || rsp.rdata.size() != 0)
      `uvm_error("OUT_RESET", $sformatf(
        "%s %s aborted/resp/rdata=%0b/%0d/%0d expected=1/0/0",
        scenario, label, rsp.aborted, rsp.resp.size(), rsp.rdata.size()))
  endfunction
endclass

class axi_outstanding_reset_test extends axi_base_test;
  `uvm_component_utils(axi_outstanding_reset_test)

  axi_outstanding_reset_seq seq;
  axi_response_audit_master_sequencer audit_sequencer;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function string get_reset_context();
    return "capacity reset";
  endfunction

  virtual function void install_master_sequencer_override();
    axi_master_sequencer::type_id::set_type_override(
      axi_response_audit_master_sequencer::get_type());
  endfunction

  virtual function void build_phase(uvm_phase phase);
    install_master_sequencer_override();
    super.build_phase(phase);
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.has_coverage = 0;
    cfg.master_cfg.max_outstanding_wr = 1;
    cfg.master_cfg.max_outstanding_rd = 1;
    cfg.master_cfg.per_channel_bp_enable = 1;
    cfg.master_cfg.b_bp_cfg.mode = BP_FIXED_DELAY;
    cfg.master_cfg.b_bp_cfg.fixed_delay = 100;
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit seq_done;

    phase.raise_objection(this);
    if (!$cast(audit_sequencer, env.master_agent.sequencer))
      `uvm_fatal("OUT_SQR_AUDIT",
        "master sequencer response audit fixture was not installed")
    audit_sequencer.prepare_response_audit();
    seq = axi_outstanding_reset_seq::type_id::create("seq");
    fork : reset_watchdog
      begin
        fork
          seq.start(env.master_agent.sequencer);
          begin
            wait (seq.second_request_started);
            repeat (2) @(posedge cfg.vif.aclk);
            if (!uvm_hdl_force("tb_top.aresetn", 1'b0))
              `uvm_fatal("OUT_RESET", "cannot force reset")
            repeat (5) @(posedge cfg.vif.aclk);
            if (!uvm_hdl_release("tb_top.aresetn"))
              `uvm_fatal("OUT_RESET", "cannot release reset")
            if (!uvm_hdl_deposit("tb_top.aresetn", 1'b1))
              `uvm_fatal("OUT_RESET", "cannot restore reset")
          end
        join
        seq_done = 1;
      end
      begin
        repeat (2_000) @(posedge cfg.vif.aclk);
        if (!seq_done)
          `uvm_error("OUT_RESET",
            "capacity reset sequence exceeded 2000 cycles")
      end
    join_any
    disable reset_watchdog;
    wait_for_idle();
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    int unsigned first_audit_count;
    int unsigned second_audit_count;
    int unsigned first_sequence_count;
    int unsigned second_sequence_count;

    super.check_phase(phase);
    seq.check_exact_reset_responses(get_reset_context());
    audit_sequencer.check_exact_responses(
      get_reset_context(), seq.req0, seq.req1);
    if (seq.req0 != null &&
        audit_sequencer.response_count_by_txn.exists(
          seq.req0.get_transaction_id()))
      first_audit_count = audit_sequencer.response_count_by_txn[
        seq.req0.get_transaction_id()];
    if (seq.req1 != null &&
        audit_sequencer.response_count_by_txn.exists(
          seq.req1.get_transaction_id()))
      second_audit_count = audit_sequencer.response_count_by_txn[
        seq.req1.get_transaction_id()];
    if (seq.req0 != null &&
        seq.response_count_by_txn.exists(seq.req0.get_transaction_id()))
      first_sequence_count =
        seq.response_count_by_txn[seq.req0.get_transaction_id()];
    if (seq.req1 != null &&
        seq.response_count_by_txn.exists(seq.req1.get_transaction_id()))
      second_sequence_count =
        seq.response_count_by_txn[seq.req1.get_transaction_id()];
    if (audit_sequencer.total_response_count != seq.total_response_count ||
        first_audit_count != first_sequence_count ||
        second_audit_count != second_sequence_count)
      `uvm_error("OUT_SQR_AUDIT", $sformatf(
        {"%s sequence/sequencer audit differs total=%0d/%0d ",
         "first=%0d/%0d second=%0d/%0d"},
        get_reset_context(), seq.total_response_count,
        audit_sequencer.total_response_count,
        first_sequence_count, first_audit_count,
        second_sequence_count, second_audit_count))
    if (seq.aborted_count != 2)
      `uvm_error("OUT_RESET", $sformatf(
        "aborted responses=%0d expected=2", seq.aborted_count))
    if (!env.is_idle())
      `uvm_error("OUT_RESET", "environment retained state after reset")
  endfunction
endclass

class axi_outstanding_short_pulse_reset_test extends
  axi_outstanding_reset_test;

  `uvm_component_utils(axi_outstanding_short_pulse_reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function string get_reset_context();
    return "short-pulse capacity reset";
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit seq_done;

    phase.raise_objection(this);
    if (!$cast(audit_sequencer, env.master_agent.sequencer))
      `uvm_fatal("OUT_SQR_AUDIT",
        "master sequencer response audit fixture was not installed")
    audit_sequencer.prepare_response_audit();
    seq = axi_outstanding_reset_seq::type_id::create("seq");
    fork : short_pulse_watchdog
      begin
        fork
          seq.start(env.master_agent.sequencer);
          begin
            wait (seq.second_request_started);
            repeat (2) @(posedge cfg.vif.aclk);
            @(negedge cfg.vif.aclk);
            #100ps;
            if (!uvm_hdl_force("tb_top.aresetn", 1'b0))
              `uvm_fatal("OUT_SHORT_RESET", "cannot force short reset")
            #100ps;
            if (!uvm_hdl_release("tb_top.aresetn"))
              `uvm_fatal("OUT_SHORT_RESET", "cannot release short reset")
            if (!uvm_hdl_deposit("tb_top.aresetn", 1'b1))
              `uvm_fatal("OUT_SHORT_RESET", "cannot restore reset")
          end
        join
        seq_done = 1;
      end
      begin
        repeat (2_000) @(posedge cfg.vif.aclk);
        if (!seq_done)
          `uvm_error("OUT_SHORT_RESET",
            "short-pulse reset sequence exceeded 2000 cycles")
      end
    join_any
    disable short_pulse_watchdog;
    wait_for_idle();
    phase.drop_objection(this);
  endtask
endclass

class axi_outstanding_handoff_reset_test extends axi_outstanding_reset_test;
  `uvm_component_utils(axi_outstanding_handoff_reset_test)

  axi_handoff_blocking_master_sequencer handoff_sequencer;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function string get_reset_context();
    return "handoff reset";
  endfunction

  virtual function bit release_handoff_after_reset();
    return 0;
  endfunction

  virtual function void install_master_sequencer_override();
    axi_master_sequencer::type_id::set_type_override(
      axi_handoff_blocking_master_sequencer::get_type());
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit seq_done;

    phase.raise_objection(this);
    if (!$cast(handoff_sequencer, env.master_agent.sequencer))
      `uvm_fatal("OUT_HANDOFF_RESET",
        "master sequencer handoff fixture override was not installed")
    audit_sequencer = handoff_sequencer;
    audit_sequencer.prepare_response_audit();
    seq = axi_outstanding_reset_seq::type_id::create("seq");
    fork : handoff_reset_watchdog
      begin
        fork
          seq.start(env.master_agent.sequencer);
          begin
            wait (handoff_sequencer.handoff_ready);
            if (handoff_sequencer.handoff_count != 2)
              `uvm_error("OUT_HANDOFF_RESET", $sformatf(
                "handoff count=%0d expected=2",
                handoff_sequencer.handoff_count))
            if (!uvm_hdl_force("tb_top.aresetn", 1'b0))
              `uvm_fatal("OUT_HANDOFF_RESET", "cannot force reset")
            if (release_handoff_after_reset()) begin
              repeat (5) @(posedge cfg.vif.aclk);
            end else begin
              @(posedge cfg.vif.aclk);
              handoff_sequencer.release_handoff = 1;
              repeat (4) @(posedge cfg.vif.aclk);
            end
            if (!uvm_hdl_release("tb_top.aresetn"))
              `uvm_fatal("OUT_HANDOFF_RESET", "cannot release reset")
            if (!uvm_hdl_deposit("tb_top.aresetn", 1'b1))
              `uvm_fatal("OUT_HANDOFF_RESET", "cannot restore reset")
            if (release_handoff_after_reset()) begin
              wait (cfg.vif.aresetn === 1'b1);
              handoff_sequencer.release_handoff = 1;
            end
          end
        join
        seq_done = 1;
      end
      begin
        repeat (2_000) @(posedge cfg.vif.aclk);
        if (!seq_done)
          `uvm_error("OUT_HANDOFF_RESET",
            "handoff reset sequence exceeded 2000 cycles")
      end
    join_any
    disable handoff_reset_watchdog;
    wait_for_idle();
    phase.drop_objection(this);
  endtask

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (handoff_sequencer.handoff_count != 2)
      `uvm_error("OUT_HANDOFF_RESET", $sformatf(
        "final handoff count=%0d expected=2",
        handoff_sequencer.handoff_count))
  endfunction
endclass

class axi_outstanding_post_reset_handoff_test extends
  axi_outstanding_handoff_reset_test;

  `uvm_component_utils(axi_outstanding_post_reset_handoff_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function string get_reset_context();
    return "post-reset handoff";
  endfunction

  virtual function bit release_handoff_after_reset();
    return 1;
  endfunction
endclass

`endif // AXI_OUTSTANDING_LIMIT_TEST_SV
