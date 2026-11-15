// seq_lib/axi_random_stress_seq.sv
`ifndef AXI_RANDOM_STRESS_SEQ_SV
`define AXI_RANDOM_STRESS_SEQ_SV

// Random fully-constrained stress sequence.
// Issues num_txn transactions whose type (read/write), address, burst
// parameters, and data are all randomised within legal AXI constraints.
// Designed to maximise functional coverage hits across a single run.
class axi_random_stress_seq extends axi_base_seq;

  `uvm_object_utils(axi_random_stress_seq)

  // Knobs
  rand int unsigned  num_txn;      // total number of transactions
  rand bit           allow_wrap;   // enable WRAP bursts in the mix
  rand bit           allow_fixed;  // enable FIXED bursts in the mix
  rand bit           allow_excl;   // enable exclusive accesses in the mix

  constraint num_txn_c {
    num_txn inside {[8:64]};
  }

  function new(string name = "axi_random_stress_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item item;
    axi_seq_item rsp;

    `uvm_info("AXI_RANDOM_STRESS_SEQ",
      $sformatf("Starting random stress: %0d transactions (wrap=%0b fixed=%0b excl=%0b)",
        num_txn, allow_wrap, allow_fixed, allow_excl),
      UVM_MEDIUM)

    for (int i = 0; i < int'(num_txn); i++) begin
      item = axi_seq_item::type_id::create($sformatf("stress_item_%0d", i));
      item.cfg = cfg;
      start_item(item);

      if (!item.randomize() with {
            // Burst type limited by knobs
            if (!allow_wrap && !allow_fixed)
              burst_type == AXI_INCR;
            else if (!allow_wrap)
              burst_type inside {AXI_INCR, AXI_FIXED};
            else if (!allow_fixed)
              burst_type inside {AXI_INCR, AXI_WRAP};

            // Exclusive only when knob permits
            if (!allow_excl)
              lock == 1'b0;

            // Keep burst size sane for a 64-bit bus
            burst_size inside {[0:3]};

            // WRAP constraints
            if (burst_type == AXI_WRAP)
              burst_len inside {8'h01, 8'h03, 8'h07, 8'h0F};

            // FIXED max 16 beats
            if (burst_type == AXI_FIXED)
              burst_len inside {[0:15]};

            // INCR 4KB boundary
            if (burst_type == AXI_INCR)
              (addr % 4096) + ((burst_len + 1) * (1 << burst_size)) <= 4096;

            // Exclusive constraints
            if (lock == 1'b1) {
              burst_len inside {8'h00, 8'h01, 8'h03, 8'h07, 8'h0F};
              (burst_len + 1) * (1 << burst_size) <= 128;
            }

            // No error injection in stress mode
            inject_err == 1'b0;
          }) begin
        `uvm_fatal("AXI_RANDOM_STRESS_SEQ",
          $sformatf("randomize failed for transaction %0d", i))
      end

      `uvm_info("AXI_RANDOM_STRESS_SEQ",
        $sformatf("[%0d/%0d] %s addr=0x%0h len=%0d size=%0d burst=%s lock=%0b id=0x%0h",
          i+1, num_txn,
          item.txn_type.name(), item.addr, item.burst_len,
          item.burst_size, item.burst_type.name(), item.lock, item.id),
        UVM_HIGH)

      finish_item(item);
      wait_response(item, rsp);
      if (rsp == null)
        `uvm_fatal("AXI_RANDOM_STRESS_SEQ", $sformatf(
          "transaction %0d returned a null response", i))
      if (rsp.aborted)
        `uvm_error("AXI_RANDOM_STRESS_SEQ", $sformatf(
          "transaction %0d response was aborted", i))
    end

    `uvm_info("AXI_RANDOM_STRESS_SEQ",
      $sformatf("Random stress complete: %0d transactions issued", num_txn),
      UVM_MEDIUM)
  endtask

endclass

`endif // AXI_RANDOM_STRESS_SEQ_SV
