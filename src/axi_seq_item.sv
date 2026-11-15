`ifndef AXI_SEQ_ITEM_SV
`define AXI_SEQ_ITEM_SV

class axi_seq_item extends uvm_sequence_item;

  `uvm_object_utils(axi_seq_item)

  // Address channel fields
  rand bit [63:0]          addr;
  rand bit [15:0]          id;
  rand axi_txn_type_e      txn_type;
  rand bit [7:0]           burst_len;
  rand axi_burst_type_e    burst_type;
  rand bit [2:0]           burst_size;
  rand bit                 lock;
  rand bit [3:0]           cache;
  rand bit [2:0]           prot;
  rand bit [3:0]           qos;
  rand bit [3:0]           region;

  // Data fields
  rand bit [7:0]           data[];
  rand bit [63:0]          wstrb[];

  // Response fields (filled by Monitor/Slave)
  axi_resp_e               resp[];
  bit [7:0]                rdata[];
  bit                      aborted;
  bit                      rlast_missing_reported;

  // Timestamps (filled by Monitor)
  time                     addr_phase_time;
  time                     data_start_time;
  time                     data_end_time;
  time                     resp_time;
  int unsigned             outstanding_at_issue;

  // Error injection knobs
  rand bit                 inject_err;
  rand axi_err_type_e      err_type;
  rand int unsigned         err_beat;

  // Configuration reference (set by sequence)
  axi_config               cfg;

  // Constraints

  constraint default_no_err_c {
    inject_err == 0;
    inject_err -> err_type != ERR_NONE;
    !inject_err -> err_type == ERR_NONE;
  }

  constraint burst_size_max_c {
    if (cfg != null)
      burst_size <= $clog2(cfg.data_width / 8);
    else
      burst_size <= 3;
  }

  constraint wrap_len_c {
    if (burst_type == AXI_WRAP)
      burst_len inside {1, 3, 7, 15};
  }

  constraint fixed_len_c {
    if (burst_type == AXI_FIXED)
      burst_len inside {[0:15]};
  }

  constraint axi4_len_c {
    burst_len inside {[0:255]};
  }

  constraint addr_4kb_c {
    if (burst_type == AXI_INCR)
      (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) <= 4096;
  }

  constraint wrap_align_c {
    if (burst_type == AXI_WRAP)
      (addr % (1 << burst_size)) == 0;
  }

  constraint exclusive_c {
    if (lock == 1) {
      burst_len inside {0, 1, 3, 7, 15};
      (burst_len + 1) * (1 << burst_size) <= 128;
    }
  }

  constraint data_size_c {
    data.size() == (burst_len + 1) * (1 << burst_size);
  }

  constraint wstrb_size_c {
    if (txn_type == AXI_WRITE)
      wstrb.size() == burst_len + 1;
    else
      wstrb.size() == 0;
  }

  constraint err_beat_c {
    if (inject_err)
      err_beat <= burst_len;
  }

  constraint lite_mode_c {
    if (cfg != null && cfg.mode == AXI4_LITE) {
      burst_len  == 0;
      burst_type == AXI_INCR;
      burst_size == $clog2(cfg.data_width / 8);
      lock       == 0;
    }
  }

  function new(string name = "axi_seq_item");
    super.new(name);
    aborted                = 0;
    rlast_missing_reported = 0;
    outstanding_at_issue   = 0;
  endfunction

  // Helper methods

  function int unsigned get_total_bytes();
    return (burst_len + 1) * (1 << burst_size);
  endfunction

  function int unsigned get_bytes_per_beat();
    return (1 << burst_size);
  endfunction

  function int unsigned get_latency();
    if (resp_time > addr_phase_time)
      return resp_time - addr_phase_time;
    else
      return 0;
  endfunction

  function bit [63:0] calc_beat_addr(int beat);
    int unsigned bytes_per_beat = 1 << burst_size;
    bit [63:0] aligned_addr = (addr / bytes_per_beat) * bytes_per_beat;
    case (burst_type)
      AXI_FIXED: return addr;
      AXI_INCR: begin
        if (beat == 0) return addr;
        else return aligned_addr + beat * bytes_per_beat;
      end
      AXI_WRAP: begin
        int unsigned wrap_boundary = (burst_len + 1) * bytes_per_beat;
        bit [63:0] lower_wrap = (addr / wrap_boundary) * wrap_boundary;
        bit [63:0] upper_wrap = lower_wrap + wrap_boundary;
        bit [63:0] beat_addr;
        if (beat == 0) beat_addr = addr;
        else beat_addr = aligned_addr + beat * bytes_per_beat;
        if (beat_addr >= upper_wrap)
          beat_addr = lower_wrap + (beat_addr - upper_wrap);
        return beat_addr;
      end
      default: return addr;
    endcase
  endfunction

  function bit beat_byte_valid(
    int beat,
    int byte_index,
    int unsigned bus_bytes
  );
    int unsigned bytes_per_beat;
    int unsigned lower_lane;

    if (bus_bytes == 0 || bus_bytes > 64) begin
      `uvm_error("AXI_SEQ_ITEM", $sformatf(
        "beat_byte_valid called with unsupported bus_bytes=%0d", bus_bytes))
      return 0;
    end
    bytes_per_beat = get_bytes_per_beat();
    lower_lane = calc_beat_addr(beat) % bus_bytes;
    return byte_index < bytes_per_beat &&
           lower_lane + byte_index < bus_bytes;
  endfunction

  function int unsigned beat_byte_lane(
    int beat,
    int byte_index,
    int unsigned bus_bytes
  );
    if (bus_bytes == 0 || bus_bytes > 64) begin
      `uvm_error("AXI_SEQ_ITEM", $sformatf(
        "beat_byte_lane called with unsupported bus_bytes=%0d", bus_bytes))
      return 0;
    end
    return (calc_beat_addr(beat) % bus_bytes) + byte_index;
  endfunction

  function int unsigned beat_data_index(int beat, int byte_index);
    return beat * get_bytes_per_beat() + byte_index;
  endfunction

  function void unpack_w_burst(
    axi_w_burst_record raw,
    int unsigned bus_bytes
  );
    int unsigned bytes_per_beat;

    if (raw == null) begin
      `uvm_error("AXI_SEQ_ITEM", "unpack_w_burst received a null record")
      data = new[0];
      wstrb = new[0];
      return;
    end
    bytes_per_beat = get_bytes_per_beat();
    data = new[raw.size() * bytes_per_beat];
    wstrb = new[raw.size()];
    if (bus_bytes == 0 || bus_bytes > 64) begin
      `uvm_error("AXI_SEQ_ITEM", $sformatf(
        "unpack_w_burst received unsupported bus_bytes=%0d", bus_bytes))
      return;
    end

    for (int beat = 0; beat < raw.size(); beat++) begin
      for (int i = 0; i < bytes_per_beat; i++) begin
        int unsigned data_index;
        int unsigned lane;

        data_index = beat_data_index(beat, i);
        if (beat_byte_valid(beat, i, bus_bytes)) begin
          lane = beat_byte_lane(beat, i, bus_bytes);
          data[data_index] = raw.data_q[beat][lane*8 +: 8];
          wstrb[beat][i] = raw.strb_q[beat][lane];
        end
      end
    end
  endfunction

  function bit [511:0] pack_beat_data(int beat, int unsigned bus_bytes);
    bit [511:0] packed_data = '0;
    int unsigned bytes_per_beat = get_bytes_per_beat();

    if (bus_bytes == 0 || bus_bytes > 64) begin
      `uvm_error("AXI_SEQ_ITEM", $sformatf(
        "pack_beat_data received unsupported bus_bytes=%0d", bus_bytes))
      return packed_data;
    end
    for (int i = 0; i < bytes_per_beat; i++) begin
      int unsigned data_index = beat_data_index(beat, i);

      if (beat_byte_valid(beat, i, bus_bytes) &&
          data_index < data.size()) begin
        int unsigned lane = beat_byte_lane(beat, i, bus_bytes);
        packed_data[lane*8 +: 8] = data[data_index];
      end
    end
    return packed_data;
  endfunction

  function bit [63:0] pack_beat_wstrb(int beat, int unsigned bus_bytes);
    bit [63:0] packed_strb = '0;
    int unsigned bytes_per_beat = get_bytes_per_beat();

    if (bus_bytes == 0 || bus_bytes > 64) begin
      `uvm_error("AXI_SEQ_ITEM", $sformatf(
        "pack_beat_wstrb received unsupported bus_bytes=%0d", bus_bytes))
      return packed_strb;
    end
    for (int i = 0; i < bytes_per_beat; i++) begin
      if (beat_byte_valid(beat, i, bus_bytes)) begin
        int unsigned lane = beat_byte_lane(beat, i, bus_bytes);
        if (beat < wstrb.size())
          packed_strb[lane] = wstrb[beat][i];
        else
          packed_strb[lane] = 1'b1;
      end
    end
    return packed_strb;
  endfunction

  function string convert2string();
    return $sformatf("%s id=0x%0h addr=0x%0h len=%0d size=%0d burst=%s lock=%0b total=%0dB",
      txn_type.name(), id, addr, burst_len, burst_size, burst_type.name(),
      lock, get_total_bytes());
  endfunction

  function void do_copy(uvm_object rhs);
    axi_seq_item rhs_item;
    super.do_copy(rhs);
    if (!$cast(rhs_item, rhs)) return;
    this.addr             = rhs_item.addr;
    this.id               = rhs_item.id;
    this.txn_type         = rhs_item.txn_type;
    this.burst_len        = rhs_item.burst_len;
    this.burst_type       = rhs_item.burst_type;
    this.burst_size       = rhs_item.burst_size;
    this.lock             = rhs_item.lock;
    this.cache            = rhs_item.cache;
    this.prot             = rhs_item.prot;
    this.qos              = rhs_item.qos;
    this.region           = rhs_item.region;
    this.data             = rhs_item.data;
    this.wstrb            = rhs_item.wstrb;
    this.resp             = rhs_item.resp;
    this.rdata            = rhs_item.rdata;
    this.aborted          = rhs_item.aborted;
    this.rlast_missing_reported = rhs_item.rlast_missing_reported;
    this.addr_phase_time  = rhs_item.addr_phase_time;
    this.data_start_time  = rhs_item.data_start_time;
    this.data_end_time    = rhs_item.data_end_time;
    this.resp_time        = rhs_item.resp_time;
    this.outstanding_at_issue = rhs_item.outstanding_at_issue;
    this.inject_err       = rhs_item.inject_err;
    this.err_type         = rhs_item.err_type;
    this.err_beat         = rhs_item.err_beat;
    this.cfg              = rhs_item.cfg;
  endfunction

endclass

`endif // AXI_SEQ_ITEM_SV
