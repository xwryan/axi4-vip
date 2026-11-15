// error_inject/axi_err_timeout_seq.sv
`ifndef AXI_ERR_TIMEOUT_SEQ_SV
`define AXI_ERR_TIMEOUT_SEQ_SV

// Handshake timeout injection sequence.
// Sends transactions with ERR_TIMEOUT set so that the slave driver
// stalls the READY signal for 1000 clock cycles on the nominated beat,
// exercising the DUT's timeout-detection and recovery logic.
class axi_err_timeout_seq extends axi_base_seq;

  `uvm_object_utils(axi_err_timeout_seq)

  // Knobs
  rand bit [63:0]   addr;
  rand bit [7:0]    burst_len;
  rand bit [2:0]    burst_size;
  rand bit [15:0]   id;
  rand int unsigned err_beat;            // beat index on which to inject timeout
  int unsigned      num_iterations = 2;  // timeouts are slow; keep count small

  constraint burst_len_c  { burst_len  inside {[0:7]};  }
  constraint burst_size_c { burst_size inside {[0:3]};  }
  constraint addr_align_c { (addr % (1 << burst_size)) == 0; }
  constraint addr_4kb_c   {
    (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) <= 4096;
  }
  constraint err_beat_c   { err_beat <= burst_len; }

  function new(string name = "axi_err_timeout_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_err_seq_item item;
    axi_seq_item     rd_rsp;

    if (cfg != null) begin
      cfg.resolve_agent_configs();
      cfg.slave_cfg.enable_err_inject = 1;
    end

    repeat (num_iterations) begin
      // --- Write with timeout on nominated beat ---
      item = axi_err_seq_item::type_id::create("err_timeout_wr");
      start_item(item);
      if (!item.randomize() with {
            txn_type        == AXI_WRITE;
            item.addr       == local::addr;
            item.id         == local::id;
            item.burst_len  == local::burst_len;
            item.burst_size == local::burst_size;
            item.burst_type == AXI_INCR;
            item.lock       == 1'b0;
            item.inject_err == 1'b1;
            item.err_type   == ERR_TIMEOUT;
            item.err_beat   == local::err_beat;
          }) begin
        `uvm_fatal("AXI_ERR_TIMEOUT_SEQ", "randomize failed on write item")
      end
      item.cfg = cfg;
      `uvm_info("AXI_ERR_TIMEOUT_SEQ",
        $sformatf("Injecting TIMEOUT: %s", item.convert2string()),
        UVM_MEDIUM)
      finish_item(item);

      // --- Read with timeout on nominated beat ---
      item = axi_err_seq_item::type_id::create("err_timeout_rd");
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
            item.err_type   == ERR_TIMEOUT;
            item.err_beat   == local::err_beat;
          }) begin
        `uvm_fatal("AXI_ERR_TIMEOUT_SEQ", "randomize failed on read item")
      end
      item.cfg = cfg;
      finish_item(item);
      rd_rsp = item;

      `uvm_info("AXI_ERR_TIMEOUT_SEQ",
        $sformatf("TIMEOUT read complete resp=%s",
          (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A"),
        UVM_MEDIUM)
    end
  endtask

endclass

`endif // AXI_ERR_TIMEOUT_SEQ_SV
