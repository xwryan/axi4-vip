`ifndef AXI_MASTER_DRIVER_SV
`define AXI_MASTER_DRIVER_SV

class axi_master_driver extends uvm_driver #(axi_seq_item);

  `uvm_component_utils(axi_master_driver)

  virtual axi_if     vif;
  axi_config         cfg;
  axi_master_config  agent_cfg;
  axi_bp_generator   b_bp_gen;
  axi_bp_generator   r_bp_gen;
  axi_bw_limiter     bw_limiter;

  mailbox #(axi_seq_item) aw_mbx;
  mailbox #(axi_seq_item) w_mbx;
  mailbox #(axi_seq_item) ar_mbx;

  int unsigned max_pending_wr_seen;
  int unsigned max_pending_rd_seen;

  protected axi_seq_item pending_wr_q[$];
  protected axi_seq_item pending_rd_q[$];
  protected axi_seq_item active_aw;
  protected axi_seq_item active_w_req;
  protected axi_seq_item active_ar;
  protected axi_seq_item active_fetch_item;
  protected longint unsigned reset_generation;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    max_pending_wr_seen = 0;
    max_pending_rd_seen = 0;
    reset_generation = 0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null)
      `uvm_fatal("CFG", "axi_master_driver: common config is null")
    if (agent_cfg == null)
      `uvm_fatal("CFG", "axi_master_driver: master config is null")
    if (vif == null)
      `uvm_fatal("CFG", "axi_master_driver: virtual interface is null")
    aw_mbx = new(0);
    w_mbx  = new(0);
    ar_mbx = new(0);
    b_bp_gen = axi_bp_generator::type_id::create("b_bp_gen");
    r_bp_gen = axi_bp_generator::type_id::create("r_bp_gen");
    bw_limiter = axi_bw_limiter::type_id::create("bw_limiter");
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    b_bp_gen.set_config(agent_cfg.get_bp_cfg("b"));
    r_bp_gen.set_config(agent_cfg.get_bp_cfg("r"));
    bw_limiter.configure(agent_cfg.enable_bw_limit,
                         agent_cfg.max_bytes_per_window,
                         agent_cfg.bw_window_cycles);
  endfunction

  virtual function bit is_idle();
    return pending_wr_q.size() == 0 &&
           pending_rd_q.size() == 0 &&
           aw_mbx.num() == 0 &&
           w_mbx.num() == 0 &&
           ar_mbx.num() == 0 &&
           active_aw == null &&
           active_w_req == null &&
           active_ar == null &&
           active_fetch_item == null;
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.claim_master_drive();
    fork
      fetch_items();
      supervise_channel_workers();
    join
  endtask

  protected task supervise_channel_workers();
    forever begin
      vif.reset_master_signals();
      wait(vif.aresetn === 1'b1);
      // Discard any drive NBA that was queued in the reset-assertion slot.
      vif.reset_master_signals();
      fork : reset_epoch
        begin
          @(posedge vif.aclk);
          if (vif.aresetn === 1'b1) begin
            fork : channel_workers
              drive_aw_channel();
              drive_w_channel();
              drive_ar_channel();
              handle_b_channel();
              handle_r_channel();
              bw_tick_loop();
            join_none
          end
          forever @(posedge vif.aclk);
        end
        begin
          wait(vif.aresetn !== 1'b1);
          reset_generation++;
        end
      join_any
      disable reset_epoch;
      abort_and_clear();
    end
  endtask

  protected task abort_and_clear();
    `uvm_info("MST_DRV_RESET", $sformatf(
      "reset clearing pending writes=%0d reads=%0d",
      pending_wr_q.size(), pending_rd_q.size()), UVM_LOW)
    while (pending_wr_q.size() > 0) begin
      axi_seq_item req = pending_wr_q.pop_front();

      req.resp      = new[0];
      req.rdata     = new[0];
      req.resp_time = $time;
      req.aborted   = 1;
      send_response(req);
      `uvm_info("MST_DRV_RESET", $sformatf(
        "sent write abort sequence_id=%0d transaction_id=%0d",
        req.get_sequence_id(), req.get_transaction_id()), UVM_LOW)
    end
    while (pending_rd_q.size() > 0) begin
      axi_seq_item req = pending_rd_q.pop_front();

      req.resp      = new[0];
      req.rdata     = new[0];
      req.resp_time = $time;
      req.aborted   = 1;
      send_response(req);
      `uvm_info("MST_DRV_RESET", $sformatf(
        "sent read abort sequence_id=%0d transaction_id=%0d",
        req.get_sequence_id(), req.get_transaction_id()), UVM_LOW)
    end
    pending_wr_q.delete();
    pending_rd_q.delete();
    aw_mbx = new(0);
    w_mbx  = new(0);
    ar_mbx = new(0);
    active_aw    = null;
    active_w_req = null;
    active_ar    = null;
    vif.reset_master_signals();
  endtask

  virtual task fetch_items();
    forever begin
      axi_seq_item item;
      longint unsigned acquisition_generation;

      wait(vif.aresetn === 1'b1);
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        continue;
      if (agent_cfg.enable_bw_limit && bw_limiter.is_throttled())
        continue;

      acquisition_generation = reset_generation;
      item = null;
      seq_item_port.try_next_item(item);
      if (item == null)
        continue;
      active_fetch_item = item;
      if (vif.aresetn !== 1'b1 ||
          acquisition_generation != reset_generation) begin
        abort_active_fetch();
        continue;
      end
      begin
        bit reset_seen;

        wait_for_capacity(item.txn_type, reset_seen);
        if (reset_seen || vif.aresetn !== 1'b1 ||
            acquisition_generation != reset_generation) begin
          abort_active_fetch();
          continue;
        end
      end
      if (item.txn_type == AXI_WRITE) begin
        axi_seq_item aw_req;
        axi_seq_item w_req;
        axi_seq_item rsp_req;

        aw_req  = clone_request(item, "aw_req");
        w_req   = clone_request(item, "w_req");
        rsp_req = clone_request(item, "wr_rsp_req");
        pending_wr_q.push_back(rsp_req);
        if (pending_wr_q.size() > max_pending_wr_seen)
          max_pending_wr_seen = pending_wr_q.size();
        aw_mbx.put(aw_req);
        w_mbx.put(w_req);
      end else begin
        axi_seq_item ar_req;
        axi_seq_item rsp_req;

        ar_req  = clone_request(item, "ar_req");
        rsp_req = clone_request(item, "rd_rsp_req");
        pending_rd_q.push_back(rsp_req);
        if (pending_rd_q.size() > max_pending_rd_seen)
          max_pending_rd_seen = pending_rd_q.size();
        ar_mbx.put(ar_req);
      end
      if (agent_cfg.enable_bw_limit)
        bw_limiter.record_sent(item.get_total_bytes());
      active_fetch_item = null;
      seq_item_port.item_done();
    end
  endtask

  protected task abort_active_fetch();
    axi_seq_item aborted_req;

    if (active_fetch_item == null)
      `uvm_fatal("MST_DRV_RESET",
        "cannot abort a request without active fetch ownership")
    aborted_req = clone_request(active_fetch_item, "capacity_reset_rsp");
    aborted_req.resp = new[0];
    aborted_req.rdata = new[0];
    aborted_req.resp_time = $time;
    aborted_req.aborted = 1;
    active_fetch_item = null;
    seq_item_port.item_done();
    send_response(aborted_req);
    `uvm_info("MST_DRV_RESET", $sformatf(
      "sent active-fetch abort sequence_id=%0d transaction_id=%0d",
      aborted_req.get_sequence_id(), aborted_req.get_transaction_id()),
      UVM_LOW)
  endtask

  protected task wait_for_capacity(
    axi_txn_type_e txn_type,
    output bit reset_seen
  );
    reset_seen = 0;
    if (txn_type == AXI_WRITE) begin
      while (pending_wr_q.size() >= agent_cfg.max_outstanding_wr) begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1) begin
          reset_seen = 1;
          return;
        end
      end
    end else begin
      while (pending_rd_q.size() >= agent_cfg.max_outstanding_rd) begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1) begin
          reset_seen = 1;
          return;
        end
      end
    end
  endtask

  virtual task drive_aw_channel();
    forever begin
      aw_mbx.get(active_aw);
      @(posedge vif.aclk);
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

  virtual task drive_w_channel();
    forever begin
      int unsigned bus_bytes = cfg.data_width / 8;
      w_mbx.get(active_w_req);
      for (int beat = 0; beat <= active_w_req.burst_len; beat++) begin
        vif.master_wdata  <= active_w_req.pack_beat_data(beat, bus_bytes);
        vif.master_wstrb  <= active_w_req.pack_beat_wstrb(beat, bus_bytes);
        vif.master_wlast  <= (beat == active_w_req.burst_len);
        vif.master_wvalid <= 1'b1;
        do begin
          @(posedge vif.aclk);
          if (vif.aresetn !== 1'b1)
            return;
        end
        while (!vif.wready);
      end
      vif.master_wvalid <= 1'b0;
      vif.master_wlast  <= 1'b0;
      active_w_req = null;
    end
  endtask

  virtual task drive_ar_channel();
    forever begin
      ar_mbx.get(active_ar);
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
      vif.master_arid     <= active_ar.id;
      vif.master_araddr   <= active_ar.addr;
      vif.master_arlen    <= active_ar.burst_len;
      vif.master_arsize   <= active_ar.burst_size;
      vif.master_arburst  <= active_ar.burst_type;
      vif.master_arlock   <= active_ar.lock;
      vif.master_arcache  <= active_ar.cache;
      vif.master_arprot   <= active_ar.prot;
      vif.master_arqos    <= active_ar.qos;
      vif.master_arregion <= active_ar.region;
      vif.master_arvalid  <= 1'b1;
      do begin
        @(posedge vif.aclk);
        if (vif.aresetn !== 1'b1)
          return;
      end
      while (!vif.arready);
      vif.master_arvalid <= 1'b0;
      active_ar = null;
    end
  endtask

  virtual task handle_b_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
      if (vif.bvalid && vif.bready) begin
        int match;

        match = -1;
        foreach (pending_wr_q[i]) begin
          if (match < 0 && project_bus_id(pending_wr_q[i].id) == vif.bid)
            match = i;
        end

        if (match < 0) begin
          `uvm_error("MST_DRV_BID", $sformatf(
            "BID 0x%0h has no pending request", vif.bid))
        end else begin
          axi_seq_item done;

          done = pending_wr_q[match];
          pending_wr_q.delete(match);
          done.resp = new[1];
          done.resp[0] = axi_resp_e'(vif.bresp);
          done.resp_time = $time;
          done.aborted = 0;
          send_response(done);
        end
      end
      vif.master_bready <= b_bp_gen.get_ready();
    end
  endtask

  virtual task handle_r_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
      if (vif.rvalid && vif.rready) begin
        int match;

        match = -1;
        foreach (pending_rd_q[i]) begin
          if (match < 0 && project_bus_id(pending_rd_q[i].id) == vif.rid)
            match = i;
        end

        if (match < 0) begin
          `uvm_error("MST_DRV_RID", $sformatf(
            "RID 0x%0h has no pending request", vif.rid))
        end else begin
          axi_seq_item done;
          int unsigned beat;
          int unsigned bytes_per_beat;
          int unsigned bus_bytes;
          int unsigned received_beats;
          int unsigned expected_beats;

          done           = pending_rd_q[match];
          beat           = done.resp.size();
          bytes_per_beat = done.get_bytes_per_beat();
          bus_bytes      = cfg.data_width / 8;
          if (bus_bytes == 0 || bus_bytes > 64)
            `uvm_fatal("MST_DRV_R", $sformatf(
              "unsupported bus_bytes=%0d", bus_bytes))

          done.resp = new[beat + 1](done.resp);
          done.resp[beat] = axi_resp_e'(vif.rresp);
          done.rdata = new[(beat + 1) * bytes_per_beat](done.rdata);
          for (int i = 0; i < bytes_per_beat; i++) begin
            int unsigned data_index;

            data_index = done.beat_data_index(beat, i);
            done.rdata[data_index] = 8'h00;
            if (done.beat_byte_valid(beat, i, bus_bytes)) begin
              int unsigned lane = done.beat_byte_lane(beat, i, bus_bytes);
              done.rdata[data_index] = vif.rdata[lane*8 +: 8];
            end
          end

          received_beats = done.resp.size();
          expected_beats = done.burst_len + 1;
          if (vif.rlast) begin
            if (received_beats < expected_beats)
              `uvm_error("MST_DRV_RLAST", $sformatf(
                "early RLAST for RID 0x%0h after %0d of %0d beats",
                vif.rid, received_beats, expected_beats))
            pending_rd_q.delete(match);
            done.resp_time = $time;
            done.aborted = 0;
            send_response(done);
          end else if (received_beats == expected_beats &&
                       !done.rlast_missing_reported) begin
            `uvm_error("MST_DRV_RLAST", $sformatf(
              "missing RLAST for RID 0x%0h at expected beat %0d",
              vif.rid, expected_beats - 1))
            done.rlast_missing_reported = 1;
          end
        end
      end
      vif.master_rready <= r_bp_gen.get_ready();
    end
  endtask

  virtual task bw_tick_loop();
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
      bw_limiter.tick();
    end
  endtask

  protected function axi_seq_item clone_request(
    axi_seq_item req,
    string name
  );
    axi_seq_item copy;

    copy = axi_seq_item::type_id::create(name);
    copy.copy(req);
    copy.set_id_info(req);
    copy.resp = new[0];
    copy.rdata = new[0];
    copy.aborted = 0;
    copy.rlast_missing_reported = 0;
    return copy;
  endfunction

  protected function bit [15:0] project_bus_id(bit [15:0] id);
    int unsigned bus_id_width;
    bit [15:0] mask;

    bus_id_width = $bits(vif.bid);
    if (bus_id_width == 0)
      return '0;
    if (bus_id_width >= $bits(id))
      return id;
    mask = 16'hFFFF >> ($bits(id) - bus_id_width);
    return id & mask;
  endfunction

  protected task send_response(axi_seq_item req);
    axi_seq_item rsp;

    rsp = axi_seq_item::type_id::create({req.get_name(), "_rsp"});
    rsp.copy(req);
    rsp.set_id_info(req);
    seq_item_port.put_response(rsp);
  endtask

endclass

`endif // AXI_MASTER_DRIVER_SV
