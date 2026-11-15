`ifndef AXI_SLAVE_DRIVER_SV
`define AXI_SLAVE_DRIVER_SV

class axi_slave_driver extends uvm_driver #(axi_seq_item);

  `uvm_component_utils(axi_slave_driver)

  virtual axi_if     vif;
  axi_config         cfg;
  axi_slave_config   agent_cfg;
  axi_ref_model      ref_mem;

  axi_bp_generator   aw_bp_gen;
  axi_bp_generator   w_bp_gen;
  axi_bp_generator   ar_bp_gen;

  mailbox #(axi_seq_item) rd_resp_mbx;
  mailbox #(axi_seq_item) wr_resp_mbx;

  protected axi_seq_item pending_aw_q[$];
  protected axi_w_burst_record complete_w_q[$];
  protected axi_w_burst_record active_w;
  protected axi_seq_item active_b;
  protected axi_seq_item active_r;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null)
      `uvm_fatal("CFG", "axi_slave_driver: common config is null")
    if (agent_cfg == null)
      `uvm_fatal("CFG", "axi_slave_driver: slave config is null")
    if (vif == null)
      `uvm_fatal("CFG", "axi_slave_driver: virtual interface is null")
    rd_resp_mbx = new(0);
    wr_resp_mbx = new(0);
    aw_bp_gen = axi_bp_generator::type_id::create("aw_bp_gen");
    w_bp_gen  = axi_bp_generator::type_id::create("w_bp_gen");
    ar_bp_gen = axi_bp_generator::type_id::create("ar_bp_gen");
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    aw_bp_gen.set_config(agent_cfg.get_bp_cfg("aw"));
    w_bp_gen.set_config(agent_cfg.get_bp_cfg("w"));
    ar_bp_gen.set_config(agent_cfg.get_bp_cfg("ar"));
  endfunction

  virtual function bit is_idle();
    return pending_aw_q.size() == 0 &&
           complete_w_q.size() == 0 &&
           active_w == null &&
           rd_resp_mbx.num() == 0 &&
           wr_resp_mbx.num() == 0 &&
           active_b == null &&
           active_r == null;
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.claim_slave_drive();
    forever begin
      vif.reset_slave_signals();
      wait(vif.aresetn === 1'b1);
      // Discard any drive NBA that was queued in the reset-assertion slot.
      vif.reset_slave_signals();
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        continue;
      fork : active_workers
        run_active_workers();
        begin
          wait(vif.aresetn !== 1'b1);
        end
      join_any
      disable active_workers;
      clear_state();
    end
  endtask

  protected virtual task run_active_workers();
    fork
      handle_request_channels();
      drive_r_channel();
      drive_b_channel();
    join
  endtask

  protected virtual task clear_state();
    pending_aw_q.delete();
    complete_w_q.delete();
    active_w = null;
    active_b = null;
    active_r = null;
    rd_resp_mbx = new(0);
    wr_resp_mbx = new(0);
    ref_mem.reset();
    vif.reset_slave_signals();
  endtask

  virtual task handle_request_channels();
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
      if (vif.awvalid && vif.awready) begin
        axi_seq_item item = axi_seq_item::type_id::create("aw_rcv");
        item.txn_type   = AXI_WRITE;
        item.id         = vif.awid;
        item.addr       = vif.awaddr;
        item.burst_len  = vif.awlen;
        item.burst_size = vif.awsize;
        item.burst_type = axi_burst_type_e'(vif.awburst);
        item.lock       = vif.awlock;
        item.cache      = vif.awcache;
        item.prot       = vif.awprot;
        item.qos        = vif.awqos;
        item.region     = vif.awregion;
        item.cfg        = cfg;
        item.addr_phase_time = $time;
        pending_aw_q.push_back(item);
        `uvm_info("SLV_DRV", $sformatf("AW received: %s", item.convert2string()), UVM_HIGH)
      end

      if (vif.wvalid && vif.wready) begin
        if (active_w == null)
          active_w = new();
        active_w.push(vif.wdata, vif.wstrb, $time);
        if (vif.wlast) begin
          complete_w_q.push_back(active_w);
          active_w = null;
        end
      end

      pair_completed_writes();

      if (vif.arvalid && vif.arready) begin
        axi_seq_item item = axi_seq_item::type_id::create("ar_rcv");
        int unsigned bus_bytes = cfg.data_width / 8;

        item.txn_type   = AXI_READ;
        item.id         = vif.arid;
        item.addr       = vif.araddr;
        item.burst_len  = vif.arlen;
        item.burst_size = vif.arsize;
        item.burst_type = axi_burst_type_e'(vif.arburst);
        item.lock       = vif.arlock;
        item.cache      = vif.arcache;
        item.prot       = vif.arprot;
        item.qos        = vif.arqos;
        item.region     = vif.arregion;
        item.cfg        = cfg;
        item.addr_phase_time = $time;
        if (ref_mem != null) begin
          ref_mem.burst_read(item, item.rdata);
        end else begin
          item.rdata = new[item.get_total_bytes()];
          if (bus_bytes == 0 || bus_bytes > 64) begin
            `uvm_error("SLV_DRV", $sformatf(
              "unsupported bus_bytes=%0d while snapshotting AR", bus_bytes))
          end else begin
            for (int beat = 0; beat <= item.burst_len; beat++) begin
              for (int i = 0; i < item.get_bytes_per_beat(); i++) begin
                int unsigned data_index = item.beat_data_index(beat, i);
                if (item.beat_byte_valid(beat, i, bus_bytes))
                  item.rdata[data_index] = 8'hDE;
              end
            end
          end
        end
        rd_resp_mbx.put(item);
        `uvm_info("SLV_DRV", $sformatf("AR received: %s", item.convert2string()), UVM_HIGH)
      end

      vif.slave_awready <= aw_bp_gen.get_ready();
      vif.slave_wready  <= w_bp_gen.get_ready();
      vif.slave_arready <= ar_bp_gen.get_ready();
    end
  endtask

  protected task pair_completed_writes();
    int unsigned bus_bytes = cfg.data_width / 8;

    while (pending_aw_q.size() > 0 && complete_w_q.size() > 0) begin
      axi_seq_item aw = pending_aw_q.pop_front();
      axi_w_burst_record raw = complete_w_q.pop_front();

      if (raw.size() != (aw.burst_len + 1))
        `uvm_error("SLV_DRV", $sformatf(
          "W beat count=%0d does not match AWLEN+1=%0d for ID 0x%0h",
          raw.size(), aw.burst_len + 1, aw.id))
      aw.unpack_w_burst(raw, bus_bytes);
      aw.data_start_time = raw.start_time;
      aw.data_end_time   = raw.end_time;
      if (ref_mem != null)
        ref_mem.burst_write(aw);
      wr_resp_mbx.put(aw);
    end
  endtask

  virtual task drive_r_channel();
    forever begin
      int unsigned bus_bytes = cfg.data_width / 8;
      rd_resp_mbx.get(active_r);
      apply_resp_delay();
      if (vif.aresetn !== 1'b1)
        return;
      for (int beat = 0; beat <= active_r.burst_len; beat++) begin
        int unsigned bytes_per_beat;
        bit [511:0] rdata_packed;
        axi_resp_e beat_resp;

        bytes_per_beat = active_r.get_bytes_per_beat();
        rdata_packed   = '0;

        if (bus_bytes == 0 || bus_bytes > 64)
          `uvm_fatal("SLV_DRV", $sformatf(
            "unsupported bus_bytes=%0d while driving R", bus_bytes))
        for (int i = 0; i < bytes_per_beat; i++) begin
          int unsigned data_index = active_r.beat_data_index(beat, i);

          if (active_r.beat_byte_valid(beat, i, bus_bytes) &&
              data_index < active_r.rdata.size()) begin
            int unsigned lane = active_r.beat_byte_lane(beat, i, bus_bytes);
            rdata_packed[lane*8 +: 8] = active_r.rdata[data_index];
          end
        end

        beat_resp = AXI_OKAY;
        if (active_r.lock && beat == 0 && ref_mem != null)
          beat_resp = ref_mem.exclusive_write(active_r.id, active_r.addr);

        if (agent_cfg.enable_err_inject && active_r.inject_err) begin
          if (active_r.err_type == ERR_RESP && beat == active_r.err_beat)
            beat_resp = AXI_SLVERR;
          if (active_r.err_type == ERR_DATA_CORRUPT && beat == active_r.err_beat)
            rdata_packed[7:0] = rdata_packed[7:0] ^ 8'hFF;
          if (active_r.err_type == ERR_TIMEOUT && beat == active_r.err_beat) begin
            repeat(1000) begin
              @(posedge vif.aclk);
              if (vif.aresetn !== 1'b1)
                return;
            end
          end
        end

        vif.slave_rid    <= active_r.id;
        vif.slave_rdata  <= rdata_packed;
        vif.slave_rresp  <= beat_resp;
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
      axi_resp_e wresp;
      wr_resp_mbx.get(active_b);
      apply_resp_delay();
      if (vif.aresetn !== 1'b1)
        return;
      wresp = AXI_OKAY;
      if (active_b.lock && ref_mem != null)
        wresp = ref_mem.exclusive_write(active_b.id, active_b.addr);
      if (agent_cfg.enable_err_inject && active_b.inject_err &&
          active_b.err_type == ERR_RESP)
        wresp = AXI_SLVERR;
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
      vif.slave_bid    <= active_b.id;
      vif.slave_bresp  <= wresp;
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

  protected task apply_resp_delay();
    int unsigned delay;
    if (agent_cfg.resp_delay_max > agent_cfg.resp_delay_min)
      delay = $urandom_range(agent_cfg.resp_delay_min,
                             agent_cfg.resp_delay_max);
    else
      delay = agent_cfg.resp_delay_min;
    repeat(delay) begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
    end
  endtask

endclass

`endif // AXI_SLAVE_DRIVER_SV
