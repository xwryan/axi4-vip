`ifndef AXI_MASTER_MONITOR_SV
`define AXI_MASTER_MONITOR_SV

class axi_master_monitor extends uvm_monitor;

  `uvm_component_utils(axi_master_monitor)

  virtual axi_if vif;
  axi_config     cfg;

  uvm_analysis_port #(axi_seq_item) item_collected_port;
  uvm_analysis_port #(axi_seq_item) write_commit_port;
  uvm_analysis_port #(axi_seq_item) read_request_port;

  protected axi_seq_item       wr_addr_q[$];
  protected axi_w_burst_record complete_w_q[$];
  protected axi_w_burst_record active_w;
  protected axi_seq_item       wr_complete_q[$];
  protected axi_seq_item       rd_addr_q[$];

  int unsigned     cur_outstanding_rd;
  int unsigned     cur_outstanding_wr;
  longint unsigned write_commit_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    item_collected_port = new("item_collected_port", this);
    write_commit_port   = new("write_commit_port", this);
    read_request_port   = new("read_request_port", this);
  endfunction

  virtual function bit is_idle();
    return wr_addr_q.size() == 0 &&
           complete_w_q.size() == 0 &&
           wr_complete_q.size() == 0 &&
           rd_addr_q.size() == 0 &&
           active_w == null &&
           cur_outstanding_wr == 0 &&
           cur_outstanding_rd == 0;
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      wait(vif.aresetn === 1'b1);
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        continue;
      fork : active_workers
        monitor_request_channels();
        monitor_b_channel();
        monitor_r_channel();
        begin
          wait(vif.aresetn !== 1'b1);
        end
      join_any
      disable active_workers;
      clear_state();
    end
  endtask

  protected function void clear_state();
    wr_addr_q.delete();
    complete_w_q.delete();
    wr_complete_q.delete();
    rd_addr_q.delete();
    active_w = null;
    cur_outstanding_wr = 0;
    cur_outstanding_rd = 0;
  endfunction

  virtual task monitor_request_channels();
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;

      if (vif.awvalid && vif.awready) begin
        axi_seq_item item = axi_seq_item::type_id::create("aw_item");

        item.txn_type       = AXI_WRITE;
        item.id             = vif.awid;
        item.addr           = vif.awaddr;
        item.burst_len      = vif.awlen;
        item.burst_size     = vif.awsize;
        item.burst_type     = axi_burst_type_e'(vif.awburst);
        item.lock           = vif.awlock;
        item.cache          = vif.awcache;
        item.prot           = vif.awprot;
        item.qos            = vif.awqos;
        item.region         = vif.awregion;
        item.addr_phase_time = $time;
        item.cfg            = cfg;
        cur_outstanding_wr++;
        item.outstanding_at_issue = cur_outstanding_wr;
        wr_addr_q.push_back(item);
        `uvm_info("MON", $sformatf("AW: %s", item.convert2string()), UVM_HIGH)
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
        axi_seq_item item = axi_seq_item::type_id::create("ar_item");

        item.txn_type       = AXI_READ;
        item.id             = vif.arid;
        item.addr           = vif.araddr;
        item.burst_len      = vif.arlen;
        item.burst_size     = vif.arsize;
        item.burst_type     = axi_burst_type_e'(vif.arburst);
        item.lock           = vif.arlock;
        item.cache          = vif.arcache;
        item.prot           = vif.arprot;
        item.qos            = vif.arqos;
        item.region         = vif.arregion;
        item.addr_phase_time = $time;
        item.cfg            = cfg;
        cur_outstanding_rd++;
        item.outstanding_at_issue = cur_outstanding_rd;
        rd_addr_q.push_back(item);
        read_request_port.write(item);
        `uvm_info("MON", $sformatf("AR: %s", item.convert2string()), UVM_HIGH)
      end
    end
  endtask

  protected task pair_completed_writes();
    int unsigned bus_bytes = cfg.data_width / 8;

    while (wr_addr_q.size() > 0 && complete_w_q.size() > 0) begin
      axi_seq_item item = wr_addr_q.pop_front();
      axi_w_burst_record raw = complete_w_q.pop_front();

      if (raw.size() != (item.burst_len + 1))
        `uvm_error("MON_WLAST", $sformatf(
          "W beat count=%0d does not match AWLEN+1=%0d for ID 0x%0h",
          raw.size(), item.burst_len + 1, item.id))
      item.unpack_w_burst(raw, bus_bytes);
      item.data_start_time = raw.start_time;
      item.data_end_time   = raw.end_time;
      wr_complete_q.push_back(item);
      write_commit_count++;
      write_commit_port.write(item);
    end
  endtask

  virtual task monitor_b_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
      if (vif.bvalid && vif.bready) begin
        int match = -1;

        foreach (wr_complete_q[i]) begin
          if (match < 0 && wr_complete_q[i].id == vif.bid)
            match = i;
        end
        if (match < 0) begin
          `uvm_error("MON_BID", $sformatf(
            "BID 0x%0h has no completed write", vif.bid))
        end else begin
          axi_seq_item item = wr_complete_q[match];

          wr_complete_q.delete(match);
          item.resp = new[1];
          item.resp[0] = axi_resp_e'(vif.bresp);
          item.resp_time = $time;
          cur_outstanding_wr--;
          item_collected_port.write(item);
          `uvm_info("MON", $sformatf("B: %s resp=%s lat=%0t",
            item.convert2string(), item.resp[0].name(),
            item.resp_time - item.addr_phase_time), UVM_HIGH)
        end
      end
    end
  endtask

  virtual task monitor_r_channel();
    forever begin
      @(posedge vif.aclk);
      if (vif.aresetn !== 1'b1)
        return;
      if (vif.rvalid && vif.rready) begin
        int match = -1;

        foreach (rd_addr_q[i]) begin
          if (match < 0 && rd_addr_q[i].id == vif.rid)
            match = i;
        end
        if (match < 0) begin
          `uvm_error("MON_RID", $sformatf(
            "RID 0x%0h has no pending read", vif.rid))
        end else begin
          axi_seq_item item = rd_addr_q[match];
          int unsigned beat = item.resp.size();
          int unsigned bytes_per_beat = item.get_bytes_per_beat();
          int unsigned bus_bytes = cfg.data_width / 8;
          bit [7:0] next_data[] =
            new[item.rdata.size() + bytes_per_beat](item.rdata);
          axi_resp_e next_resp[] =
            new[item.resp.size() + 1](item.resp);
          int unsigned received_beats;
          int unsigned expected_beats;

          if (beat == 0)
            item.data_start_time = $time;
          for (int i = 0; i < bytes_per_beat; i++) begin
            int unsigned data_index = item.beat_data_index(beat, i);
            if (item.beat_byte_valid(beat, i, bus_bytes)) begin
              int unsigned lane = item.beat_byte_lane(beat, i, bus_bytes);
              next_data[data_index] = vif.rdata[lane*8 +: 8];
            end
          end
          next_resp[item.resp.size()] = axi_resp_e'(vif.rresp);
          item.rdata = next_data;
          item.resp  = next_resp;

          received_beats = item.resp.size();
          expected_beats = item.burst_len + 1;
          if (vif.rlast) begin
            if (received_beats < expected_beats)
              `uvm_error("MON_RLAST", $sformatf(
                "early RLAST for RID 0x%0h after %0d of %0d beats",
                vif.rid, received_beats, expected_beats))
            else if (received_beats > expected_beats &&
                     !item.rlast_missing_reported)
              `uvm_error("MON_RLAST", $sformatf(
                "late RLAST for RID 0x%0h after %0d beats; expected %0d",
                vif.rid, received_beats, expected_beats))
            rd_addr_q.delete(match);
            cur_outstanding_rd--;
            item.data_end_time = $time;
            item.resp_time     = $time;
            item_collected_port.write(item);
            `uvm_info("MON", $sformatf("R: %s beats=%0d lat=%0t",
              item.convert2string(), item.resp.size(),
              item.resp_time - item.addr_phase_time), UVM_HIGH)
          end else if (received_beats == expected_beats &&
                       !item.rlast_missing_reported) begin
            `uvm_error("MON_RLAST", $sformatf(
              "missing RLAST for RID 0x%0h at expected beat %0d",
              vif.rid, expected_beats - 1))
            item.rlast_missing_reported = 1;
          end
        end
      end
    end
  endtask

endclass

`endif // AXI_MASTER_MONITOR_SV
