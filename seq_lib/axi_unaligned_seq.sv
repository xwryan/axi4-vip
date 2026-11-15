// seq_lib/axi_unaligned_seq.sv
`ifndef AXI_UNALIGNED_SEQ_SV
`define AXI_UNALIGNED_SEQ_SV

// Unaligned address transfer sequence.
// Issues INCR bursts whose start address is NOT naturally aligned to the
// beat size, exercising byte-lane offset handling in the driver.
class axi_unaligned_seq extends axi_base_seq;

  `uvm_object_utils(axi_unaligned_seq)

  // Knobs
  rand bit [63:0]  addr;
  rand bit [7:0]   burst_len;
  rand bit [2:0]   burst_size;
  rand bit [15:0]  id;

  constraint burst_len_c {
    burst_len inside {[0:7]};
  }

  constraint burst_size_range_c {
    burst_size inside {[1:3]};  // at least 2-byte beat so misalignment is meaningful
  }

  // Force address to be unaligned: lower bits non-zero
  constraint unaligned_addr_c {
    (addr % (1 << burst_size)) != 0;
    // Keep within a 4KB page with room for the full burst
    (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) + (1 << burst_size) <= 4096;
  }

  function new(string name = "axi_unaligned_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item rd_rsp;
    int unsigned  num_bytes;
    bit [7:0]     wr_data[];
    int unsigned  offset;

    offset    = addr % (1 << burst_size);
    num_bytes = (burst_len + 1) * (1 << burst_size);
    wr_data   = new [num_bytes];

    foreach (wr_data[i])
      wr_data[i] = $urandom_range(0, 255);

    `uvm_info("AXI_UNALIGNED_SEQ",
      $sformatf("UNALIGNED WRITE addr=0x%0h (offset=%0d) len=%0d size=%0d total=%0dB id=0x%0h",
        addr, offset, burst_len, burst_size, num_bytes, id),
      UVM_MEDIUM)

    do_write(
      .addr       (addr),
      .data       (wr_data),
      .burst_len  (burst_len),
      .burst_size (burst_size),
      .burst_type (AXI_INCR),
      .id         (id)
    );

    `uvm_info("AXI_UNALIGNED_SEQ",
      $sformatf("UNALIGNED READ  addr=0x%0h (offset=%0d) len=%0d size=%0d total=%0dB id=0x%0h",
        addr, offset, burst_len, burst_size, num_bytes, id),
      UVM_MEDIUM)

    do_read(
      .addr       (addr),
      .burst_len  (burst_len),
      .burst_size (burst_size),
      .burst_type (AXI_INCR),
      .id         (id),
      .rsp        (rd_rsp)
    );

    `uvm_info("AXI_UNALIGNED_SEQ",
      $sformatf("UNALIGNED READ  complete resp=%s rdata_bytes=%0d",
        (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A",
        rd_rsp.rdata.size()),
      UVM_MEDIUM)
  endtask

endclass

`endif // AXI_UNALIGNED_SEQ_SV
