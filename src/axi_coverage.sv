`ifndef AXI_COVERAGE_SV
`define AXI_COVERAGE_SV

class axi_coverage extends uvm_subscriber #(axi_seq_item);

  `uvm_component_utils(axi_coverage)

  axi_config cfg;

  // Outstanding counts for outstanding covergroup
  int unsigned outstanding_rd;
  int unsigned outstanding_wr;

  // -----------------------------------------------------------------------
  // Main transaction covergroup
  // -----------------------------------------------------------------------
  covergroup axi_txn_cg with function sample(axi_seq_item item);

    cp_txn_type: coverpoint item.txn_type {
      bins READ  = {AXI_READ};
      bins WRITE = {AXI_WRITE};
    }

    cp_burst_type: coverpoint item.burst_type {
      bins FIXED = {AXI_FIXED};
      bins INCR  = {AXI_INCR};
      bins WRAP  = {AXI_WRAP};
    }

    cp_burst_size: coverpoint item.burst_size {
      bins SIZE_1B  = {3'h0};
      bins SIZE_2B  = {3'h1};
      bins SIZE_4B  = {3'h2};
      bins SIZE_8B  = {3'h3};
      bins SIZE_16B = {3'h4};
      bins SIZE_32B = {3'h5};
      bins SIZE_64B = {3'h6};
    }

    cp_burst_len: coverpoint item.burst_len {
      bins LEN_1    = {8'h00};
      bins LEN_2_4  = {[8'h01 : 8'h03]};
      bins LEN_5_8  = {[8'h04 : 8'h07]};
      bins LEN_9_16 = {[8'h08 : 8'h0f]};
      bins LEN_LONG = {[8'h10 : 8'hff]};
    }

    cp_resp: coverpoint item.resp[0] {
      bins OKAY   = {AXI_OKAY};
      bins EXOKAY = {AXI_EXOKAY};
      bins SLVERR = {AXI_SLVERR};
      bins DECERR = {AXI_DECERR};
    }

    cp_lock: coverpoint item.lock {
      bins NORMAL    = {1'b0};
      bins EXCLUSIVE = {1'b1};
    }

    cp_addr_range: coverpoint item.addr {
      bins LOW   = {[64'h0000_0000 : 64'h0000_ffff]};
      bins MID   = {[64'h0001_0000 : 64'h00ff_ffff]};
      bins HIGH  = {[64'h0100_0000 : 64'hffff_ffff]};
      bins UPPER = {[64'h1_0000_0000 : {64{1'b1}}]};
    }

    cp_narrow: coverpoint (item.burst_size < $clog2(item.data.size() / (item.burst_len + 1))) {
      bins NOT_NARROW = {1'b0};
      bins NARROW     = {1'b1};
    }

    cp_unaligned: coverpoint (item.addr % (1 << item.burst_size) != 0) {
      bins ALIGNED   = {1'b0};
      bins UNALIGNED = {1'b1};
    }

    // Cross coverage
    cx_type_x_burst: cross cp_txn_type, cp_burst_type;
    cx_type_x_size:  cross cp_txn_type, cp_burst_size;
    cx_type_x_len:   cross cp_txn_type, cp_burst_len;
    cx_burst_x_len:  cross cp_burst_type, cp_burst_len;

  endgroup : axi_txn_cg

  // -----------------------------------------------------------------------
  // Outstanding transaction covergroup
  // -----------------------------------------------------------------------
  covergroup axi_outstanding_cg;

    cp_outstanding_rd: coverpoint outstanding_rd {
      bins ZERO = {0};
      bins LOW  = {[1:4]};
      bins MED  = {[5:8]};
      bins HIGH = {[9:16]};
      bins MAX  = {[17:$]};
    }

    cp_outstanding_wr: coverpoint outstanding_wr {
      bins ZERO = {0};
      bins LOW  = {[1:4]};
      bins MED  = {[5:8]};
      bins HIGH = {[9:16]};
      bins MAX  = {[17:$]};
    }

    cx_rd_x_wr: cross cp_outstanding_rd, cp_outstanding_wr;

  endgroup : axi_outstanding_cg

  function new(string name, uvm_component parent);
    super.new(name, parent);
    axi_txn_cg         = new();
    axi_outstanding_cg = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(axi_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("CFG", "axi_coverage: axi_config not found in config_db")
  endfunction

  virtual function void write(axi_seq_item t);
    if (!cfg.has_coverage) return;

    // Track outstanding counts
    if (t.txn_type == AXI_READ)
      outstanding_rd = (outstanding_rd > 0) ? outstanding_rd - 1 : 0;
    else
      outstanding_wr = (outstanding_wr > 0) ? outstanding_wr - 1 : 0;

    if (t.resp.size() > 0)
      axi_txn_cg.sample(t);

    axi_outstanding_cg.sample();
  endfunction

endclass

`endif // AXI_COVERAGE_SV
