// seq_lib/axi_b2b_seq.sv
`ifndef AXI_B2B_SEQ_SV
`define AXI_B2B_SEQ_SV

// Back-to-back write+read pairs sequence.
// Issues N consecutive write+read pairs to different addresses with no idle
// cycles between them, stressing the address channel pipeline.
class axi_b2b_seq extends axi_base_seq;

  `uvm_object_utils(axi_b2b_seq)

  // Knobs
  rand int unsigned  num_pairs;    // how many write+read pairs to issue
  rand bit [63:0]    base_addr;    // starting address (increments per pair)
  rand bit [2:0]     burst_size;   // log2(bytes_per_beat)
  rand bit [15:0]    id;

  constraint num_pairs_c {
    num_pairs inside {[2:16]};
  }

  constraint burst_size_range_c {
    burst_size inside {[0:3]};
  }

  // Keep base address aligned and far enough from end of address space
  constraint base_addr_c {
    (base_addr % (1 << burst_size)) == 0;
    base_addr < 64'hFFFF_FF00;
  }

  function new(string name = "axi_b2b_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item rd_rsp;
    bit [7:0]    wr_data[];
    bit [63:0]   addr;
    int unsigned num_bytes;
    int unsigned step;

    num_bytes = 1 << burst_size;
    step      = num_bytes;
    wr_data   = new [num_bytes];

    `uvm_info("AXI_B2B_SEQ",
      $sformatf("Starting %0d back-to-back write+read pairs base=0x%0h size=%0d",
        num_pairs, base_addr, burst_size),
      UVM_MEDIUM)

    for (int i = 0; i < int'(num_pairs); i++) begin
      addr = base_addr + i * step;

      // Fill write data with pair index XOR beat index pattern
      foreach (wr_data[j])
        wr_data[j] = (i[7:0] ^ j[7:0]);

      `uvm_info("AXI_B2B_SEQ",
        $sformatf("Pair[%0d] WRITE addr=0x%0h id=0x%0h", i, addr, id),
        UVM_HIGH)

      do_write(
        .addr       (addr),
        .data       (wr_data),
        .burst_len  (8'h00),
        .burst_size (burst_size),
        .burst_type (AXI_INCR),
        .id         (id)
      );

      `uvm_info("AXI_B2B_SEQ",
        $sformatf("Pair[%0d] READ  addr=0x%0h id=0x%0h", i, addr, id),
        UVM_HIGH)

      do_read(
        .addr       (addr),
        .burst_len  (8'h00),
        .burst_size (burst_size),
        .burst_type (AXI_INCR),
        .id         (id),
        .rsp        (rd_rsp)
      );
    end

    `uvm_info("AXI_B2B_SEQ",
      $sformatf("Completed %0d back-to-back pairs", num_pairs),
      UVM_MEDIUM)
  endtask

endclass

`endif // AXI_B2B_SEQ_SV
