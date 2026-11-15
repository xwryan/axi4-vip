// seq_lib/axi_exclusive_seq.sv
`ifndef AXI_EXCLUSIVE_SEQ_SV
`define AXI_EXCLUSIVE_SEQ_SV

// Exclusive access sequence.
// Issues an exclusive read (ARLOCK=1) followed by an exclusive write
// (AWLOCK=1) to the same address and checks for EXOKAY response.
// Models the AXI exclusive-access monitor protocol.
class axi_exclusive_seq extends axi_base_seq;

  `uvm_object_utils(axi_exclusive_seq)

  // Knobs
  rand bit [63:0]  addr;
  rand bit [2:0]   burst_size;
  rand bit [7:0]   burst_len;   // AXI exclusive: 1,3,7,15 beats
  rand bit [15:0]  id;

  // Exclusive transfers must have naturally aligned addresses
  constraint addr_align_c {
    (addr % (1 << burst_size)) == 0;
  }

  constraint burst_size_range_c {
    burst_size inside {[0:3]};
  }

  // AXI spec: exclusive burst lengths 1,2,4,8,16 beats (burst_len 0,1,3,7,15)
  constraint excl_len_c {
    burst_len inside {8'h00, 8'h01, 8'h03, 8'h07, 8'h0F};
  }

  // Total exclusive transfer <= 128 bytes
  constraint excl_size_c {
    (burst_len + 1) * (1 << burst_size) <= 128;
  }

  // 4KB boundary
  constraint addr_4kb_c {
    (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) <= 4096;
  }

  function new(string name = "axi_exclusive_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item item;
    axi_seq_item rd_rsp;
    int unsigned  num_bytes;
    bit [7:0]     wr_data[];

    num_bytes = (burst_len + 1) * (1 << burst_size);
    wr_data   = new [num_bytes];

    foreach (wr_data[i])
      wr_data[i] = $urandom_range(0, 255);

    // --- Exclusive Read ---
    `uvm_info("AXI_EXCLUSIVE_SEQ",
      $sformatf("EXCL READ  addr=0x%0h len=%0d size=%0d total=%0dB id=0x%0h",
        addr, burst_len, burst_size, num_bytes, id),
      UVM_MEDIUM)

    item = axi_seq_item::type_id::create("excl_rd");
    start_item(item);
    if (!item.randomize() with {
          txn_type        == AXI_READ;
          item.addr       == local::addr;
          item.id         == local::id;
          item.burst_len  == local::burst_len;
          item.burst_size == local::burst_size;
          item.burst_type == AXI_INCR;
          item.lock       == 1'b1;
          item.inject_err == 1'b0;
        }) begin
      `uvm_fatal("AXI_EXCLUSIVE_SEQ", "exclusive read randomize failed")
    end
    item.cfg = cfg;
    finish_item(item);
    rd_rsp = item;

    `uvm_info("AXI_EXCLUSIVE_SEQ",
      $sformatf("EXCL READ  complete resp=%s",
        (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A"),
      UVM_MEDIUM)

    // --- Exclusive Write ---
    `uvm_info("AXI_EXCLUSIVE_SEQ",
      $sformatf("EXCL WRITE addr=0x%0h len=%0d size=%0d total=%0dB id=0x%0h",
        addr, burst_len, burst_size, num_bytes, id),
      UVM_MEDIUM)

    item = axi_seq_item::type_id::create("excl_wr");
    start_item(item);
    if (!item.randomize() with {
          txn_type        == AXI_WRITE;
          item.addr       == local::addr;
          item.id         == local::id;
          item.burst_len  == local::burst_len;
          item.burst_size == local::burst_size;
          item.burst_type == AXI_INCR;
          item.lock       == 1'b1;
          item.inject_err == 1'b0;
        }) begin
      `uvm_fatal("AXI_EXCLUSIVE_SEQ", "exclusive write randomize failed")
    end
    item.data = wr_data;
    item.cfg  = cfg;
    finish_item(item);

    `uvm_info("AXI_EXCLUSIVE_SEQ",
      $sformatf("EXCL WRITE complete resp=%s",
        (item.resp.size() > 0) ? item.resp[0].name() : "N/A"),
      UVM_MEDIUM)

    if (item.resp.size() > 0 && item.resp[0] != AXI_EXOKAY) begin
      `uvm_warning("AXI_EXCLUSIVE_SEQ",
        $sformatf("Exclusive write did not receive EXOKAY (got %s) -- monitor may have seen intervening access",
          item.resp[0].name()))
    end
  endtask

endclass

`endif // AXI_EXCLUSIVE_SEQ_SV
