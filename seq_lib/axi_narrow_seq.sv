// seq_lib/axi_narrow_seq.sv
`ifndef AXI_NARROW_SEQ_SV
`define AXI_NARROW_SEQ_SV

// Narrow transfer sequence.
// Issues bursts where burst_size < bus width, exercising byte-lane steering
// logic in the driver and scoreboard.  Each beat uses only a subset of the
// available data bus lanes.
class axi_narrow_seq extends axi_base_seq;

  `uvm_object_utils(axi_narrow_seq)

  // Knobs
  rand bit [63:0]  addr;
  rand bit [7:0]   burst_len;   // number of beats - 1
  rand bit [2:0]   burst_size;  // must be < bus_size (enforced by constraint)
  rand bit [15:0]  id;

  // bus_size: log2(data_width_bytes).  Default = 3 (8-byte / 64-bit bus).
  // Override before randomize if the DUT uses a wider bus.
  int unsigned     bus_size = 3;

  constraint burst_len_c {
    burst_len inside {[1:15]};
  }

  // Narrow: beat size strictly less than bus width
  constraint narrow_size_c {
    burst_size < bus_size;
    burst_size inside {[0:2]};
  }

  // Natural address alignment to beat size
  constraint addr_align_c {
    (addr % (1 << burst_size)) == 0;
  }

  // 4KB boundary
  constraint addr_4kb_c {
    (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) <= 4096;
  }

  function new(string name = "axi_narrow_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item rd_rsp;
    int unsigned  num_bytes;
    bit [7:0]     wr_data[];

    num_bytes = (burst_len + 1) * (1 << burst_size);
    wr_data   = new [num_bytes];

    foreach (wr_data[i])
      wr_data[i] = $urandom_range(0, 255);

    `uvm_info("AXI_NARROW_SEQ",
      $sformatf("NARROW WRITE addr=0x%0h len=%0d size=%0d (bus_size=%0d) total=%0dB id=0x%0h",
        addr, burst_len, burst_size, bus_size, num_bytes, id),
      UVM_MEDIUM)

    do_write(
      .addr       (addr),
      .data       (wr_data),
      .burst_len  (burst_len),
      .burst_size (burst_size),
      .burst_type (AXI_INCR),
      .id         (id)
    );

    `uvm_info("AXI_NARROW_SEQ",
      $sformatf("NARROW READ  addr=0x%0h len=%0d size=%0d total=%0dB id=0x%0h",
        addr, burst_len, burst_size, num_bytes, id),
      UVM_MEDIUM)

    do_read(
      .addr       (addr),
      .burst_len  (burst_len),
      .burst_size (burst_size),
      .burst_type (AXI_INCR),
      .id         (id),
      .rsp        (rd_rsp)
    );

    `uvm_info("AXI_NARROW_SEQ",
      $sformatf("NARROW READ  complete resp=%s rdata_bytes=%0d",
        (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A",
        rd_rsp.rdata.size()),
      UVM_MEDIUM)
  endtask

endclass

`endif // AXI_NARROW_SEQ_SV
