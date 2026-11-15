// error_inject/axi_err_resp_seq.sv
`ifndef AXI_ERR_RESP_SEQ_SV
`define AXI_ERR_RESP_SEQ_SV

// RESP error injection sequence.
// Sends a configurable number of write and/or read transactions that
// request ERR_RESP injection on a chosen beat.  The slave driver
// (axi_slave_driver) returns AXI_SLVERR on that beat when
// cfg.slave_cfg.enable_err_inject is set.
class axi_err_resp_seq extends axi_base_seq;

  `uvm_object_utils(axi_err_resp_seq)

  // Knobs
  rand bit [63:0]   addr;
  rand bit [7:0]    burst_len;
  rand bit [2:0]    burst_size;
  rand bit [15:0]   id;
  rand int unsigned err_beat;            // beat index on which to inject SLVERR
  int unsigned      num_iterations = 4;  // how many error transactions to run

  constraint burst_len_c  { burst_len  inside {[0:15]};  }
  constraint burst_size_c { burst_size inside {[0:3]};   }
  constraint addr_align_c { (addr % (1 << burst_size)) == 0; }
  constraint addr_4kb_c   {
    (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) <= 4096;
  }
  constraint err_beat_c   { err_beat <= burst_len; }

  function new(string name = "axi_err_resp_seq");
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
      // --- Write with RESP error ---
      item = axi_err_seq_item::type_id::create("err_resp_wr");
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
            item.err_type   == ERR_RESP;
            item.err_beat   == local::err_beat;
          }) begin
        `uvm_fatal("AXI_ERR_RESP_SEQ", "randomize failed on write item")
      end
      item.cfg = cfg;
      `uvm_info("AXI_ERR_RESP_SEQ",
        $sformatf("Injecting RESP error: %s", item.convert2string()),
        UVM_MEDIUM)
      finish_item(item);

      // --- Read back (also carrying error flag so slave injects on read) ---
      item = axi_err_seq_item::type_id::create("err_resp_rd");
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
            item.err_type   == ERR_RESP;
            item.err_beat   == local::err_beat;
          }) begin
        `uvm_fatal("AXI_ERR_RESP_SEQ", "randomize failed on read item")
      end
      item.cfg = cfg;
      finish_item(item);
      rd_rsp = item;

      `uvm_info("AXI_ERR_RESP_SEQ",
        $sformatf("RESP error read complete resp=%s",
          (rd_rsp.resp.size() > 0) ? rd_rsp.resp[0].name() : "N/A"),
        UVM_MEDIUM)
    end
  endtask

endclass

`endif // AXI_ERR_RESP_SEQ_SV
