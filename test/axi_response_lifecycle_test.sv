`ifndef AXI_RESPONSE_LIFECYCLE_TEST_SV
`define AXI_RESPONSE_LIFECYCLE_TEST_SV

// Test-only master override used to prove that the slave accepts a complete
// W burst before its corresponding AW.  W remains on the production path.
class axi_w_before_aw_master_driver extends axi_master_driver;

  `uvm_component_utils(axi_w_before_aw_master_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task drive_aw_channel();
    forever begin
      aw_mbx.get(active_aw);
      repeat (10) begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      vif.master_awid     <= active_aw.id;
      vif.master_awaddr   <= active_aw.addr;
      vif.master_awlen    <= active_aw.burst_len;
      vif.master_awsize   <= active_aw.burst_size;
      vif.master_awburst  <= active_aw.burst_type;
      vif.master_awlock   <= active_aw.lock;
      vif.master_awcache  <= active_aw.cache;
      vif.master_awprot   <= active_aw.prot;
      vif.master_awqos    <= active_aw.qos;
      vif.master_awregion <= active_aw.region;
      vif.master_awvalid  <= 1'b1;
      do begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      while (!vif.awready);
      vif.master_awvalid <= 1'b0;
      active_aw = null;
    end
  endtask

endclass

// Test-only master override used to align the AW and complete single-beat W
// handshakes.  The only production difference is removal of AW's initial
// pre-drive clock wait.
class axi_aw_w_same_cycle_master_driver extends axi_master_driver;

  `uvm_component_utils(axi_aw_w_same_cycle_master_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task drive_aw_channel();
    forever begin
      aw_mbx.get(active_aw);
      if (vif.aresetn !== 1'b1)
        return;
      vif.master_awid     <= active_aw.id;
      vif.master_awaddr   <= active_aw.addr;
      vif.master_awlen    <= active_aw.burst_len;
      vif.master_awsize   <= active_aw.burst_size;
      vif.master_awburst  <= active_aw.burst_type;
      vif.master_awlock   <= active_aw.lock;
      vif.master_awcache  <= active_aw.cache;
      vif.master_awprot   <= active_aw.prot;
      vif.master_awqos    <= active_aw.qos;
      vif.master_awregion <= active_aw.region;
      vif.master_awvalid  <= 1'b1;
      do begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      while (!vif.awready);
      vif.master_awvalid <= 1'b0;
      active_aw = null;
    end
  endtask

endclass

// Test-only slave override used to force two read responses to interleave.
// Production slave behavior is intentionally left unchanged.
class axi_interleaved_r_slave_driver extends axi_slave_driver;

  `uvm_component_utils(axi_interleaved_r_slave_driver)

  protected axi_seq_item active_r_second;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function bit is_idle();
    return super.is_idle() && active_r_second == null;
  endfunction

  protected virtual task clear_state();
    super.clear_state();
    active_r_second = null;
  endtask

  function bit has_two_active_responses();
    return active_r != null && active_r_second != null;
  endfunction

  protected task drive_interleaved_beat(
    input axi_seq_item item,
    input int unsigned beat
  );
    int unsigned bytes_per_beat;
    int unsigned bus_bytes;
    bit [511:0] rdata_packed;

    bytes_per_beat = item.get_bytes_per_beat();
    bus_bytes      = cfg.data_width / 8;
    rdata_packed   = '0;

    if (bus_bytes == 0 || bus_bytes > 64)
      `uvm_fatal("AXI_INTERLEAVED_R", $sformatf(
        "unsupported bus_bytes=%0d", bus_bytes))
    for (int i = 0; i < bytes_per_beat; i++) begin
      int unsigned data_index = item.beat_data_index(beat, i);

      if (item.beat_byte_valid(beat, i, bus_bytes) &&
          data_index < item.rdata.size()) begin
        int unsigned lane = item.beat_byte_lane(beat, i, bus_bytes);
        rdata_packed[lane*8 +: 8] = item.rdata[data_index];
      end
    end

    vif.slave_rid    <= item.id;
    vif.slave_rdata  <= rdata_packed;
    vif.slave_rresp  <= AXI_OKAY;
    vif.slave_rlast  <= (beat == item.burst_len);
    vif.slave_rvalid <= 1'b1;
    do begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
    end
    while (!vif.rready);
  endtask

  virtual task drive_r_channel();
    forever begin
      axi_seq_item item_a;
      axi_seq_item item_b;

      rd_resp_mbx.get(active_r);
      rd_resp_mbx.get(active_r_second);
      if (vif.aresetn !== 1'b1)
        return;

      // Define A/B by address so fork scheduling cannot change the required
      // RID order on the interface.
      if (active_r.addr < active_r_second.addr) begin
        item_a = active_r;
        item_b = active_r_second;
      end else begin
        item_a = active_r_second;
        item_b = active_r;
      end

      if (item_a.addr == item_b.addr || item_a.id == item_b.id)
        `uvm_error("AXI_INTERLEAVED_R",
          "interleaved requests must have different addresses and RIDs")
      if (item_a.burst_len != item_b.burst_len ||
          item_a.burst_size != item_b.burst_size)
        `uvm_error("AXI_INTERLEAVED_R",
          "interleaved requests must have equal LEN and SIZE")
      if (item_a.burst_len < 1)
        `uvm_error("AXI_INTERLEAVED_R",
          "interleaved test requires at least two beats per response")

      apply_resp_delay();
      if (vif.aresetn !== 1'b1)
        return;
      for (int beat = 0; beat <= item_a.burst_len; beat++) begin
        drive_interleaved_beat(item_a, beat);
        if (vif.aresetn !== 1'b1)
          return;
        drive_interleaved_beat(item_b, beat);
        if (vif.aresetn !== 1'b1)
          return;
      end
      vif.slave_rvalid <= 1'b0;
      vif.slave_rlast  <= 1'b0;
      active_r = null;
      active_r_second = null;
    end
  endtask

endclass

// Test-only response drivers used to separate write-data commit from the B
// response and to exercise malformed/unmatched response recovery.
class axi_r_before_b_slave_driver extends axi_slave_driver;

  `uvm_component_utils(axi_r_before_b_slave_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task drive_r_channel();
    forever begin
      int unsigned bus_bytes = cfg.data_width / 8;

      rd_resp_mbx.get(active_r);
      if (vif.aresetn !== 1'b1)
        return;
      for (int beat = 0; beat <= active_r.burst_len; beat++) begin
        bit [511:0] rdata_packed = '0;

        for (int i = 0; i < active_r.get_bytes_per_beat(); i++) begin
          int unsigned data_index = active_r.beat_data_index(beat, i);
          if (active_r.beat_byte_valid(beat, i, bus_bytes) &&
              data_index < active_r.rdata.size()) begin
            int unsigned lane = active_r.beat_byte_lane(beat, i, bus_bytes);
            rdata_packed[lane*8 +: 8] = active_r.rdata[data_index];
          end
        end
        vif.slave_rid    <= active_r.id;
        vif.slave_rdata  <= rdata_packed;
        vif.slave_rresp  <= AXI_OKAY;
        vif.slave_rlast  <= (beat == active_r.burst_len);
        vif.slave_rvalid <= 1'b1;
        do begin
          @(posedge vif.aclk);
          if (vif.aresetn !== 1'b1)
            return;
        end
        while (!vif.rready);
      end
      vif.slave_rvalid <= 1'b0;
      vif.slave_rlast  <= 1'b0;
      active_r = null;
    end
  endtask

  virtual task drive_b_channel();
    forever begin
      wr_resp_mbx.get(active_b);
      repeat (40) begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      vif.slave_bid    <= active_b.id;
      vif.slave_bresp  <= AXI_OKAY;
      vif.slave_bvalid <= 1'b1;
      do begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      while (!vif.bready);
      vif.slave_bvalid <= 1'b0;
      active_b = null;
    end
  endtask

endclass

class axi_same_cycle_resp_slave_driver extends axi_slave_driver;

  `uvm_component_utils(axi_same_cycle_resp_slave_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  protected virtual task run_active_workers();
    fork
      handle_request_channels();
      drive_b_r_same_cycle();
    join
  endtask

  protected task drive_b_r_same_cycle();
    forever begin
      bit [511:0] rdata_packed = '0;
      int unsigned bus_bytes = cfg.data_width / 8;

      wr_resp_mbx.get(active_b);
      rd_resp_mbx.get(active_r);
      if (vif.aresetn !== 1'b1)
        return;
      if (active_r.burst_len != 0)
        `uvm_fatal("AXI_SAME_CYCLE", "same-cycle test expects one R beat")
      for (int i = 0; i < active_r.get_bytes_per_beat(); i++) begin
        int unsigned data_index = active_r.beat_data_index(0, i);
        if (active_r.beat_byte_valid(0, i, bus_bytes) &&
            data_index < active_r.rdata.size()) begin
          int unsigned lane = active_r.beat_byte_lane(0, i, bus_bytes);
          rdata_packed[lane*8 +: 8] = active_r.rdata[data_index];
        end
      end

      vif.slave_bid    <= active_b.id;
      vif.slave_bresp  <= AXI_OKAY;
      vif.slave_bvalid <= 1'b1;
      vif.slave_rid    <= active_r.id;
      vif.slave_rdata  <= rdata_packed;
      vif.slave_rresp  <= AXI_OKAY;
      vif.slave_rlast  <= 1'b1;
      vif.slave_rvalid <= 1'b1;
      do begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      while (!(vif.bready && vif.rready));
      vif.slave_bvalid <= 1'b0;
      vif.slave_rvalid <= 1'b0;
      vif.slave_rlast  <= 1'b0;
      active_b = null;
      active_r = null;
    end
  endtask

endclass

class axi_malformed_last_slave_driver extends axi_slave_driver;

  `uvm_component_utils(axi_malformed_last_slave_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task drive_r_channel();
    forever begin
      int unsigned bus_bytes = cfg.data_width / 8;
      int unsigned final_beat;

      rd_resp_mbx.get(active_r);
      if (vif.aresetn !== 1'b1)
        return;
      final_beat = $test$plusargs("R_EARLY_LAST") ? 0 :
                   active_r.burst_len + 1;
      for (int beat = 0; beat <= final_beat; beat++) begin
        bit [511:0] rdata_packed = '0;

        for (int i = 0; i < active_r.get_bytes_per_beat(); i++) begin
          int unsigned data_index = active_r.beat_data_index(beat, i);
          if (active_r.beat_byte_valid(beat, i, bus_bytes) &&
              data_index < active_r.rdata.size()) begin
            int unsigned lane = active_r.beat_byte_lane(beat, i, bus_bytes);
            rdata_packed[lane*8 +: 8] = active_r.rdata[data_index];
          end
        end
        vif.slave_rid    <= active_r.id;
        vif.slave_rdata  <= rdata_packed;
        vif.slave_rresp  <= AXI_OKAY;
        vif.slave_rlast  <= (beat == final_beat);
        vif.slave_rvalid <= 1'b1;
        do begin
          @(posedge vif.aclk);
          if (vif.aresetn !== 1'b1)
            return;
        end
        while (!vif.rready);
      end
      vif.slave_rvalid <= 1'b0;
      vif.slave_rlast  <= 1'b0;
      active_r = null;
    end
  endtask

endclass

class axi_unmatched_resp_slave_driver extends axi_slave_driver;

  `uvm_component_utils(axi_unmatched_resp_slave_driver)

  protected bit          injection_consumed;
  protected bit          injection_active;
  protected int unsigned injection_attempt_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function bit is_idle();
    return super.is_idle() && !injection_active;
  endfunction

  function bit has_active_unmatched_injection();
    return injection_active;
  endfunction

  function int unsigned get_unmatched_injection_attempt_count();
    return injection_attempt_count;
  endfunction

  protected virtual task clear_state();
    super.clear_state();
    injection_active = 0;
  endtask

  protected virtual task run_active_workers();
    if (!injection_consumed) begin
      injection_consumed = 1;
      injection_active = 1;
      injection_attempt_count++;
      `uvm_info("AXI_UNMATCHED_RESP", $sformatf(
        "starting unmatched response injection attempt %0d",
        injection_attempt_count), UVM_LOW)
      repeat (5) begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      vif.slave_bid    <= 16'hE;
      vif.slave_bresp  <= AXI_OKAY;
      vif.slave_bvalid <= 1'b1;
      vif.slave_rid    <= 16'hF;
      vif.slave_rdata  <= '0;
      vif.slave_rresp  <= AXI_OKAY;
      vif.slave_rlast  <= 1'b1;
      vif.slave_rvalid <= 1'b1;
      do begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      while (!(vif.bready && vif.rready));
      vif.slave_bvalid <= 1'b0;
      vif.slave_rvalid <= 1'b0;
      vif.slave_rlast  <= 1'b0;
      injection_active = 0;
    end
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
    end
  endtask

endclass

class axi_collision_reader_seq extends axi_base_seq;

  `uvm_object_utils(axi_collision_reader_seq)

  bit [63:0] addr;
  bit [15:0] id;
  bit [7:0]  expected_data[];
  int        request_sequence_id;
  int        request_transaction_id;
  bit        completed;

  function new(string name = "axi_collision_reader_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item item;
    axi_seq_item rsp;

    item = axi_seq_item::type_id::create("collision_read_item");
    item.cfg = cfg;
    start_item(item);
    if (!item.randomize() with {
          txn_type        == AXI_READ;
          item.addr       == local::addr;
          item.id         == local::id;
          item.burst_len  == 8'h01;
          item.burst_size == 3'h2;
          item.burst_type == AXI_INCR;
          item.lock       == 1'b0;
          item.inject_err == 1'b0;
        }) begin
      `uvm_fatal("AXI_COLLISION_READER", "read item randomize failed")
    end
    item.set_transaction_id(7);
    finish_item(item);
    request_sequence_id    = item.get_sequence_id();
    request_transaction_id = item.get_transaction_id();

    get_response(rsp, 7);
    if (rsp == null)
      `uvm_fatal("AXI_COLLISION_READER", "received a null response")
    if (rsp.aborted)
      `uvm_error("AXI_COLLISION_READER", "read response was aborted")
    if (rsp.addr != addr || rsp.id != id)
      `uvm_error("AXI_COLLISION_READER", $sformatf(
        "response identity mismatch: addr=0x%0h id=0x%0h expected addr=0x%0h id=0x%0h",
        rsp.addr, rsp.id, addr, id))
    if (rsp.resp.size() != 2)
      `uvm_error("AXI_COLLISION_READER", $sformatf(
        "response beat count=%0d expected=2", rsp.resp.size()))
    if (rsp.rdata.size() != expected_data.size()) begin
      `uvm_error("AXI_COLLISION_READER", $sformatf(
        "data size=%0d expected=%0d", rsp.rdata.size(), expected_data.size()))
    end else begin
      foreach (expected_data[i]) begin
        if (rsp.rdata[i] !== expected_data[i])
          `uvm_error("AXI_COLLISION_READER", $sformatf(
            "addr=0x%0h byte[%0d] got=0x%02h expected=0x%02h",
            addr, i, rsp.rdata[i], expected_data[i]))
      end
    end
    `uvm_info("AXI_COLLISION_READER", $sformatf(
      "verified addr=0x%0h RID=0x%0h returned all %0d expected bytes",
      addr, id, expected_data.size()), UVM_LOW)
    completed = 1;
  endtask

endclass

class axi_response_lifecycle_seq extends axi_base_seq;

  `uvm_object_utils(axi_response_lifecycle_seq)

  bit          reset_while_throttled;
  bit          reset_in_flight;
  bit          reset_edge_race;
  bit          reset_derived_interleaved;
  bit          reset_derived_same_cycle;
  bit          reset_derived_unmatched;
  bit          interleaved_r_collision;
  bit          w_before_aw;
  bit          aw_w_same_cycle;
  bit          ar_snapshot;
  bit          r_before_b;
  bit          b_r_same_cycle;
  bit          malformed_last;
  bit          unmatched_resp;
  axi_scoreboard scoreboard;
  bit          second_request_started;
  int unsigned second_completion_count;
  int unsigned b_count;
  int unsigned observed_cycle;
  int unsigned reset_release_cycle;
  int unsigned first_aw_cycle;
  int unsigned first_w_cycle;
  int unsigned second_aw_cycle;
  int unsigned second_w_cycle;
  int unsigned w_before_aw_aw_cycle;
  int unsigned w_before_aw_wlast_cycle;
  bit          w_before_aw_order_reported;
  int unsigned same_cycle_aw_cycle;
  int unsigned same_cycle_wlast_cycle;
  int unsigned same_cycle_b_count;
  bit          snapshot_new_write_started;
  int unsigned snapshot_ar_cycle;
  int unsigned snapshot_new_aw_cycle;
  int unsigned snapshot_new_wlast_cycle;
  int unsigned snapshot_new_commit_cycle;
  int unsigned snapshot_first_r_cycle;
  int unsigned snapshot_b_count;
  int unsigned snapshot_r_count;
  bit          reset_requests_accepted;
  bit          reset_released;
  bit          derived_requests_issued;
  int unsigned aborted_response_count;
  int unsigned response_count_by_txn[int];
  axi_seq_item reset_edge_stale_commit;

  function new(string name = "axi_response_lifecycle_seq");
    super.new(name);
  endfunction

  virtual function void put_response(uvm_sequence_item response_item);
    response_count_by_txn[response_item.get_transaction_id()]++;
    super.put_response(response_item);
  endfunction

  protected task check_data(
    input string label,
    input axi_seq_item rsp,
    input bit [63:0] expected_addr,
    input bit [7:0] expected_data[],
    input int unsigned expected_beats = 1
  );
    if (rsp == null) begin
      `uvm_error("AXI_LIFECYCLE", {label, " returned a null response"})
      return;
    end
    if (rsp.aborted)
      `uvm_error("AXI_LIFECYCLE", {label, " response was aborted"})
    if (rsp.addr != expected_addr)
      `uvm_error("AXI_LIFECYCLE", $sformatf(
        "%s response addr=0x%0h expected=0x%0h",
        label, rsp.addr, expected_addr))
    if (rsp.resp.size() != expected_beats)
      `uvm_error("AXI_LIFECYCLE", $sformatf(
        "%s response beat count=%0d expected=%0d",
        label, rsp.resp.size(), expected_beats))
    if (rsp.rdata.size() != expected_data.size()) begin
      `uvm_error("AXI_LIFECYCLE", $sformatf(
        "%s data size=%0d expected=%0d",
        label, rsp.rdata.size(), expected_data.size()))
    end else begin
      foreach (expected_data[i]) begin
        if (rsp.rdata[i] !== expected_data[i])
          `uvm_error("AXI_LIFECYCLE", $sformatf(
            "%s byte[%0d] got=0x%02h expected=0x%02h",
            label, i, rsp.rdata[i], expected_data[i]))
      end
    end
  endtask

  protected task check_write_response(
    input string label,
    input axi_seq_item req,
    input axi_seq_item rsp,
    input bit [15:0] expected_id
  );
    if (rsp == null) begin
      `uvm_error("AXI_LIFECYCLE", {label, " returned a null response"})
      return;
    end
    if (rsp.aborted)
      `uvm_error("AXI_LIFECYCLE", {label, " response was aborted"})
    if (rsp.id != expected_id || rsp.addr != req.addr)
      `uvm_error("AXI_LIFECYCLE", $sformatf(
        "%s response identity id=0x%0h addr=0x%0h expected id=0x%0h addr=0x%0h",
        label, rsp.id, rsp.addr, expected_id, req.addr))
    if (rsp.get_sequence_id() != req.get_sequence_id() ||
        rsp.get_transaction_id() != req.get_transaction_id())
      `uvm_error("AXI_LIFECYCLE", $sformatf(
        "%s routing identity seq/txn=%0d/%0d expected=%0d/%0d",
        label, rsp.get_sequence_id(), rsp.get_transaction_id(),
        req.get_sequence_id(), req.get_transaction_id()))
    if (rsp.resp.size() != 1 || rsp.resp[0] != AXI_OKAY)
      `uvm_error("AXI_LIFECYCLE", $sformatf(
        "%s did not return exactly one OKAY response", label))
  endtask

  protected task run_same_id_outstanding();
    axi_seq_item wr_req[2];
    axi_seq_item wr_rsp[2];
    axi_seq_item rd_req[2];
    axi_seq_item rd_rsp[2];
    bit [7:0] d0[] = '{8'hA0, 8'hA1, 8'hA2, 8'hA3};
    bit [7:0] d1[] = '{8'hB0, 8'hB1, 8'hB2, 8'hB3};
    int unsigned write_issue_count;
    int unsigned read_issue_count;

    issue_write(64'h1900, d0, 0, 2, AXI_INCR, 16'h5, wr_req[0]);
    write_issue_count++;
    `uvm_info("AXI_LIFECYCLE", $sformatf(
      "same-ID write issue %0d/2 completed before first explicit wait",
      write_issue_count), UVM_LOW)
    issue_write(64'h1910, d1, 0, 2, AXI_INCR, 16'h5, wr_req[1]);
    write_issue_count++;
    `uvm_info("AXI_LIFECYCLE", $sformatf(
      "same-ID write issue %0d/2 completed before first explicit wait",
      write_issue_count), UVM_LOW)
    if (write_issue_count != 2)
      `uvm_error("AXI_LIFECYCLE",
        "first write wait began before both writes were issued")
    if (wr_req[0].get_transaction_id() == wr_req[1].get_transaction_id())
      `uvm_error("AXI_LIFECYCLE", "issued writes reused a transaction ID")
    `uvm_info("AXI_LIFECYCLE", $sformatf(
      "both same-ID writes issued before first wait: transaction IDs %0d and %0d",
      wr_req[0].get_transaction_id(), wr_req[1].get_transaction_id()), UVM_LOW)

    wait_response(wr_req[0], wr_rsp[0]);
    wait_response(wr_req[1], wr_rsp[1]);
    foreach (wr_rsp[i]) begin
      if (wr_rsp[i] == null) begin
        `uvm_error("AXI_LIFECYCLE", $sformatf(
          "same-ID write response[%0d] was null", i))
      end else begin
        if (wr_rsp[i].aborted)
          `uvm_error("AXI_LIFECYCLE", $sformatf(
            "same-ID write response[%0d] was aborted", i))
        if (wr_rsp[i].resp.size() != 1)
          `uvm_error("AXI_LIFECYCLE", $sformatf(
            "same-ID write response[%0d] beat count=%0d expected=1",
            i, wr_rsp[i].resp.size()))
      end
    end
    if (wr_rsp[0] != null && wr_rsp[0].addr != 64'h1900)
      `uvm_error("AXI_LIFECYCLE",
        "first same-ID write response lost address identity")
    if (wr_rsp[1] != null && wr_rsp[1].addr != 64'h1910)
      `uvm_error("AXI_LIFECYCLE",
        "second same-ID write response lost address identity")

    issue_read(64'h1900, 0, 2, AXI_INCR, 16'h5, rd_req[0]);
    read_issue_count++;
    `uvm_info("AXI_LIFECYCLE", $sformatf(
      "same-ID read issue %0d/2 completed before first explicit wait",
      read_issue_count), UVM_LOW)
    issue_read(64'h1910, 0, 2, AXI_INCR, 16'h5, rd_req[1]);
    read_issue_count++;
    `uvm_info("AXI_LIFECYCLE", $sformatf(
      "same-ID read issue %0d/2 completed before first explicit wait",
      read_issue_count), UVM_LOW)
    if (read_issue_count != 2)
      `uvm_error("AXI_LIFECYCLE",
        "first read wait began before both reads were issued")
    if (rd_req[0].get_transaction_id() == rd_req[1].get_transaction_id())
      `uvm_error("AXI_LIFECYCLE", "issued reads reused a transaction ID")
    `uvm_info("AXI_LIFECYCLE", $sformatf(
      "both same-ID reads issued before first wait: transaction IDs %0d and %0d",
      rd_req[0].get_transaction_id(), rd_req[1].get_transaction_id()), UVM_LOW)

    wait_response(rd_req[0], rd_rsp[0]);
    wait_response(rd_req[1], rd_rsp[1]);
    check_data("first same-ID read", rd_rsp[0], 64'h1900, d0);
    check_data("second same-ID read", rd_rsp[1], 64'h1910, d1);
  endtask

  protected task run_interleaved_collision();
    bit [7:0] d0[] = '{
      8'hA0, 8'hA1, 8'hA2, 8'hA3,
      8'hA4, 8'hA5, 8'hA6, 8'hA7
    };
    bit [7:0] d1[] = '{
      8'hB0, 8'hB1, 8'hB2, 8'hB3,
      8'hB4, 8'hB5, 8'hB6, 8'hB7
    };
    axi_collision_reader_seq seq_a;
    axi_collision_reader_seq seq_b;
    bit [15:0] observed_rid[4];
    bit [15:0] expected_rid[4] = '{16'h6, 16'h7, 16'h6, 16'h7};
    int unsigned rid_count;

    // Single-beat writes preload distinct data before the collision reads.
    do_write(64'h1900, d0, 0, 3, AXI_INCR, 16'h5);
    do_write(64'h1910, d1, 0, 3, AXI_INCR, 16'h5);

    seq_a = axi_collision_reader_seq::type_id::create("seq_a");
    seq_b = axi_collision_reader_seq::type_id::create("seq_b");
    seq_a.addr          = 64'h1900;
    seq_a.id            = 16'h6;
    seq_a.expected_data = d0;
    seq_b.addr          = 64'h1910;
    seq_b.id            = 16'h7;
    seq_b.expected_data = d1;

    fork
      begin
        while (rid_count < 4) begin
          do @(posedge cfg.vif.aclk);
          while (!(cfg.vif.rvalid && cfg.vif.rready));
          observed_rid[rid_count] = cfg.vif.rid;
          `uvm_info("AXI_INTERLEAVED_R", $sformatf(
            "R handshake[%0d] RID=0x%0h", rid_count, cfg.vif.rid), UVM_LOW)
          rid_count++;
        end
      end
      begin
        seq_a.start(m_sequencer);
      end
      begin
        seq_b.start(m_sequencer);
      end
    join

    if (!seq_a.completed || !seq_b.completed)
      `uvm_error("AXI_INTERLEAVED_R",
        "one or both collision reader sequences did not complete")
    if (seq_a.request_sequence_id == seq_b.request_sequence_id)
      `uvm_error("AXI_INTERLEAVED_R",
        "collision readers reused a UVM sequence ID")
    if (seq_a.request_transaction_id != 7 ||
        seq_b.request_transaction_id != 7)
      `uvm_error("AXI_INTERLEAVED_R",
        "collision readers did not preserve forced transaction ID 7")
    foreach (observed_rid[i]) begin
      if (observed_rid[i] != expected_rid[i])
        `uvm_error("AXI_INTERLEAVED_R", $sformatf(
          "R handshake[%0d] RID=0x%0h expected=0x%0h",
          i, observed_rid[i], expected_rid[i]))
    end
    `uvm_info("AXI_INTERLEAVED_R", $sformatf(
      "collision readers routed by distinct sequence IDs %0d/%0d with shared transaction ID 7",
      seq_a.request_sequence_id, seq_b.request_sequence_id), UVM_LOW)
  endtask

  protected task run_w_before_aw_unaligned();
    bit [7:0] nominal_data[] = '{
      8'h11, 8'h22, 8'h33, 8'h44,
      8'h55, 8'h66, 8'h77, 8'h88,
      8'h99, 8'hAA, 8'hBB, 8'hCC,
      8'hDD, 8'hEE, 8'hF1, 8'hF2
    };
    bit [7:0] expected_data[] = '{
      8'h11, 8'h00, 8'h00, 8'h00,
      8'h55, 8'h66, 8'h77, 8'h88,
      8'h99, 8'hAA, 8'hBB, 8'hCC,
      8'hDD, 8'hEE, 8'hF1, 8'hF2
    };
    axi_seq_item wr_req;
    axi_seq_item wr_rsp;
    axi_seq_item rd_rsp;

    issue_write(64'h1907, nominal_data, 8'h03, 3'h2,
                AXI_INCR, 16'h9, wr_req);
    wait_response(wr_req, wr_rsp);
    #0;

    if (wr_rsp == null || wr_rsp.aborted || wr_rsp.resp.size() != 1 ||
        wr_rsp.resp[0] != AXI_OKAY)
      `uvm_error("AXI_W_BEFORE_AW",
        "W-before-AW write did not complete with one OKAY B response")
    if (b_count != 1)
      `uvm_error("AXI_W_BEFORE_AW", $sformatf(
        "B handshake count=%0d expected=1", b_count))

    do_read(64'h1907, 8'h03, 3'h2, AXI_INCR, 16'hA, rd_rsp);
    check_data("W-before-AW unaligned read", rd_rsp, 64'h1907,
               expected_data, 4);
    if (rd_rsp != null)
      `uvm_info("AXI_W_BEFORE_AW", $sformatf(
        "verified 16 nominal read bytes with holes [1:3]=0: %p",
        rd_rsp.rdata), UVM_LOW)
  endtask

  protected task run_aw_w_same_cycle();
    bit [7:0] data[] = '{8'hD1, 8'hE2, 8'hF3, 8'hA4};
    axi_seq_item wr_req;
    axi_seq_item wr_rsp;
    axi_seq_item rd_rsp;

    fork : observe_same_cycle_b
      begin
        forever begin
          do @(posedge cfg.vif.aclk);
          while (!(cfg.vif.bvalid && cfg.vif.bready));
          same_cycle_b_count++;
          if (cfg.vif.bid != 4'hE || cfg.vif.bresp != AXI_OKAY)
            `uvm_error("AW_W_SAME_CYCLE", $sformatf(
              "B handshake id/resp=0x%0h/%0d expected=0xE/OKAY",
              cfg.vif.bid, cfg.vif.bresp))
        end
      end
    join_none

    issue_write(64'h1D00, data, 0, 2, AXI_INCR, 16'hE, wr_req);
    wait_response(wr_req, wr_rsp);
    check_write_response("same-cycle write", wr_req, wr_rsp, 16'hE);
    do_read(64'h1D00, 0, 2, AXI_INCR, 16'hD, rd_rsp);
    check_data("same-cycle readback", rd_rsp, 64'h1D00, data);
    #0;
    disable observe_same_cycle_b;

    if (same_cycle_b_count != 1)
      `uvm_error("AW_W_SAME_CYCLE", $sformatf(
        "B handshake count=%0d expected=1", same_cycle_b_count))
    `uvm_info("AW_W_SAME_CYCLE", $sformatf(
      "one routed OKAY B and exact readback data=%p", rd_rsp.rdata), UVM_LOW)
  endtask

  protected task run_ar_snapshot();
    bit [7:0] old_data[] = '{8'hA1, 8'hB2, 8'hC3, 8'hD4};
    bit [7:0] new_data[] = '{8'h1E, 8'h2D, 8'h3C, 8'h4B};
    axi_seq_item init_wr_req;
    axi_seq_item init_wr_rsp;
    axi_seq_item snapshot_rd_req;
    axi_seq_item snapshot_rd_rsp;
    axi_seq_item new_wr_req;
    axi_seq_item new_wr_rsp;
    axi_seq_item final_rd_rsp;

    fork : observe_snapshot_responses
      begin
        forever begin
          do @(posedge cfg.vif.aclk);
          while (!(cfg.vif.bvalid && cfg.vif.bready));
          if ((snapshot_b_count == 0 &&
               (cfg.vif.bid != 4'h1 || cfg.vif.bresp != AXI_OKAY)) ||
              (snapshot_b_count == 1 &&
               (cfg.vif.bid != 4'h3 || cfg.vif.bresp != AXI_OKAY)) ||
              snapshot_b_count > 1)
            `uvm_error("AR_SNAPSHOT", $sformatf(
              "unexpected B[%0d] id/resp=0x%0h/%0d",
              snapshot_b_count, cfg.vif.bid, cfg.vif.bresp))
          snapshot_b_count++;
        end
      end
      begin
        forever begin
          do @(posedge cfg.vif.aclk);
          while (!(cfg.vif.rvalid && cfg.vif.rready));
          if ((snapshot_r_count == 0 && cfg.vif.rid != 4'h2) ||
              (snapshot_r_count == 1 && cfg.vif.rid != 4'h4) ||
              cfg.vif.rresp != AXI_OKAY || !cfg.vif.rlast ||
              snapshot_r_count > 1)
            `uvm_error("AR_SNAPSHOT", $sformatf(
              "unexpected R[%0d] id/resp/last=0x%0h/%0d/%0b",
              snapshot_r_count, cfg.vif.rid,
              cfg.vif.rresp, cfg.vif.rlast))
          snapshot_r_count++;
        end
      end
    join_none

    issue_write(64'h1D40, old_data, 0, 2,
                AXI_INCR, 16'h1, init_wr_req);
    wait_response(init_wr_req, init_wr_rsp);
    check_write_response("snapshot initialization write",
                         init_wr_req, init_wr_rsp, 16'h1);

    issue_read(64'h1D40, 0, 2, AXI_INCR, 16'h2, snapshot_rd_req);
    wait (snapshot_ar_cycle != 0);
    snapshot_new_write_started = 1;
    issue_write(64'h1D40, new_data, 0, 2,
                AXI_INCR, 16'h3, new_wr_req);

    wait_response(snapshot_rd_req, snapshot_rd_rsp);
    check_data("queued OLD snapshot", snapshot_rd_rsp,
               64'h1D40, old_data);
    wait_response(new_wr_req, new_wr_rsp);
    check_write_response("post-AR NEW write",
                         new_wr_req, new_wr_rsp, 16'h3);
    wait (snapshot_new_commit_cycle != 0);

    do_read(64'h1D40, 0, 2, AXI_INCR, 16'h4, final_rd_rsp);
    check_data("post-commit NEW read", final_rd_rsp,
               64'h1D40, new_data);
    #0;
    disable observe_snapshot_responses;

    if (snapshot_b_count != 2 || snapshot_r_count != 2)
      `uvm_error("AR_SNAPSHOT", $sformatf(
        "response handshake counts B=%0d R=%0d expected=2/2",
        snapshot_b_count, snapshot_r_count))
    `uvm_info("AR_SNAPSHOT", $sformatf(
      "queued read returned OLD=%p and later read returned NEW=%p with routed B/R responses",
      snapshot_rd_rsp.rdata, final_rd_rsp.rdata), UVM_LOW)
  endtask

  protected task run_reset_in_flight();
    bit [7:0] pre_reset_data[] = '{8'h11, 8'h22, 8'h33, 8'h44};
    bit [7:0] reset_data[]     = '{8'h00, 8'h00, 8'h00, 8'h00};
    bit [7:0] clean_data[]     = '{8'hA5, 8'h5A, 8'hC3, 8'h3C};
    axi_seq_item wr_req;
    axi_seq_item rd_req;
    axi_seq_item wr_rsp;
    axi_seq_item rd_rsp;
    axi_seq_item reset_rsp;
    axi_seq_item clean_rsp;
    bit aw_accepted;
    bit w_accepted;
    bit ar_accepted;
    bit wr_response_received;
    bit rd_response_received;

    fork : observe_reset_acceptance
      begin
        do @(posedge cfg.vif.aclk);
        while (!(cfg.vif.awvalid && cfg.vif.awready &&
                 cfg.vif.awaddr == 64'h1A00));
        aw_accepted = 1;
      end
      begin
        do @(posedge cfg.vif.aclk);
        while (!(cfg.vif.wvalid && cfg.vif.wready && cfg.vif.wlast));
        w_accepted = 1;
      end
      begin
        do @(posedge cfg.vif.aclk);
        while (!(cfg.vif.arvalid && cfg.vif.arready &&
                 cfg.vif.araddr == 64'h1A20));
        ar_accepted = 1;
      end
    join_none

    issue_write(64'h1A00, pre_reset_data, 0, 2,
                AXI_INCR, 16'h1, wr_req);
    reset_edge_stale_commit = wr_req;
    issue_read(64'h1A20, 0, 2, AXI_INCR, 16'h2, rd_req);
    `uvm_info("AXI_RESET_TEST", $sformatf(
      "issued write seq/txn=%0d/%0d and read seq/txn=%0d/%0d",
      wr_req.get_sequence_id(), wr_req.get_transaction_id(),
      rd_req.get_sequence_id(), rd_req.get_transaction_id()), UVM_LOW)
    wait (aw_accepted && w_accepted && ar_accepted);
    disable observe_reset_acceptance;
    reset_requests_accepted = 1;

    wait (reset_released);
    fork : wait_for_reset_responses
      begin
        wait_response(wr_req, wr_rsp);
        wr_response_received = 1;
        wait_response(rd_req, rd_rsp);
        rd_response_received = 1;
      end
      begin
        repeat (500) @(posedge cfg.vif.aclk);
        if (!wr_response_received || !rd_response_received)
          `uvm_error("AXI_RESET_TEST",
            "accepted requests did not receive abort responses")
      end
    join_any
    if (!wr_response_received || !rd_response_received) begin
      disable wait_for_reset_responses;
      return;
    end
    disable wait_for_reset_responses;

    if (wr_rsp.aborted)
      aborted_response_count++;
    if (rd_rsp.aborted)
      aborted_response_count++;
    if (!wr_rsp.aborted || !rd_rsp.aborted || aborted_response_count != 2)
      `uvm_error("AXI_RESET_TEST",
        "accepted requests did not receive abort responses")
    if (response_count_by_txn[wr_req.get_transaction_id()] != 1 ||
        response_count_by_txn[rd_req.get_transaction_id()] != 1)
      `uvm_error("AXI_RESET_TEST",
        "accepted requests did not receive exactly one abort response each")
    if (wr_rsp.addr != 64'h1A00 || rd_rsp.addr != 64'h1A20)
      `uvm_error("AXI_RESET_TEST",
        "abort response identity did not match accepted requests")
    if (wr_rsp.resp.size() != 0 || wr_rsp.rdata.size() != 0 ||
        rd_rsp.resp.size() != 0 || rd_rsp.rdata.size() != 0)
      `uvm_error("AXI_RESET_TEST",
        "abort responses were not empty")
    `uvm_info("AXI_RESET_TEST", $sformatf(
      "accepted pre-reset requests received %0d abort responses",
      aborted_response_count), UVM_LOW)

    do_read(64'h1A00, 0, 2, AXI_INCR, 16'h5, reset_rsp);
    check_data("reset pre-reset-address read", reset_rsp,
               64'h1A00, reset_data);
    `uvm_info("AXI_RESET_TEST",
      "pre-reset address returned reset contents", UVM_LOW)

    do_write(64'h1B00, clean_data, 0, 2, AXI_INCR, 16'h3);
    do_read(64'h1B00, 0, 2, AXI_INCR, 16'h4, clean_rsp);
    check_data("clean post-reset read", clean_rsp, 64'h1B00, clean_data);
    if (response_count_by_txn[wr_req.get_transaction_id()] != 1 ||
        response_count_by_txn[rd_req.get_transaction_id()] != 1)
      `uvm_error("AXI_RESET_TEST",
        "stale duplicate response appeared after reset")
    `uvm_info("AXI_RESET_TEST",
      "clean post-reset write/read completed with expected data", UVM_LOW)
  endtask

  protected task run_derived_reset();
    bit [7:0] data[] = '{8'hD1, 8'hD2, 8'hD3, 8'hD4};
    axi_seq_item req_a;
    axi_seq_item req_b;
    axi_seq_item rsp_a;
    axi_seq_item rsp_b;

    if (reset_derived_interleaved) begin
      issue_read(64'h1C00, 1, 2, AXI_INCR, 16'h6, req_a);
      issue_read(64'h1C20, 1, 2, AXI_INCR, 16'h7, req_b);
    end else if (reset_derived_same_cycle) begin
      issue_write(64'h1C40, data, 0, 2, AXI_INCR, 16'h8, req_a);
      issue_read(64'h1C40, 0, 2, AXI_INCR, 16'h9, req_b);
    end
    derived_requests_issued = 1;
    wait (reset_released);

    if (!reset_derived_unmatched) begin
      wait_response(req_a, rsp_a);
      wait_response(req_b, rsp_b);
      if (!rsp_a.aborted || !rsp_b.aborted)
        `uvm_error("AXI_DERIVED_RESET",
          "derived-driver requests did not receive abort responses")
    end
    repeat (2) @(posedge cfg.vif.aclk);
  endtask

  protected task run_commit_before_response();
    bit [7:0] data[] = '{8'hC1, 8'hC2, 8'hC3, 8'hC4};
    axi_seq_item wr_req;
    axi_seq_item wr_rsp;
    axi_seq_item rd_req;
    axi_seq_item rd_rsp;
    bit b_seen;
    int unsigned match_count_before = scoreboard.match_count;

    fork : observe_delayed_b
      begin
        do @(posedge cfg.vif.aclk);
        while (!(cfg.vif.bvalid && cfg.vif.bready));
        b_seen = 1;
      end
    join_none

    // The two observers deliberately watch only the existing interface; the
    // RED test does not depend on the monitor's later commit counter API.
    fork
      issue_write(64'h1920, data, 0, 2, AXI_INCR, 16'hB, wr_req);
      begin
        do @(posedge cfg.vif.aclk);
        while (!(cfg.vif.awvalid && cfg.vif.awready));
      end
      begin
        do @(posedge cfg.vif.aclk);
        while (!(cfg.vif.wvalid && cfg.vif.wready && cfg.vif.wlast));
      end
    join

    issue_read(64'h1920, 0, 2, AXI_INCR, 16'hC, rd_req);
    wait_response(rd_req, rd_rsp);
    check_data("commit-before-response read", rd_rsp, 64'h1920, data);

    if (r_before_b) begin
      int cycles;
      while (cycles < 100 && scoreboard.match_count == match_count_before &&
             !b_seen) begin
        @(posedge cfg.vif.aclk);
        cycles++;
      end
      if (scoreboard.match_count == match_count_before)
        `uvm_error("AXI_LIFECYCLE",
          "scoreboard did not match read before delayed B")
      if (b_seen)
        `uvm_error("AXI_LIFECYCLE",
          "write response completed before read response and scoreboard match")
    end

    wait_response(wr_req, wr_rsp);
    if (wr_rsp == null || wr_rsp.aborted || wr_rsp.resp.size() != 1)
      `uvm_error("AXI_LIFECYCLE", "write lifecycle response was incomplete")
    begin
      int cycles;
      while (cycles < 100 && scoreboard.match_count == match_count_before) begin
        @(posedge cfg.vif.aclk);
        cycles++;
      end
    end
    if (scoreboard.match_count == match_count_before)
      `uvm_error("AXI_LIFECYCLE", "same-cycle response produced no scoreboard match")
    disable observe_delayed_b;
  endtask

  protected task run_malformed_last();
    axi_seq_item req;
    axi_seq_item rsp;

    issue_read(64'h1930, 1, 2, AXI_INCR, 16'hD, req);
    wait_response(req, rsp);
    if (rsp == null || rsp.aborted)
      `uvm_error("AXI_LIFECYCLE", "malformed-LAST response did not terminate")
  endtask

  virtual task body();
    bit [7:0] data[] = '{8'h31, 8'h42, 8'h53, 8'h64};
    axi_seq_item rsp;

    fork : lifecycle_bus_observers
      begin
        forever begin
          @(posedge cfg.vif.aclk);
          observed_cycle++;
          if (first_aw_cycle == 0 && cfg.vif.awvalid && cfg.vif.awready)
            first_aw_cycle = observed_cycle;
          if (first_w_cycle == 0 && cfg.vif.wvalid && cfg.vif.wready)
            first_w_cycle = observed_cycle;
          if (second_request_started && second_aw_cycle == 0 &&
              cfg.vif.awvalid && cfg.vif.awready)
            second_aw_cycle = observed_cycle;
          if (second_request_started && second_w_cycle == 0 &&
              cfg.vif.wvalid && cfg.vif.wready)
            second_w_cycle = observed_cycle;
          if (w_before_aw && w_before_aw_wlast_cycle == 0 &&
              cfg.vif.wvalid && cfg.vif.wready && cfg.vif.wlast)
            w_before_aw_wlast_cycle = observed_cycle;
          if (w_before_aw && w_before_aw_aw_cycle == 0 &&
              cfg.vif.awvalid && cfg.vif.awready)
            w_before_aw_aw_cycle = observed_cycle;
          if (w_before_aw && !w_before_aw_order_reported &&
              w_before_aw_wlast_cycle != 0 &&
              w_before_aw_aw_cycle != 0) begin
            w_before_aw_order_reported = 1;
            `uvm_info("AXI_W_BEFORE_AW", $sformatf(
              "observed WLAST handshake cycle %0d strictly before AW handshake cycle %0d",
              w_before_aw_wlast_cycle, w_before_aw_aw_cycle), UVM_LOW)
          end
          if (aw_w_same_cycle && same_cycle_aw_cycle == 0 &&
              cfg.vif.awvalid && cfg.vif.awready &&
              cfg.vif.awaddr == 64'h1D00)
            same_cycle_aw_cycle = observed_cycle;
          if (aw_w_same_cycle && same_cycle_wlast_cycle == 0 &&
              cfg.vif.wvalid && cfg.vif.wready && cfg.vif.wlast)
            same_cycle_wlast_cycle = observed_cycle;
          if (ar_snapshot && snapshot_ar_cycle == 0 &&
              cfg.vif.arvalid && cfg.vif.arready &&
              cfg.vif.araddr == 64'h1D40 && cfg.vif.arid == 4'h2)
            snapshot_ar_cycle = observed_cycle;
          if (ar_snapshot && snapshot_new_write_started &&
              snapshot_new_aw_cycle == 0 &&
              cfg.vif.awvalid && cfg.vif.awready &&
              cfg.vif.awaddr == 64'h1D40 && cfg.vif.awid == 4'h3)
            snapshot_new_aw_cycle = observed_cycle;
          if (ar_snapshot && snapshot_new_write_started &&
              snapshot_new_wlast_cycle == 0 &&
              cfg.vif.wvalid && cfg.vif.wready && cfg.vif.wlast)
            snapshot_new_wlast_cycle = observed_cycle;
          if (ar_snapshot && snapshot_new_commit_cycle == 0 &&
              snapshot_new_aw_cycle != 0 &&
              snapshot_new_wlast_cycle != 0) begin
            snapshot_new_commit_cycle =
              (snapshot_new_aw_cycle > snapshot_new_wlast_cycle) ?
              snapshot_new_aw_cycle : snapshot_new_wlast_cycle;
          end
          if (ar_snapshot && snapshot_first_r_cycle == 0 &&
              cfg.vif.rvalid && cfg.vif.rready && cfg.vif.rid == 4'h2)
            snapshot_first_r_cycle = observed_cycle;
        end
      end
    join_none

    if (reset_in_flight) begin
      run_reset_in_flight();
    end else if (reset_derived_interleaved ||
                 reset_derived_same_cycle ||
                 reset_derived_unmatched) begin
      run_derived_reset();
    end else if (unmatched_resp) begin
      repeat (30) @(posedge cfg.vif.aclk);
    end else if (malformed_last) begin
      run_malformed_last();
    end else if (r_before_b || b_r_same_cycle) begin
      run_commit_before_response();
    end else if (reset_while_throttled) begin
      fork : count_b_handshakes
        begin
          forever begin
            do @(posedge cfg.vif.aclk);
            while (!(cfg.vif.bvalid && cfg.vif.bready));
            b_count++;
          end
        end
      join_none

      do_write(64'h1800, data, 8'h00, 3'h2, AXI_INCR, 16'h3);
      wait (b_count == 1);

      second_request_started = 1;
      do_write(64'h1810, data, 8'h00, 3'h2, AXI_INCR, 16'h3);
      second_completion_count++;
      wait (b_count == 2);
      disable count_b_handshakes;

      if (second_completion_count != 1 || b_count != 2)
        `uvm_error("AXI_THROTTLE_RESET",
          "throttled request did not complete exactly once after reset")
      if (second_aw_cycle == 0 || second_w_cycle == 0 ||
          second_aw_cycle >= second_w_cycle)
        `uvm_error("AXI_THROTTLE_RESET", $sformatf(
          "post-reset AW handshake did not precede W handshake: reset=%0d AW=%0d W=%0d",
          reset_release_cycle, second_aw_cycle, second_w_cycle))
      if (reset_release_cycle == 0 ||
          second_aw_cycle <= reset_release_cycle ||
          second_w_cycle <= reset_release_cycle)
        `uvm_error("AXI_THROTTLE_RESET",
          "second AW/W handshook before reset release")
      if (second_aw_cycle != 0 && second_w_cycle != 0 &&
          second_aw_cycle < second_w_cycle &&
          reset_release_cycle != 0 &&
          second_aw_cycle > reset_release_cycle &&
          second_w_cycle > reset_release_cycle)
        `uvm_info("AXI_THROTTLE_RESET", $sformatf(
          "reset released at cycle %0d; AW cycle %0d preceded W cycle %0d",
          reset_release_cycle, second_aw_cycle, second_w_cycle), UVM_LOW)
    end else if (w_before_aw) begin
      fork : count_w_before_aw_b_handshakes
        begin
          forever begin
            do @(posedge cfg.vif.aclk);
            while (!(cfg.vif.bvalid && cfg.vif.bready));
            b_count++;
          end
        end
      join_none
      run_w_before_aw_unaligned();
      disable count_w_before_aw_b_handshakes;
    end else if (aw_w_same_cycle) begin
      run_aw_w_same_cycle();
    end else if (ar_snapshot) begin
      run_ar_snapshot();
    end else if (interleaved_r_collision) begin
      run_interleaved_collision();
    end else begin
      fork
        begin
          do @(posedge cfg.vif.aclk);
          while (!(cfg.vif.bvalid && cfg.vif.bready));
          b_count++;
        end
        begin
          do_write(64'h1800, data, 8'h00, 3'h2, AXI_INCR, 16'h0013);
          #0;
          if (b_count != 1)
            `uvm_error("AXI_LIFECYCLE", "do_write returned before B handshake")
        end
      join

      do_read(64'h1800, 8'h00, 3'h2, AXI_INCR, 16'h0013, rsp);

      if (rsp == null || rsp.resp.size() != 1 || rsp.resp[0] != AXI_OKAY)
        `uvm_error("AXI_LIFECYCLE",
          "read helper did not return one OKAY response")
      if (rsp == null || rsp.rdata.size() != data.size())
        `uvm_error("AXI_LIFECYCLE",
          "read helper returned an incomplete data array")
      else foreach (data[i]) begin
        if (rsp.rdata[i] !== data[i])
          `uvm_error("AXI_LIFECYCLE", $sformatf(
            "byte[%0d] got=0x%02h expected=0x%02h", i, rsp.rdata[i], data[i]))
      end
      if (rsp == null || rsp.id != 16'h0013)
        `uvm_error("AXI_LIFECYCLE",
          "read response did not preserve the original request ID")

      run_same_id_outstanding();
    end

    disable lifecycle_bus_observers;
    if (aw_w_same_cycle) begin
      `uvm_info("AW_W_SAME_CYCLE", $sformatf(
        "observed AW handshake cycle %0d and WLAST handshake cycle %0d",
        same_cycle_aw_cycle, same_cycle_wlast_cycle), UVM_LOW)
      if (same_cycle_aw_cycle == 0 || same_cycle_wlast_cycle == 0 ||
          same_cycle_aw_cycle != same_cycle_wlast_cycle)
        `uvm_error("AW_W_SAME_CYCLE", $sformatf(
          "AW and complete W were not accepted on the same cycle: AW=%0d WLAST=%0d",
          same_cycle_aw_cycle, same_cycle_wlast_cycle))
    end else if (ar_snapshot) begin
      `uvm_info("AR_SNAPSHOT", $sformatf(
        "ordering cycles AR=%0d new_AW=%0d new_WLAST=%0d new_commit=%0d first_R=%0d",
        snapshot_ar_cycle, snapshot_new_aw_cycle,
        snapshot_new_wlast_cycle, snapshot_new_commit_cycle,
        snapshot_first_r_cycle), UVM_LOW)
      if (snapshot_ar_cycle == 0 || snapshot_new_commit_cycle == 0 ||
          snapshot_first_r_cycle == 0 ||
          !(snapshot_ar_cycle < snapshot_new_commit_cycle &&
            snapshot_new_commit_cycle < snapshot_first_r_cycle))
        `uvm_error("AR_SNAPSHOT", $sformatf(
          "expected AR < new write commit < first R, got %0d < %0d < %0d",
          snapshot_ar_cycle, snapshot_new_commit_cycle,
          snapshot_first_r_cycle))
    end else if (w_before_aw) begin
      if (w_before_aw_wlast_cycle == 0 || w_before_aw_aw_cycle == 0 ||
          w_before_aw_wlast_cycle >= w_before_aw_aw_cycle)
        `uvm_error("AXI_W_BEFORE_AW", $sformatf(
          "expected WLAST before AW, got WLAST cycle=%0d AW cycle=%0d",
          w_before_aw_wlast_cycle, w_before_aw_aw_cycle))
    end else if (!unmatched_resp && !malformed_last &&
                 !reset_derived_interleaved &&
                 !reset_derived_same_cycle &&
                 !reset_derived_unmatched) begin
      if (first_aw_cycle == 0 || first_w_cycle == 0 ||
          first_aw_cycle >= first_w_cycle)
        `uvm_error("AXI_LIFECYCLE", $sformatf(
          "test isolation failed: first AW cycle=%0d first W cycle=%0d",
          first_aw_cycle, first_w_cycle))
      else
        `uvm_info("AXI_LIFECYCLE", $sformatf(
          "test isolation proved first AW cycle %0d strictly preceded first W cycle %0d",
          first_aw_cycle, first_w_cycle), UVM_LOW)
    end
  endtask

endclass

class axi_response_lifecycle_test extends axi_base_test;

  `uvm_component_utils(axi_response_lifecycle_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  protected function bit all_components_idle();
    return env.master_agent.driver.is_idle() &&
           env.slave_agent.driver.is_idle() &&
           env.master_agent.monitor.is_idle() &&
           env.slave_agent.monitor.is_idle();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    uvm_report_server server;
    uvm_default_report_server default_server;

    if ($test$plusargs("W_BEFORE_AW"))
      axi_master_driver::type_id::set_type_override(
        axi_w_before_aw_master_driver::get_type());
    if ($test$plusargs("AW_W_SAME_CYCLE"))
      axi_master_driver::type_id::set_type_override(
        axi_aw_w_same_cycle_master_driver::get_type());
    if ($test$plusargs("INTERLEAVED_R_COLLISION") ||
        $test$plusargs("RESET_DERIVED_INTERLEAVED"))
      axi_slave_driver::type_id::set_type_override(
        axi_interleaved_r_slave_driver::get_type());
    if ($test$plusargs("R_BEFORE_B"))
      axi_slave_driver::type_id::set_type_override(
        axi_r_before_b_slave_driver::get_type());
    if ($test$plusargs("B_R_SAME_CYCLE") ||
        $test$plusargs("RESET_DERIVED_SAME_CYCLE"))
      axi_slave_driver::type_id::set_type_override(
        axi_same_cycle_resp_slave_driver::get_type());
    if ($test$plusargs("R_EARLY_LAST") ||
        $test$plusargs("R_MISSING_LAST"))
      axi_slave_driver::type_id::set_type_override(
        axi_malformed_last_slave_driver::get_type());
    if ($test$plusargs("UNMATCHED_RESP") ||
        $test$plusargs("RESET_DERIVED_UNMATCHED"))
      axi_slave_driver::type_id::set_type_override(
        axi_unmatched_resp_slave_driver::get_type());
    super.build_phase(phase);
    if ($test$plusargs("R_EARLY_LAST") ||
        $test$plusargs("R_MISSING_LAST") ||
        $test$plusargs("UNMATCHED_RESP")) begin
      server = uvm_report_server::get_server();
      if (!$cast(default_server, server))
        `uvm_fatal("AXI_LIFECYCLE",
          "negative modes require the default UVM report server")
      default_server.enable_report_id_count_summary = 0;
    end
  endfunction

  virtual function void configure_test();
    super.configure_test();
    cfg.resolve_agent_configs();
    cfg.has_coverage          = 0;
    cfg.slave_cfg.resp_delay_min = 12;
    cfg.slave_cfg.resp_delay_max = 12;
    cfg.slave_cfg.per_channel_bp_enable = 1;
    cfg.master_cfg.per_channel_bp_enable = 1;
    cfg.slave_cfg.aw_bp_cfg.mode = BP_NONE;
    cfg.master_cfg.b_bp_cfg.mode = BP_NONE;
    cfg.master_cfg.r_bp_cfg.mode = BP_NONE;
    if ($test$plusargs("AR_SNAPSHOT")) begin
      cfg.slave_cfg.resp_delay_min = 40;
      cfg.slave_cfg.resp_delay_max = 40;
    end
    if ($test$plusargs("RESET_IN_FLIGHT") ||
        $test$plusargs("RESET_EDGE_RACE") ||
        $test$plusargs("RESET_DERIVED_INTERLEAVED")) begin
      cfg.slave_cfg.resp_delay_min = 100;
      cfg.slave_cfg.resp_delay_max = 100;
    end
    if ($test$plusargs("RESET_DERIVED_SAME_CYCLE") ||
        $test$plusargs("RESET_DERIVED_UNMATCHED")) begin
      cfg.master_cfg.b_bp_cfg.mode        = BP_FIXED_DELAY;
      cfg.master_cfg.b_bp_cfg.fixed_delay = 100;
      cfg.master_cfg.r_bp_cfg.mode        = BP_FIXED_DELAY;
      cfg.master_cfg.r_bp_cfg.fixed_delay = 100;
    end
    if ($test$plusargs("W_BEFORE_AW") ||
        $test$plusargs("AW_W_SAME_CYCLE")) begin
      cfg.slave_cfg.w_bp_cfg.mode = BP_NONE;
    end else begin
      cfg.slave_cfg.w_bp_cfg.mode        = BP_FIXED_DELAY;
      cfg.slave_cfg.w_bp_cfg.fixed_delay = 16;
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_response_lifecycle_seq seq;
    axi_interleaved_r_slave_driver interleaved_driver;
    axi_unmatched_resp_slave_driver unmatched_driver;
    bit reset_mode;
    bit reset_in_flight_mode;
    bit reset_edge_race_mode;
    bit reset_derived_interleaved_mode;
    bit reset_derived_same_cycle_mode;
    bit reset_derived_unmatched_mode;
    bit reset_derived_mode;
    bit collision_mode;
    bit w_before_aw_mode;
    bit aw_w_same_cycle_mode;
    bit ar_snapshot_mode;
    bit negative_mode;
    bit seq_done;
    bit valid_seen_during_reset;
    bit derived_valid_seen_during_reset;
    int unsigned match_count_before;
    int unsigned mismatch_count_before;
    longint unsigned master_write_commit_before;
    longint unsigned slave_write_commit_before;
    int unsigned slave_mem_size_before;

    phase.raise_objection(this, "response lifecycle");
    seq = axi_response_lifecycle_seq::type_id::create("seq");
    reset_mode     = $test$plusargs("RESET_WHILE_THROTTLED");
    reset_edge_race_mode = $test$plusargs("RESET_EDGE_RACE");
    reset_in_flight_mode = $test$plusargs("RESET_IN_FLIGHT") ||
                           reset_edge_race_mode;
    reset_derived_interleaved_mode =
      $test$plusargs("RESET_DERIVED_INTERLEAVED");
    reset_derived_same_cycle_mode =
      $test$plusargs("RESET_DERIVED_SAME_CYCLE");
    reset_derived_unmatched_mode =
      $test$plusargs("RESET_DERIVED_UNMATCHED");
    reset_derived_mode = reset_derived_interleaved_mode ||
                         reset_derived_same_cycle_mode ||
                         reset_derived_unmatched_mode;
    collision_mode = $test$plusargs("INTERLEAVED_R_COLLISION");
    w_before_aw_mode = $test$plusargs("W_BEFORE_AW");
    aw_w_same_cycle_mode = $test$plusargs("AW_W_SAME_CYCLE");
    ar_snapshot_mode = $test$plusargs("AR_SNAPSHOT");
    negative_mode = $test$plusargs("R_EARLY_LAST") ||
                    $test$plusargs("R_MISSING_LAST") ||
                    $test$plusargs("UNMATCHED_RESP");
    seq.reset_while_throttled   = reset_mode;
    seq.reset_in_flight         = reset_in_flight_mode;
    seq.reset_edge_race         = reset_edge_race_mode;
    seq.reset_derived_interleaved = reset_derived_interleaved_mode;
    seq.reset_derived_same_cycle  = reset_derived_same_cycle_mode;
    seq.reset_derived_unmatched   = reset_derived_unmatched_mode;
    seq.interleaved_r_collision = collision_mode;
    seq.w_before_aw             = w_before_aw_mode;
    seq.aw_w_same_cycle         = aw_w_same_cycle_mode;
    seq.ar_snapshot             = ar_snapshot_mode;
    seq.r_before_b              = $test$plusargs("R_BEFORE_B");
    seq.b_r_same_cycle          = $test$plusargs("B_R_SAME_CYCLE");
    seq.malformed_last          = $test$plusargs("R_EARLY_LAST") ||
                                  $test$plusargs("R_MISSING_LAST");
    seq.unmatched_resp          = $test$plusargs("UNMATCHED_RESP");
    seq.scoreboard              = env.scoreboard;
    match_count_before          = env.scoreboard.match_count;
    mismatch_count_before       = env.scoreboard.mismatch_count;
    master_write_commit_before  =
      env.master_agent.monitor.write_commit_count;
    slave_write_commit_before   =
      env.slave_agent.monitor.write_commit_count;
    slave_mem_size_before       = env.ref_mem.get_mem_size();

    if (reset_mode) begin
      cfg.master_cfg.enable_bw_limit       = 1;
      cfg.master_cfg.max_bytes_per_window  = 4;
      cfg.master_cfg.bw_window_cycles      = 1_000_000;
      env.master_agent.driver.bw_limiter.configure(
        cfg.master_cfg.enable_bw_limit,
        cfg.master_cfg.max_bytes_per_window,
        cfg.master_cfg.bw_window_cycles);
    end

    fork : lifecycle_watchdog
      begin
        if (reset_mode) begin
          fork
            seq.start(env.master_agent.sequencer);
            begin
              wait (seq.second_request_started);
              repeat (2) @(posedge cfg.vif.aclk);
              if (!env.master_agent.sequencer.has_do_available())
                `uvm_error("AXI_THROTTLE_RESET",
                  "second request was accepted before reset")
              if (!uvm_hdl_force("tb_top.aresetn", 1'b0))
                `uvm_fatal("AXI_THROTTLE_RESET", "cannot force tb_top.aresetn")
              repeat (5) @(posedge cfg.vif.aclk);
              if (!uvm_hdl_release("tb_top.aresetn"))
                `uvm_fatal("AXI_THROTTLE_RESET", "cannot release tb_top.aresetn")
              if (!uvm_hdl_deposit("tb_top.aresetn", 1'b1))
                `uvm_fatal("AXI_THROTTLE_RESET", "cannot restore tb_top.aresetn")
              wait (cfg.vif.aresetn === 1'b1);
              seq.reset_release_cycle = seq.observed_cycle;
              cfg.slave_cfg.w_bp_cfg.mode        = BP_FIXED_DELAY;
              cfg.slave_cfg.w_bp_cfg.fixed_delay = 5;
              env.slave_agent.driver.w_bp_gen.set_config(
                cfg.slave_cfg.get_bp_cfg("w"));
              cfg.master_cfg.enable_bw_limit = 0;
              env.master_agent.driver.bw_limiter.configure(0, 1024, 100);
            end
          join
        end else if (reset_in_flight_mode) begin
          fork
            seq.start(env.master_agent.sequencer);
            begin
              wait (seq.reset_requests_accepted);
              match_count_before = env.scoreboard.match_count;
              mismatch_count_before = env.scoreboard.mismatch_count;
              if (!uvm_hdl_force("tb_top.aresetn", 1'b0))
                `uvm_fatal("AXI_RESET_TEST", "cannot force tb_top.aresetn")
              if (reset_edge_race_mode) begin
                #0;
                env.scoreboard.write_write_commit(
                  seq.reset_edge_stale_commit);
                `uvm_info("AXI_RESET_EDGE",
                  "injected deterministic same-slot late write callback",
                  UVM_LOW)
              end
              repeat (5) begin
                @(posedge cfg.vif.aclk);
                if (cfg.vif.awvalid || cfg.vif.wvalid || cfg.vif.arvalid ||
                    cfg.vif.bvalid || cfg.vif.rvalid) begin
                  valid_seen_during_reset = 1;
                  `uvm_error("AXI_RESET_TEST",
                    "VALID remained asserted during reset")
                end
              end
              if (!valid_seen_during_reset)
                `uvm_info("AXI_RESET_TEST",
                  "all AXI VALID signals remained low during reset", UVM_LOW)
              if (!uvm_hdl_release("tb_top.aresetn"))
                `uvm_fatal("AXI_RESET_TEST", "cannot release tb_top.aresetn")
              if (!uvm_hdl_deposit("tb_top.aresetn", 1'b1))
                `uvm_fatal("AXI_RESET_TEST", "cannot restore tb_top.aresetn")
              wait (cfg.vif.aresetn === 1'b1);
              @(posedge cfg.vif.aclk);
              seq.reset_released = 1;
            end
          join
        end else if (reset_derived_mode) begin
          fork
            seq.start(env.master_agent.sequencer);
            begin
              wait (seq.derived_requests_issued);
              if (reset_derived_interleaved_mode) begin
                if (!$cast(interleaved_driver, env.slave_agent.driver))
                  `uvm_fatal("AXI_DERIVED_RESET",
                    "interleaved reset mode did not install its driver")
                do @(posedge cfg.vif.aclk);
                while (!interleaved_driver.has_two_active_responses());
              end else if (reset_derived_unmatched_mode) begin
                if (!$cast(unmatched_driver, env.slave_agent.driver))
                  `uvm_fatal("AXI_DERIVED_RESET",
                    "unmatched reset mode did not install its driver")
                do @(posedge cfg.vif.aclk);
                while (!unmatched_driver.has_active_unmatched_injection());
                if (unmatched_driver.get_unmatched_injection_attempt_count() != 1)
                  `uvm_error("AXI_DERIVED_RESET",
                    "unmatched driver did not start exactly one injection attempt")
                if (env.slave_agent.driver.is_idle())
                  `uvm_error("AXI_DERIVED_RESET",
                    "unmatched runtime injection was absent from public is_idle")
                else
                  `uvm_info("AXI_DERIVED_RESET",
                    "unmatched runtime injection is active through public is_idle",
                    UVM_LOW)
                wait (cfg.vif.bvalid && cfg.vif.rvalid);
              end else begin
                wait (cfg.vif.bvalid && cfg.vif.rvalid);
              end
              if (!uvm_hdl_force("tb_top.aresetn", 1'b0))
                `uvm_fatal("AXI_DERIVED_RESET",
                  "cannot force tb_top.aresetn")
              repeat (5) begin
                @(posedge cfg.vif.aclk);
                if (cfg.vif.bvalid || cfg.vif.rvalid) begin
                  derived_valid_seen_during_reset = 1;
                  `uvm_error("AXI_DERIVED_RESET",
                    "derived driver kept response VALID asserted in reset")
                end
              end
              if (!derived_valid_seen_during_reset)
                `uvm_info("AXI_DERIVED_RESET",
                  "derived driver response VALID signals stayed low in reset",
                  UVM_LOW)
              if (!uvm_hdl_release("tb_top.aresetn"))
                `uvm_fatal("AXI_DERIVED_RESET",
                  "cannot release tb_top.aresetn")
              if (!uvm_hdl_deposit("tb_top.aresetn", 1'b1))
                `uvm_fatal("AXI_DERIVED_RESET",
                  "cannot restore tb_top.aresetn")
              wait (cfg.vif.aresetn === 1'b1);
              @(posedge cfg.vif.aclk);
              seq.reset_released = 1;
            end
          join
        end else begin
          seq.start(env.master_agent.sequencer);
        end
        seq_done = 1;
      end
      begin
        if (reset_in_flight_mode || reset_derived_mode)
          repeat (500) @(posedge cfg.vif.aclk);
        else if (w_before_aw_mode)
          repeat (200) @(posedge cfg.vif.aclk);
        else
          repeat (800) @(posedge cfg.vif.aclk);
        if (!seq_done) begin
          if (reset_in_flight_mode)
            `uvm_error("AXI_RESET_TEST",
              "accepted requests did not receive abort responses")
          else if (reset_derived_mode)
            `uvm_error("AXI_DERIVED_RESET",
              "derived-driver reset mode did not complete")
          else if (reset_mode)
            `uvm_error("AXI_THROTTLE_RESET",
              "AXI_THROTTLE_RESET request stranded across reset")
          else if (w_before_aw_mode && seq.b_count == 0)
            `uvm_error("AXI_W_BEFORE_AW",
              "W_BEFORE_AW watchdog expired before B completion")
          else if (w_before_aw_mode)
            `uvm_error("AXI_W_BEFORE_AW",
              "W_BEFORE_AW sequence exceeded 200 cycles after B completion")
          else if (collision_mode)
            `uvm_error("AXI_INTERLEAVED_R",
              "interleaved read collision exceeded 800 cycles")
          else
            `uvm_error("AXI_LIFECYCLE",
              "response lifecycle sequence exceeded 800 cycles")
        end
      end
    join_any
    disable lifecycle_watchdog;

    if ((aw_w_same_cycle_mode || ar_snapshot_mode) && seq_done) begin
      int unsigned expected_writes = aw_w_same_cycle_mode ? 1 : 2;
      int unsigned expected_matches = aw_w_same_cycle_mode ? 1 : 2;
      int cycles = 0;

      while (cycles < 200 &&
             (!all_components_idle() ||
              (env.master_agent.monitor.write_commit_count -
               master_write_commit_before) != expected_writes ||
              (env.slave_agent.monitor.write_commit_count -
               slave_write_commit_before) != expected_writes ||
              (env.scoreboard.match_count - match_count_before) !=
                expected_matches)) begin
        @(posedge cfg.vif.aclk);
        cycles++;
      end
      if ((env.master_agent.monitor.write_commit_count -
           master_write_commit_before) != expected_writes)
        `uvm_error(aw_w_same_cycle_mode ? "AW_W_SAME_CYCLE" : "AR_SNAPSHOT",
          $sformatf("master monitor write_commit_count delta=%0d expected=%0d",
            env.master_agent.monitor.write_commit_count -
              master_write_commit_before, expected_writes))
      if ((env.slave_agent.monitor.write_commit_count -
           slave_write_commit_before) != expected_writes)
        `uvm_error(aw_w_same_cycle_mode ? "AW_W_SAME_CYCLE" : "AR_SNAPSHOT",
          $sformatf("slave monitor write_commit_count delta=%0d expected=%0d",
            env.slave_agent.monitor.write_commit_count -
              slave_write_commit_before, expected_writes))
      if ((env.scoreboard.match_count - match_count_before) !=
          expected_matches ||
          env.scoreboard.mismatch_count != mismatch_count_before)
        `uvm_error(aw_w_same_cycle_mode ? "AW_W_SAME_CYCLE" : "AR_SNAPSHOT",
          $sformatf("scoreboard match/mismatch delta=%0d/%0d expected=%0d/0",
            env.scoreboard.match_count - match_count_before,
            env.scoreboard.mismatch_count - mismatch_count_before,
            expected_matches))
      if (aw_w_same_cycle_mode &&
          (env.ref_mem.get_mem_size() - slave_mem_size_before) != 4)
        `uvm_error("AW_W_SAME_CYCLE", $sformatf(
          "slave memory byte delta=%0d expected=4 for one write commit",
          env.ref_mem.get_mem_size() - slave_mem_size_before))
      if (!all_components_idle())
        `uvm_error(aw_w_same_cycle_mode ? "AW_W_SAME_CYCLE" : "AR_SNAPSHOT",
          "master/slave drivers and monitors were not idle")
      else
        `uvm_info(aw_w_same_cycle_mode ? "AW_W_SAME_CYCLE" : "AR_SNAPSHOT",
          $sformatf(
            "count evidence master/slave write commits=%0d/%0d scoreboard=%0d/%0d; all drivers/monitors idle",
            env.master_agent.monitor.write_commit_count -
              master_write_commit_before,
            env.slave_agent.monitor.write_commit_count -
              slave_write_commit_before,
            env.scoreboard.match_count - match_count_before,
            env.scoreboard.mismatch_count - mismatch_count_before), UVM_LOW)
    end

    if (reset_in_flight_mode && seq_done) begin
      @(posedge cfg.vif.aclk);
      if ((env.scoreboard.match_count - match_count_before) != 2)
        `uvm_error("AXI_RESET_TEST", $sformatf(
          "post-reset scoreboard match delta=%0d expected=2",
          env.scoreboard.match_count - match_count_before))
      if (env.scoreboard.mismatch_count != mismatch_count_before)
        `uvm_error("AXI_RESET_TEST", $sformatf(
          "post-reset scoreboard mismatch delta=%0d expected=0",
          env.scoreboard.mismatch_count - mismatch_count_before))
      if (!all_components_idle())
        `uvm_error("AXI_RESET_TEST",
          "transaction state was not idle after post-reset traffic")
      else
        `uvm_info("AXI_RESET_TEST",
          "master/slave drivers and both monitors are idle", UVM_LOW)
    end else if (reset_derived_mode && seq_done) begin
      @(posedge cfg.vif.aclk);
      if (reset_derived_unmatched_mode) begin
        if (unmatched_driver.has_active_unmatched_injection())
          `uvm_error("AXI_DERIVED_RESET",
            "unmatched runtime injection remained active after reset")
        if (unmatched_driver.get_unmatched_injection_attempt_count() != 1)
          `uvm_error("AXI_DERIVED_RESET",
            "unmatched driver reinjected after its test epoch was consumed")
        else
          `uvm_info("AXI_DERIVED_RESET",
            "unmatched injection attempted exactly once and runtime state is idle",
            UVM_LOW)
      end
      if (!all_components_idle())
        `uvm_error("AXI_DERIVED_RESET",
          "derived driver retained transaction state after reset")
      else
        `uvm_info("AXI_DERIVED_RESET",
          "derived driver reset state and all public idle APIs are clean",
          UVM_LOW)
    end else if (!negative_mode && !reset_mode &&
                 !reset_in_flight_mode && !reset_derived_mode) begin
      int cycles = 0;
      while (cycles < 200 &&
             (env.master_agent.monitor.cur_outstanding_rd != 0 ||
              env.master_agent.monitor.cur_outstanding_wr != 0 ||
              env.scoreboard.match_count == match_count_before)) begin
        @(posedge cfg.vif.aclk);
        cycles++;
      end
      if (env.scoreboard.match_count == match_count_before)
        `uvm_error("AXI_LIFECYCLE", "scoreboard saw no complete read")
      if (env.scoreboard.mismatch_count != mismatch_count_before)
        `uvm_error("AXI_LIFECYCLE", $sformatf(
          "scoreboard mismatches=%0d", env.scoreboard.mismatch_count))
      if (env.master_agent.monitor.cur_outstanding_rd != 0 ||
          env.master_agent.monitor.cur_outstanding_wr != 0)
        `uvm_error("AXI_LIFECYCLE", "monitor retained completed traffic")
    end

    phase.drop_objection(this, "response lifecycle complete");
  endtask

endclass

`endif // AXI_RESPONSE_LIFECYCLE_TEST_SV
