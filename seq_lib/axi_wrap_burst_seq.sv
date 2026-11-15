// seq_lib/axi_wrap_burst_seq.sv
`ifndef AXI_WRAP_BURST_SEQ_SV
`define AXI_WRAP_BURST_SEQ_SV

// WRAP burst sequence.
// Issues AXI_WRAP burst writes and reads, exercising the wrapping address
// calculation in the driver and scoreboard reference model.
// AXI spec requires: burst_len in {1,3,7,15}, aligned start address.
class axi_wrap_burst_seq extends axi_base_seq;

  `uvm_object_utils(axi_wrap_burst_seq)

  // Knobs
  rand bit [63:0]  addr;
  rand bit [7:0]   burst_len;   // must be 1, 3, 7, or 15
  rand bit [2:0]   burst_size;
  rand bit [15:0]  id;

  // AXI WRAP requires burst_len in {1, 3, 7, 15}
  constraint wrap_len_c {
    burst_len inside {8'h01, 8'h03, 8'h07, 8'h0F};
  }

  constraint burst_size_range_c {
    burst_size inside {[0:3]};
  }

  // WRAP requires naturally aligned start address
  constraint wrap_align_c {
    (addr % (1 << burst_size)) == 0;
  }

  function new(string name = "axi_wrap_burst_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item rd_rsp;
    int unsigned  num_bytes;
    int unsigned  wrap_boundary;
    bit [7:0]     wr_data[];

    num_bytes     = (burst_len + 1) * (1 << burst_size);
    wrap_boundary = num_bytes;
    wr_data       = new [num_bytes];

    // Fill with a walking-ones pattern to make wrap behaviour visible
    foreach (wr_data[i])
      wr_data[i] = 8'h01 << (i % 8);

    `uvm_info("AXI_WRAP_BURST_SEQ",
      $sformatf("WRAP WRITE addr=0x%0h len=%0d size=%0d boundary=%0dB total=%0dB id=0x%0h",
        addr, burst_len, burst_size, wrap_boundary, num_bytes, id),
      UVM_MEDIUM)

    do_write(
      .addr       (addr),
      .data       (wr_data),
      .burst_len  (burst_len),
      .burst_size (burst_size),
      .burst_type (AXI_WRAP),
      .id         (id)
    );

    `uvm_info("AXI_WRAP_BURST_SEQ",
      $sformatf("WRAP READ  addr=0x%0h len=%0d size=%0d boundary=%0dB total=%0dB id=0x%0h",
        addr, burst_len, burst_size, wrap_boundary, num_bytes, id),
      UVM_MEDIUM)

    do_read(
      .addr       (addr),
      .burst_len  (burst_len),
      .burst_size (burst_size),
      .burst_type (AXI_WRAP),
      .id         (id),
      .rsp        (rd_rsp)
    );

    `uvm_info("AXI_WRAP_BURST_SEQ",
      $sformatf("WRAP READ  complete resp=%s rdata_bytes=%0d",
        (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A",
        rd_rsp.rdata.size()),
      UVM_MEDIUM)
  endtask

endclass

`endif // AXI_WRAP_BURST_SEQ_SV
