// seq_lib/axi_burst_seq.sv
`ifndef AXI_BURST_SEQ_SV
`define AXI_BURST_SEQ_SV

// Burst read/write sequence.
// Issues a multi-beat INCR burst write followed by an INCR burst read
// to the same address.  The number of beats (burst_len+1) and beat
// width (burst_size) are randomisable knobs.
class axi_burst_seq extends axi_base_seq;

  `uvm_object_utils(axi_burst_seq)

  // Knobs -- may be set by the test before starting the sequence
  rand bit [63:0]  addr;
  rand bit [7:0]   burst_len;   // number of beats - 1 (0 = single beat)
  rand bit [2:0]   burst_size;  // log2(bytes_per_beat)
  rand bit [15:0]  id;

  // Default to a modest burst so constraints are easy to satisfy
  constraint burst_len_default_c {
    burst_len inside {[1:15]};
  }

  constraint burst_size_range_c {
    burst_size inside {[0:3]};
  }

  // Keep address naturally aligned to beat size
  constraint addr_align_c {
    (addr % (1 << burst_size)) == 0;
  }

  // AXI 4KB boundary: the burst must not cross a 4 KB page
  constraint addr_4kb_c {
    (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) <= 4096;
  }

  function new(string name = "axi_burst_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item rd_rsp;
    int unsigned  num_bytes;
    bit [7:0]     wr_data[];

    num_bytes = (burst_len + 1) * (1 << burst_size);
    wr_data   = new [num_bytes];

    // Fill write data with an incrementing pattern
    foreach (wr_data[i])
      wr_data[i] = i[7:0];

    `uvm_info("AXI_BURST_SEQ",
      $sformatf("BURST WRITE addr=0x%0h len=%0d size=%0d total=%0dB id=0x%0h",
        addr, burst_len, burst_size, num_bytes, id),
      UVM_MEDIUM)

    do_write(
      .addr       (addr),
      .data       (wr_data),
      .burst_len  (burst_len),
      .burst_size (burst_size),
      .burst_type (AXI_INCR),
      .id         (id)
    );

    `uvm_info("AXI_BURST_SEQ",
      $sformatf("BURST READ  addr=0x%0h len=%0d size=%0d total=%0dB id=0x%0h",
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

    // Scoreboard handles full data checking; log a summary here
    `uvm_info("AXI_BURST_SEQ",
      $sformatf("BURST READ  complete resp=%s rdata_bytes=%0d",
        (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A",
        rd_rsp.rdata.size()),
      UVM_MEDIUM)
  endtask

endclass

`endif // AXI_BURST_SEQ_SV
