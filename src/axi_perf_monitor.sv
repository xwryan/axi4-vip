`ifndef AXI_PERF_MONITOR_SV
`define AXI_PERF_MONITOR_SV

class axi_perf_monitor extends uvm_subscriber #(axi_seq_item);

  `uvm_component_utils(axi_perf_monitor)

  axi_config cfg;

  // Transaction counters
  int unsigned total_rd_txn;
  int unsigned total_wr_txn;
  int unsigned peak_rd_outstanding;
  int unsigned peak_wr_outstanding;

  // Byte counters
  longint unsigned total_rd_bytes;
  longint unsigned total_wr_bytes;

  // Latency accumulators (in simulation time units)
  longint unsigned sum_rd_latency;
  longint unsigned sum_wr_latency;
  longint unsigned max_rd_latency;
  longint unsigned max_wr_latency;

  // Simulation window (all transactions)
  time first_txn_time;
  time last_txn_time;
  bit  first_txn_seen;

  // Per-direction timing for accurate BW calculation
  time first_rd_time;
  time last_rd_time;
  bit  first_rd_seen;
  time first_wr_time;
  time last_wr_time;
  bit  first_wr_seen;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    total_rd_txn    = 0;
    total_wr_txn    = 0;
    peak_rd_outstanding = 0;
    peak_wr_outstanding = 0;
    total_rd_bytes  = 0;
    total_wr_bytes  = 0;
    sum_rd_latency  = 0;
    sum_wr_latency  = 0;
    max_rd_latency  = 0;
    max_wr_latency  = 0;
    first_txn_time  = 0;
    last_txn_time   = 0;
    first_txn_seen  = 0;
    first_rd_time   = 0;
    last_rd_time    = 0;
    first_rd_seen   = 0;
    first_wr_time   = 0;
    last_wr_time    = 0;
    first_wr_seen   = 0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(axi_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("CFG", "axi_perf_monitor: axi_config not found in config_db")
  endfunction

  virtual function void write(axi_seq_item t);
    longint unsigned latency;
    int unsigned     num_bytes;

    // Record timing window
    if (!first_txn_seen) begin
      first_txn_time = t.addr_phase_time;
      first_txn_seen = 1;
    end
    last_txn_time = t.resp_time;

    num_bytes = t.get_total_bytes();
    latency   = t.get_latency();

    if (t.txn_type == AXI_READ) begin
      total_rd_txn++;
      if (t.outstanding_at_issue > peak_rd_outstanding)
        peak_rd_outstanding = t.outstanding_at_issue;
      total_rd_bytes += num_bytes;
      sum_rd_latency += latency;
      if (latency > max_rd_latency)
        max_rd_latency = latency;
      if (!first_rd_seen) begin
        first_rd_time = t.addr_phase_time;
        first_rd_seen = 1;
      end
      last_rd_time = t.resp_time;
    end else begin
      total_wr_txn++;
      if (t.outstanding_at_issue > peak_wr_outstanding)
        peak_wr_outstanding = t.outstanding_at_issue;
      total_wr_bytes += num_bytes;
      sum_wr_latency += latency;
      if (latency > max_wr_latency)
        max_wr_latency = latency;
      if (!first_wr_seen) begin
        first_wr_time = t.addr_phase_time;
        first_wr_seen = 1;
      end
      last_wr_time = t.resp_time;
    end
  endfunction

  // Reset all counters so statistics can be collected per-phase.
  virtual function void reset();
    total_rd_txn    = 0;
    total_wr_txn    = 0;
    peak_rd_outstanding = 0;
    peak_wr_outstanding = 0;
    total_rd_bytes  = 0;
    total_wr_bytes  = 0;
    sum_rd_latency  = 0;
    sum_wr_latency  = 0;
    max_rd_latency  = 0;
    max_wr_latency  = 0;
    first_txn_time  = 0;
    last_txn_time   = 0;
    first_txn_seen  = 0;
    first_rd_time   = 0;
    last_rd_time    = 0;
    first_rd_seen   = 0;
    first_wr_time   = 0;
    last_wr_time    = 0;
    first_wr_seen   = 0;
  endfunction

  // Print a summary for the current stats window (usable mid-simulation).
  virtual function void print_stats(string phase_name);
    longint unsigned elapsed;
    longint unsigned rd_elapsed, wr_elapsed;
    real avg_rd_lat, avg_wr_lat;
    real rd_throughput, wr_throughput;
    real rd_bw_gbps, wr_bw_gbps;

    elapsed = (last_txn_time > first_txn_time) ?
              (last_txn_time - first_txn_time) : 1;

    rd_elapsed = (last_rd_time > first_rd_time) ?
                 (last_rd_time - first_rd_time) : 1;
    wr_elapsed = (last_wr_time > first_wr_time) ?
                 (last_wr_time - first_wr_time) : 1;

    avg_rd_lat = (total_rd_txn > 0) ?
                 (real'(sum_rd_latency) / real'(total_rd_txn)) : 0.0;
    avg_wr_lat = (total_wr_txn > 0) ?
                 (real'(sum_wr_latency) / real'(total_wr_txn)) : 0.0;

    rd_throughput = real'(total_rd_bytes) / real'(elapsed);
    wr_throughput = real'(total_wr_bytes) / real'(elapsed);

    // Per-direction BW in Gbps (bytes * 8000 / duration_ps)
    if (total_rd_txn > 0)
      rd_bw_gbps = (real'(total_rd_bytes) * 8000.0) / real'(rd_elapsed);
    else
      rd_bw_gbps = 0.0;

    if (total_wr_txn > 0)
      wr_bw_gbps = (real'(total_wr_bytes) * 8000.0) / real'(wr_elapsed);
    else
      wr_bw_gbps = 0.0;

    `uvm_info("PERF", $sformatf("--- %s ---", phase_name), UVM_NONE)
    `uvm_info("PERF", $sformatf("  rd_txn=%0d  wr_txn=%0d  rd_bytes=%0d  wr_bytes=%0d",
      total_rd_txn, total_wr_txn, total_rd_bytes, total_wr_bytes), UVM_NONE)
    `uvm_info("PERF", $sformatf(
      "  peak_rd_outstanding=%0d  peak_wr_outstanding=%0d",
      peak_rd_outstanding, peak_wr_outstanding), UVM_NONE)
    `uvm_info("PERF", $sformatf("  avg_rd_lat=%.2f  avg_wr_lat=%.2f  max_rd_lat=%0d  max_wr_lat=%0d",
      avg_rd_lat, avg_wr_lat, max_rd_latency, max_wr_latency), UVM_NONE)
    `uvm_info("PERF", $sformatf("  rd_throughput=%.4f B/tu  wr_throughput=%.4f B/tu",
      rd_throughput, wr_throughput), UVM_NONE)
    `uvm_info("PERF", $sformatf("  rd_bw=%.3f Gbps  wr_bw=%.3f Gbps",
      rd_bw_gbps, wr_bw_gbps), UVM_NONE)
  endfunction

  virtual function void report_phase(uvm_phase phase);
    longint unsigned elapsed;
    longint unsigned rd_elapsed, wr_elapsed;
    real avg_rd_lat, avg_wr_lat;
    real rd_throughput, wr_throughput;
    real rd_bw_gbps, wr_bw_gbps;

    elapsed = (last_txn_time > first_txn_time) ?
              (last_txn_time - first_txn_time) : 1;

    rd_elapsed = (last_rd_time > first_rd_time) ?
                 (last_rd_time - first_rd_time) : 1;
    wr_elapsed = (last_wr_time > first_wr_time) ?
                 (last_wr_time - first_wr_time) : 1;

    avg_rd_lat = (total_rd_txn > 0) ?
                 (real'(sum_rd_latency) / real'(total_rd_txn)) : 0.0;
    avg_wr_lat = (total_wr_txn > 0) ?
                 (real'(sum_wr_latency) / real'(total_wr_txn)) : 0.0;

    rd_throughput = real'(total_rd_bytes) / real'(elapsed);
    wr_throughput = real'(total_wr_bytes) / real'(elapsed);

    if (total_rd_txn > 0)
      rd_bw_gbps = (real'(total_rd_bytes) * 8000.0) / real'(rd_elapsed);
    else
      rd_bw_gbps = 0.0;

    if (total_wr_txn > 0)
      wr_bw_gbps = (real'(total_wr_bytes) * 8000.0) / real'(wr_elapsed);
    else
      wr_bw_gbps = 0.0;

    `uvm_info("PERF", "======================================================", UVM_NONE)
    `uvm_info("PERF", "           AXI Performance Monitor Report             ", UVM_NONE)
    `uvm_info("PERF", "======================================================", UVM_NONE)
    `uvm_info("PERF", $sformatf("  Simulation window : %0t -- %0t  (elapsed=%0d)",
      first_txn_time, last_txn_time, elapsed), UVM_NONE)
    `uvm_info("PERF", "------------------------------------------------------", UVM_NONE)
    `uvm_info("PERF", $sformatf("  READ  transactions : %0d",      total_rd_txn),   UVM_NONE)
    `uvm_info("PERF", $sformatf("  READ  total bytes  : %0d",      total_rd_bytes), UVM_NONE)
    `uvm_info("PERF", $sformatf("  READ  avg latency  : %.2f",     avg_rd_lat),     UVM_NONE)
    `uvm_info("PERF", $sformatf("  READ  max latency  : %0d",      max_rd_latency), UVM_NONE)
    `uvm_info("PERF", $sformatf("  READ  throughput   : %.4f B/tu", rd_throughput), UVM_NONE)
    `uvm_info("PERF", $sformatf("  READ  bandwidth    : %.3f Gbps", rd_bw_gbps),   UVM_NONE)
    `uvm_info("PERF", "------------------------------------------------------", UVM_NONE)
    `uvm_info("PERF", $sformatf("  WRITE transactions : %0d",      total_wr_txn),   UVM_NONE)
    `uvm_info("PERF", $sformatf("  WRITE total bytes  : %0d",      total_wr_bytes), UVM_NONE)
    `uvm_info("PERF", $sformatf("  WRITE avg latency  : %.2f",     avg_wr_lat),     UVM_NONE)
    `uvm_info("PERF", $sformatf("  WRITE max latency  : %0d",      max_wr_latency), UVM_NONE)
    `uvm_info("PERF", $sformatf("  WRITE throughput   : %.4f B/tu", wr_throughput), UVM_NONE)
    `uvm_info("PERF", $sformatf("  WRITE bandwidth    : %.3f Gbps", wr_bw_gbps),   UVM_NONE)
    `uvm_info("PERF", $sformatf(
      "  peak_rd_outstanding=%0d  peak_wr_outstanding=%0d",
      peak_rd_outstanding, peak_wr_outstanding), UVM_NONE)
    `uvm_info("PERF", "======================================================", UVM_NONE)
  endfunction

endclass

`endif // AXI_PERF_MONITOR_SV
