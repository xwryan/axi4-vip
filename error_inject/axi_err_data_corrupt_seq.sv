// error_inject/axi_err_data_corrupt_seq.sv
`ifndef AXI_ERR_DATA_CORRUPT_SEQ_SV
`define AXI_ERR_DATA_CORRUPT_SEQ_SV

// Data corruption injection sequence.
// Sends read transactions with ERR_DATA_CORRUPT set so that the slave
// driver XORs the lowest byte of the nominated beat with 0xFF, producing
// a corrupted payload that exercises the DUT's data-integrity checks
// (e.g. ECC, parity, CRC).
class axi_err_data_corrupt_seq extends axi_base_seq;

  `uvm_object_utils(axi_err_data_corrupt_seq)

  // Knobs
  rand bit [63:0]   addr;
  rand bit [7:0]    burst_len;
  rand bit [2:0]    burst_size;
  rand bit [15:0]   id;
  rand int unsigned err_beat;            // beat index on which to corrupt data
  int unsigned      num_iterations = 4;

  constraint burst_len_c  { burst_len  inside {[0:15]};  }
  constraint burst_size_c { burst_size inside {[0:3]};   }
  constraint addr_align_c { (addr % (1 << burst_size)) == 0; }
  constraint addr_4kb_c   {
    (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) <= 4096;
  }
  constraint err_beat_c   { err_beat <= burst_len; }

  function new(string name = "axi_err_data_corrupt_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_err_seq_item item;
    axi_seq_item     rd_rsp;
    bit [7:0]        wr_data[];
    int unsigned     num_bytes;

    if (cfg != null) begin
      cfg.resolve_agent_configs();
      cfg.slave_cfg.enable_err_inject = 1;
    end

    repeat (num_iterations) begin
      num_bytes = (burst_len + 1) * (1 << burst_size);
      wr_data   = new [num_bytes];
      foreach (wr_data[i]) wr_data[i] = $urandom_range(0, 255);

      // --- Write clean data first so memory has known content ---
      item = axi_err_seq_item::type_id::create("data_corrupt_wr");
      start_item(item);
      if (!item.randomize() with {
            txn_type        == AXI_WRITE;
            item.addr       == local::addr;
            item.id         == local::id;
            item.burst_len  == local::burst_len;
            item.burst_size == local::burst_size;
            item.burst_type == AXI_INCR;
            item.lock       == 1'b0;
            item.inject_err == 1'b0;
            item.err_type   == ERR_NONE;
          }) begin
        `uvm_fatal("AXI_ERR_DATA_CORRUPT_SEQ", "randomize failed on write item")
      end
      item.data = wr_data;
      item.cfg  = cfg;
      `uvm_info("AXI_ERR_DATA_CORRUPT_SEQ",
        $sformatf("Clean WRITE addr=0x%0h len=%0d size=%0d",
          addr, burst_len, burst_size),
        UVM_MEDIUM)
      finish_item(item);

      // --- Read back with data corruption on nominated beat ---
      item = axi_err_seq_item::type_id::create("data_corrupt_rd");
      start_item(item);
      if (!item.randomize() with {
            txn_type        == AXI_READ;
            item.addr       == local::addr;
            item.id         == local::id;
            item.burst_len  == local::burst_len;
            item.burst_size == local::burst_size;
            item.burst_type == AXI_INCR;
            item.lock       == 1'b0;
            item.inject_err == 1'b1;
            item.err_type   == ERR_DATA_CORRUPT;
            item.err_beat   == local::err_beat;
          }) begin
        `uvm_fatal("AXI_ERR_DATA_CORRUPT_SEQ", "randomize failed on read item")
      end
      item.cfg = cfg;
      `uvm_info("AXI_ERR_DATA_CORRUPT_SEQ",
        $sformatf("Injecting DATA_CORRUPT: %s", item.convert2string()),
        UVM_MEDIUM)
      finish_item(item);
      rd_rsp = item;

      `uvm_info("AXI_ERR_DATA_CORRUPT_SEQ",
        $sformatf("DATA_CORRUPT read complete resp=%s rdata_bytes=%0d",
          (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A",
          rd_rsp.rdata.size()),
        UVM_MEDIUM)
    end
  endtask

endclass

`endif // AXI_ERR_DATA_CORRUPT_SEQ_SV
