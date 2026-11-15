// seq_lib/axi_base_seq.sv
`ifndef AXI_BASE_SEQ_SV
`define AXI_BASE_SEQ_SV

// Base sequence for all AXI VIP sequences.
// Provides shared cfg handle, UVM config DB lookup, and
// do_write / do_read helper tasks so derived sequences avoid
// boilerplate item construction.
class axi_base_seq extends uvm_sequence #(axi_seq_item);

  `uvm_object_utils(axi_base_seq)

  // Central configuration -- populated in pre_start via config DB
  axi_config cfg;

  function new(string name = "axi_base_seq");
    super.new(name);
  endfunction

  // Retrieve cfg from the UVM config DB before the sequence body runs.
  virtual task pre_start();
    super.pre_start();
    set_response_queue_depth(-1);
    if (cfg == null) begin
      if (!uvm_config_db #(axi_config)::get(
            m_sequencer, "", "cfg", cfg)) begin
        `uvm_warning("AXI_BASE_SEQ",
          "axi_config not found in config DB; using default")
        cfg = axi_config::type_id::create("cfg");
      end
    end
    if (cfg.data_width == 0 || (cfg.data_width % 8) != 0 ||
        (cfg.data_width / 8) == 0 || (cfg.data_width / 8) > 64)
      `uvm_fatal("AXI_BASE_SEQ", $sformatf(
        "unsupported data_width=%0d; expected 8 to 512 whole-bit bytes",
        cfg.data_width))
  endtask

  // -----------------------------------------------------------------------
  // Helper: issue a single write transaction without waiting for its B
  // response. The returned request identity must be passed to wait_response.
  //   addr       - target byte address
  //   data       - byte array to write (determines total transfer size)
  //   burst_len  - number of beats - 1  (0 = single beat)
  //   burst_size - log2(bytes_per_beat) (0=1B, 1=2B, 2=4B, 3=8B ...)
  //   burst_type - AXI_FIXED / AXI_INCR / AXI_WRAP
  //   id         - transaction ID
  // -----------------------------------------------------------------------
  virtual task issue_write(
    input  bit [63:0]         addr,
    input  bit [7:0]          data[],
    input  bit [7:0]          burst_len  = 0,
    input  bit [2:0]          burst_size = 0,
    input  axi_burst_type_e   burst_type = AXI_INCR,
    input  bit [15:0]         id         = 0,
    output axi_seq_item       req
  );
    axi_seq_item item;
    item = axi_seq_item::type_id::create("wr_item");
    item.cfg = cfg;
    start_item(item);
    if (!item.randomize() with {
          txn_type        == AXI_WRITE;
          item.addr       == local::addr;
          item.id         == local::id;
          item.burst_len  == local::burst_len;
          item.burst_size == local::burst_size;
          item.burst_type == local::burst_type;
          item.lock       == 1'b0;
          item.inject_err == 1'b0;
        }) begin
      `uvm_fatal("AXI_BASE_SEQ", "issue_write: randomize failed")
    end
    // Override data after randomize so caller-supplied bytes are used
    item.data = data;
    // Set all wstrb bits to 1 so every byte is written
    foreach (item.wstrb[i])
      item.wstrb[i] = '1;
    finish_item(item);
    req = item;
  endtask

  // -----------------------------------------------------------------------
  // Helper: issue a single read transaction without waiting for RLAST.
  //   addr       - target byte address
  //   burst_len  - number of beats - 1
  //   burst_size - log2(bytes_per_beat)
  //   burst_type - AXI_FIXED / AXI_INCR / AXI_WRAP
  //   id         - transaction ID
  //   req        - output: issued item identity for wait_response
  // -----------------------------------------------------------------------
  virtual task issue_read(
    input  bit [63:0]         addr,
    input  bit [7:0]          burst_len  = 0,
    input  bit [2:0]          burst_size = 0,
    input  axi_burst_type_e   burst_type = AXI_INCR,
    input  bit [15:0]         id         = 0,
    output axi_seq_item       req
  );
    axi_seq_item item;
    item = axi_seq_item::type_id::create("rd_item");
    item.cfg = cfg;
    start_item(item);
    if (!item.randomize() with {
          txn_type        == AXI_READ;
          item.addr       == local::addr;
          item.id         == local::id;
          item.burst_len  == local::burst_len;
          item.burst_size == local::burst_size;
          item.burst_type == local::burst_type;
          item.lock       == 1'b0;
          item.inject_err == 1'b0;
        }) begin
      `uvm_fatal("AXI_BASE_SEQ", "issue_read: randomize failed")
    end
    finish_item(item);
    req = item;
  endtask

  // Wait for the exact response matching one previously issued request.
  virtual task wait_response(
    input  axi_seq_item req,
    output axi_seq_item rsp
  );
    if (req == null)
      `uvm_fatal("AXI_BASE_SEQ", "wait_response received a null request")
    get_response(rsp, req.get_transaction_id());
    if (rsp == null)
      `uvm_fatal("AXI_BASE_SEQ", "sequencer returned a null response")
  endtask

  // Blocking compatibility wrapper: issue one write and wait for its B.
  virtual task do_write(
    input  bit [63:0]         addr,
    input  bit [7:0]          data[],
    input  bit [7:0]          burst_len  = 8'h00,
    input  bit [2:0]          burst_size = 3'h0,
    input  axi_burst_type_e   burst_type = AXI_INCR,
    input  bit [15:0]         id         = 16'h0
  );
    axi_seq_item req;
    axi_seq_item rsp;

    issue_write(addr, data, burst_len, burst_size, burst_type, id, req);
    wait_response(req, rsp);
    if (rsp.aborted)
      `uvm_error("AXI_BASE_SEQ",
        "do_write completed without a bus B response")
  endtask

  // Blocking compatibility wrapper: issue one read and wait for RLAST.
  virtual task do_read(
    input  bit [63:0]         addr,
    input  bit [7:0]          burst_len  = 8'h00,
    input  bit [2:0]          burst_size = 3'h0,
    input  axi_burst_type_e   burst_type = AXI_INCR,
    input  bit [15:0]         id         = 16'h0,
    output axi_seq_item       rsp
  );
    axi_seq_item req;

    issue_read(addr, burst_len, burst_size, burst_type, id, req);
    wait_response(req, rsp);
    if (rsp.aborted)
      `uvm_error("AXI_BASE_SEQ",
        "do_read completed without an RLAST response")
  endtask

  // Default body -- derived classes override this
  virtual task body();
  endtask

endclass

`endif // AXI_BASE_SEQ_SV
