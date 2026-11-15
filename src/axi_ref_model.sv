`ifndef AXI_REF_MODEL_SV
`define AXI_REF_MODEL_SV

class axi_ref_model extends uvm_object;

  `uvm_object_utils(axi_ref_model)

  protected bit [7:0] mem[bit [63:0]];
  bit [7:0] default_val = 8'h00;

  protected bit [63:0] excl_addr[int];
  protected bit        excl_valid[int];

  function new(string name = "axi_ref_model");
    super.new(name);
  endfunction

  virtual function void write(
    bit [63:0]     addr,
    bit [7:0]      data[],
    bit            strb[],
    int unsigned   num_bytes
  );
    for (int i = 0; i < num_bytes; i++) begin
      if (i < strb.size() && strb[i])
        mem[addr + i] = (i < data.size()) ? data[i] : 8'h00;
      else if (strb.size() == 0)
        mem[addr + i] = (i < data.size()) ? data[i] : 8'h00;
    end
    foreach (excl_addr[eid]) begin
      if (excl_valid[eid] &&
          excl_addr[eid] >= addr &&
          excl_addr[eid] < (addr + num_bytes))
        excl_valid[eid] = 0;
    end
  endfunction

  virtual function void read(
    bit [63:0]          addr,
    int unsigned        num_bytes,
    output bit [7:0]    data[]
  );
    data = new[num_bytes];
    for (int i = 0; i < num_bytes; i++) begin
      if (mem.exists(addr + i))
        data[i] = mem[addr + i];
      else
        data[i] = default_val;
    end
  endfunction

  virtual function void burst_write(axi_seq_item item);
    int unsigned bus_bytes;
    int unsigned bytes_per_beat;

    if (item == null) begin
      `uvm_error("AXI_REF_MODEL", "burst_write received a null item")
      return;
    end
    if (item.cfg == null || item.cfg.data_width == 0 ||
        (item.cfg.data_width % 8) != 0) begin
      `uvm_error("AXI_REF_MODEL",
        "burst_write requires a valid item.cfg data width")
      return;
    end
    bus_bytes = item.cfg.data_width / 8;
    if (bus_bytes == 0 || bus_bytes > 64) begin
      `uvm_error("AXI_REF_MODEL", $sformatf(
        "burst_write received unsupported bus_bytes=%0d", bus_bytes))
      return;
    end

    bytes_per_beat = item.get_bytes_per_beat();
    for (int beat = 0; beat <= item.burst_len; beat++) begin
      bit [63:0] beat_addr = item.calc_beat_addr(beat);
      bit [7:0] beat_data[];
      bit beat_strb[];

      beat_data = new[bytes_per_beat];
      beat_strb = new[bytes_per_beat];

      for (int i = 0; i < bytes_per_beat; i++) begin
        int unsigned data_index = item.beat_data_index(beat, i);

        if (item.beat_byte_valid(beat, i, bus_bytes)) begin
          beat_data[i] = (data_index < item.data.size()) ?
                         item.data[data_index] : 8'h00;
          if (beat < item.wstrb.size())
            beat_strb[i] = item.wstrb[beat][i];
        end
      end
      // Keep the legacy whole-beat exclusive-monitor invalidation range,
      // while beat_strb prevents holes and unstrobed bytes from updating mem.
      write(beat_addr, beat_data, beat_strb, bytes_per_beat);
    end
  endfunction

  virtual function void burst_read(
    axi_seq_item       item,
    output bit [7:0]   data[]
  );
    int unsigned total_bytes;
    int unsigned bytes_per_beat;
    int unsigned bus_bytes;

    if (item == null) begin
      `uvm_error("AXI_REF_MODEL", "burst_read received a null item")
      data = new[0];
      return;
    end
    total_bytes = item.get_total_bytes();
    bytes_per_beat = item.get_bytes_per_beat();
    data = new[total_bytes];
    if (item.cfg == null || item.cfg.data_width == 0 ||
        (item.cfg.data_width % 8) != 0) begin
      `uvm_error("AXI_REF_MODEL",
        "burst_read requires a valid item.cfg data width")
      return;
    end
    bus_bytes = item.cfg.data_width / 8;
    if (bus_bytes == 0 || bus_bytes > 64) begin
      `uvm_error("AXI_REF_MODEL", $sformatf(
        "burst_read received unsupported bus_bytes=%0d", bus_bytes))
      return;
    end

    for (int beat = 0; beat <= item.burst_len; beat++) begin
      bit [63:0]   beat_addr = item.calc_beat_addr(beat);

      for (int i = 0; i < bytes_per_beat; i++) begin
        int unsigned data_index = item.beat_data_index(beat, i);

        if (item.beat_byte_valid(beat, i, bus_bytes) &&
            data_index < total_bytes) begin
          if (mem.exists(beat_addr + i))
            data[data_index] = mem[beat_addr + i];
          else
            data[data_index] = default_val;
        end
      end
    end
  endfunction

  virtual function bit exclusive_read(int id, bit [63:0] addr);
    excl_addr[id]  = addr;
    excl_valid[id] = 1;
    return 1;
  endfunction

  virtual function axi_resp_e exclusive_write(int id, bit [63:0] addr);
    if (excl_valid.exists(id) && excl_valid[id] && excl_addr[id] == addr) begin
      excl_valid[id] = 0;
      return AXI_EXOKAY;
    end
    return AXI_OKAY;
  endfunction

  virtual function void reset();
    mem.delete();
    excl_addr.delete();
    excl_valid.delete();
  endfunction

  function int unsigned get_mem_size();
    return mem.size();
  endfunction

  function void backdoor_write(bit [63:0] addr, bit [7:0] data);
    mem[addr] = data;
  endfunction

  function bit [7:0] backdoor_read(bit [63:0] addr);
    if (mem.exists(addr)) return mem[addr];
    else return default_val;
  endfunction

endclass

`endif // AXI_REF_MODEL_SV
