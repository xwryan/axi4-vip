// seq_lib/axi_outstanding_seq.sv
`ifndef AXI_OUTSTANDING_SEQ_SV
`define AXI_OUTSTANDING_SEQ_SV

// Multiple outstanding transactions sequence.
// Issues num_wr write transactions back-to-back (without waiting for
// responses), then issues num_rd read transactions back-to-back, stressing
// the ID-tracking and reorder buffer logic in the master driver and
// scoreboard.
class axi_outstanding_seq extends axi_base_seq;

  `uvm_object_utils(axi_outstanding_seq)

  // Knobs
  rand int unsigned  num_wr;       // number of outstanding writes
  rand int unsigned  num_rd;       // number of outstanding reads
  rand bit [63:0]    base_addr;
  rand bit [2:0]     burst_size;
  rand bit [7:0]     burst_len;

  constraint num_wr_c {
    num_wr inside {[2:8]};
  }

  constraint num_rd_c {
    num_rd inside {[2:8]};
  }

  constraint burst_size_range_c {
    burst_size inside {[0:3]};
  }

  constraint burst_len_c {
    burst_len inside {[0:7]};
  }

  // Ensure transactions stay in address space and do not overlap across 4KB
  constraint base_addr_c {
    (base_addr % (1 << burst_size)) == 0;
    base_addr < 64'hFFFF_0000;
  }

  function new(string name = "axi_outstanding_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item wr_req[];
    axi_seq_item wr_rsp[];
    axi_seq_item rd_req[];
    axi_seq_item rd_rsp[];
    int unsigned  num_bytes;
    int unsigned  step;
    bit [7:0]     wr_data[];
    bit [63:0]    addr;

    num_bytes = (burst_len + 1) * (1 << burst_size);
    step      = num_bytes;
    wr_data   = new [num_bytes];
    wr_req    = new [num_wr];
    wr_rsp    = new [num_wr];
    rd_req    = new [num_rd];
    rd_rsp    = new [num_rd];

    `uvm_info("AXI_OUTSTANDING_SEQ",
      $sformatf("Issuing %0d outstanding WRITEs then %0d outstanding READs base=0x%0h",
        num_wr, num_rd, base_addr),
      UVM_MEDIUM)

    // --- Fire all writes without waiting between them ---
    for (int i = 0; i < int'(num_wr); i++) begin
      addr = base_addr + i * step;

      foreach (wr_data[j])
        wr_data[j] = (i[7:0] + j[7:0]);

      `uvm_info("AXI_OUTSTANDING_SEQ",
        $sformatf("OUTSTANDING WRITE[%0d] addr=0x%0h len=%0d size=%0d id=0x%0h",
          i, addr, burst_len, burst_size, i[15:0]),
        UVM_HIGH)

      issue_write(
        .addr       (addr),
        .data       (wr_data),
        .burst_len  (burst_len),
        .burst_size (burst_size),
        .burst_type (AXI_INCR),
        .id         (i[15:0]),
        .req        (wr_req[i])
      );
    end

    `uvm_info("AXI_OUTSTANDING_SEQ",
      $sformatf("All %0d writes issued; now waiting for B responses", num_wr),
      UVM_MEDIUM)

    foreach (wr_req[i]) begin
      wait_response(wr_req[i], wr_rsp[i]);
      if (wr_rsp[i] == null)
        `uvm_fatal("AXI_OUTSTANDING_SEQ", $sformatf(
          "WRITE[%0d] returned a null response", i))
      if (wr_rsp[i].aborted)
        `uvm_error("AXI_OUTSTANDING_SEQ", $sformatf(
          "WRITE[%0d] response was aborted", i))
      if (wr_rsp[i].resp.size() != 1)
        `uvm_error("AXI_OUTSTANDING_SEQ", $sformatf(
          "WRITE[%0d] B response count=%0d expected=1",
          i, wr_rsp[i].resp.size()))
    end

    `uvm_info("AXI_OUTSTANDING_SEQ",
      $sformatf("All %0d B responses received; now issuing %0d reads",
        num_wr, num_rd), UVM_MEDIUM)

    // --- Fire all reads without waiting between them ---
    for (int i = 0; i < int'(num_rd); i++) begin
      addr = base_addr + i * step;

      `uvm_info("AXI_OUTSTANDING_SEQ",
        $sformatf("OUTSTANDING READ[%0d] addr=0x%0h len=%0d size=%0d id=0x%0h",
          i, addr, burst_len, burst_size, i[15:0]),
        UVM_HIGH)

      issue_read(
        .addr       (addr),
        .burst_len  (burst_len),
        .burst_size (burst_size),
        .burst_type (AXI_INCR),
        .id         (i[15:0]),
        .req        (rd_req[i])
      );
    end

    `uvm_info("AXI_OUTSTANDING_SEQ",
      $sformatf("All %0d reads issued; now waiting for RLAST responses", num_rd),
      UVM_MEDIUM)

    foreach (rd_req[i]) begin
      wait_response(rd_req[i], rd_rsp[i]);
      if (rd_rsp[i] == null)
        `uvm_fatal("AXI_OUTSTANDING_SEQ", $sformatf(
          "READ[%0d] returned a null response", i))
      if (rd_rsp[i].aborted)
        `uvm_error("AXI_OUTSTANDING_SEQ", $sformatf(
          "READ[%0d] response was aborted", i))
      if (rd_rsp[i].resp.size() != burst_len + 1)
        `uvm_error("AXI_OUTSTANDING_SEQ", $sformatf(
          "READ[%0d] R response count=%0d expected=%0d",
          i, rd_rsp[i].resp.size(), burst_len + 1))
    end

    `uvm_info("AXI_OUTSTANDING_SEQ",
      $sformatf("Outstanding sequence complete: %0d writes, %0d reads", num_wr, num_rd),
      UVM_MEDIUM)
  endtask

endclass

`endif // AXI_OUTSTANDING_SEQ_SV
