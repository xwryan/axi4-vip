// seq_lib/axi_single_rw_seq.sv
`ifndef AXI_SINGLE_RW_SEQ_SV
`define AXI_SINGLE_RW_SEQ_SV

// Single read/write sequence.
// Issues one write followed by one read to the same address and
// checks that the read data matches what was written.
class axi_single_rw_seq extends axi_base_seq;

  `uvm_object_utils(axi_single_rw_seq)

  // Knobs -- may be set by the test before starting the sequence
  rand bit [63:0]  addr;
  rand bit [2:0]   burst_size;  // log2(bytes_per_beat)
  rand bit [15:0]  id;

  // Constraint: keep address naturally aligned to beat size
  constraint addr_align_c {
    (addr % (1 << burst_size)) == 0;
  }

  constraint burst_size_range_c {
    burst_size inside {[0:3]};
  }

  function new(string name = "axi_single_rw_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item rd_rsp;
    int unsigned  num_bytes;
    bit [7:0]     wr_data[];

    // Single-beat transfer: burst_len = 0
    num_bytes = 1 << burst_size;
    wr_data   = new [num_bytes];

    // Fill write data with a random pattern
    foreach (wr_data[i])
      wr_data[i] = $urandom_range(0, 255);

    `uvm_info("AXI_SINGLE_RW_SEQ",
      $sformatf("WRITE addr=0x%0h size=%0d bytes=%0d id=0x%0h",
        addr, burst_size, num_bytes, id),
      UVM_MEDIUM)

    do_write(
      .addr       (addr),
      .data       (wr_data),
      .burst_len  (8'h00),
      .burst_size (burst_size),
      .burst_type (AXI_INCR),
      .id         (id)
    );

    `uvm_info("AXI_SINGLE_RW_SEQ",
      $sformatf("READ  addr=0x%0h size=%0d bytes=%0d id=0x%0h",
        addr, burst_size, num_bytes, id),
      UVM_MEDIUM)

    do_read(
      .addr       (addr),
      .burst_len  (8'h00),
      .burst_size (burst_size),
      .burst_type (AXI_INCR),
      .id         (id),
      .rsp        (rd_rsp)
    );

    // Scoreboard handles full data checking; log a summary here
    `uvm_info("AXI_SINGLE_RW_SEQ",
      $sformatf("READ  complete resp=%s rdata_bytes=%0d",
        (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A",
        rd_rsp.rdata.size()),
      UVM_MEDIUM)
  endtask

endclass

`endif // AXI_SINGLE_RW_SEQ_SV
