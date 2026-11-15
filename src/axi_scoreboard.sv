`ifndef AXI_SCOREBOARD_SV
`define AXI_SCOREBOARD_SV

`uvm_analysis_imp_decl(_write_commit)
`uvm_analysis_imp_decl(_read_request)
`uvm_analysis_imp_decl(_complete)

class axi_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(axi_scoreboard)

  axi_config    cfg;
  axi_ref_model ref_mem;

  uvm_analysis_imp_write_commit #(axi_seq_item, axi_scoreboard)
    write_commit_imp;
  uvm_analysis_imp_read_request #(axi_seq_item, axi_scoreboard)
    read_request_imp;
  uvm_analysis_imp_complete #(axi_seq_item, axi_scoreboard)
    complete_imp;

  protected axi_seq_item expected_read_q[$];

  int unsigned match_count;
  int unsigned mismatch_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    write_commit_imp = new("write_commit_imp", this);
    read_request_imp = new("read_request_imp", this);
    complete_imp     = new("complete_imp", this);
    ref_mem          = axi_ref_model::type_id::create("expected_mem");
    match_count      = 0;
    mismatch_count   = 0;
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      @(negedge cfg.vif.aresetn);
      ref_mem.reset();
      expected_read_q.delete();
    end
  endtask

  virtual function void write_write_commit(axi_seq_item item);
    if (cfg.vif.aresetn !== 1'b1)
      return;
    if (item.txn_type == AXI_WRITE && !item.aborted) begin
      ref_mem.burst_write(item);
      `uvm_info("SB", $sformatf(
        "WRITE_COMMIT: %s", item.convert2string()), UVM_HIGH)
    end
  endfunction

  virtual function void write_read_request(axi_seq_item item);
    axi_seq_item expected;

    if (cfg.vif.aresetn !== 1'b1 || item.aborted)
      return;
    if (item.txn_type != AXI_READ)
      return;
    expected = axi_seq_item::type_id::create("expected_read");
    expected.copy(item);
    ref_mem.burst_read(expected, expected.rdata);
    expected_read_q.push_back(expected);
  endfunction

  virtual function void write_complete(axi_seq_item item);
    int match = -1;
    axi_seq_item expected;
    bit mismatch;

    if (cfg.vif.aresetn !== 1'b1 && !item.aborted)
      return;
    if (item.txn_type != AXI_READ) begin
      `uvm_info("SB", $sformatf(
        "WRITE_COMPLETE: %s", item.convert2string()), UVM_HIGH)
      return;
    end

    foreach (expected_read_q[i]) begin
      if (match < 0 && expected_read_q[i].id == item.id)
        match = i;
    end

    if (item.aborted) begin
      if (match >= 0)
        expected_read_q.delete(match);
      return;
    end
    if (match < 0) begin
      `uvm_error("SB", $sformatf(
        "completed read has no expected AR snapshot: %s",
        item.convert2string()))
      mismatch_count++;
      return;
    end

    expected = expected_read_q[match];
    expected_read_q.delete(match);
    if (item.addr != expected.addr ||
        item.burst_len != expected.burst_len ||
        item.burst_size != expected.burst_size ||
        item.burst_type != expected.burst_type) begin
      `uvm_error("SB", $sformatf(
        "READ HEADER MISMATCH: got %s expected %s",
        item.convert2string(), expected.convert2string()))
      mismatch = 1;
    end
    if (item.resp.size() != (item.burst_len + 1)) begin
      `uvm_error("SB", $sformatf(
        "INCOMPLETE READ RESPONSE: %s resp.size=%0d expected=%0d",
        item.convert2string(), item.resp.size(), item.burst_len + 1))
      mismatch = 1;
    end
    if (item.rdata.size() != item.get_total_bytes()) begin
      `uvm_error("SB", $sformatf(
        "INCOMPLETE READ DATA: %s rdata.size=%0d expected=%0d",
        item.convert2string(), item.rdata.size(), item.get_total_bytes()))
      mismatch = 1;
    end
    if (item.rdata.size() != expected.rdata.size()) begin
      `uvm_error("SB", $sformatf(
        "SIZE MISMATCH: %s rdata.size=%0d expected.size=%0d",
        item.convert2string(), item.rdata.size(), expected.rdata.size()))
      mismatch = 1;
    end
    for (int i = 0;
         i < item.rdata.size() && i < expected.rdata.size(); i++) begin
      if (item.rdata[i] !== expected.rdata[i]) begin
        `uvm_error("SB", $sformatf(
          "DATA MISMATCH: %s byte[%0d] got=0x%02h exp=0x%02h",
          item.convert2string(), i, item.rdata[i], expected.rdata[i]))
        mismatch = 1;
      end
    end

    if (mismatch)
      mismatch_count++;
    else begin
      match_count++;
      `uvm_info("SB", $sformatf(
        "MATCH: %s", item.convert2string()), UVM_HIGH)
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf(
      "Scoreboard Report: MATCH=%0d  MISMATCH=%0d",
      match_count, mismatch_count), UVM_NONE)
    if (mismatch_count > 0)
      `uvm_error("SB", $sformatf(
        "%0d data mismatch(es) detected -- test FAILED", mismatch_count))
  endfunction

endclass

`endif // AXI_SCOREBOARD_SV
