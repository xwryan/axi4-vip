`ifndef AXI_BP_GENERATOR_SV
`define AXI_BP_GENERATOR_SV

class axi_bp_generator extends uvm_object;

  `uvm_object_utils(axi_bp_generator)

  axi_bp_config bp_cfg;

  protected int unsigned cycle_count;
  protected int unsigned burst_counter;
  protected bit          burst_accepting;

  function new(string name = "axi_bp_generator");
    super.new(name);
    cycle_count     = 0;
    burst_counter   = 0;
    burst_accepting = 1;
  endfunction

  function void set_config(axi_bp_config cfg);
    this.bp_cfg = cfg;
    reset();
  endfunction

  function void reset();
    cycle_count     = 0;
    burst_counter   = 0;
    burst_accepting = 1;
  endfunction

  virtual function bit get_ready();
    bit ready;
    if (bp_cfg == null) return 1;

    case (bp_cfg.mode)
      BP_NONE: begin
        ready = 1;
      end
      BP_FIXED_DELAY: begin
        ready = (cycle_count >= bp_cfg.fixed_delay);
        if (ready) cycle_count = 0;
        else cycle_count++;
      end
      BP_RANDOM: begin
        int unsigned rand_val;
        rand_val = $urandom_range(0, 99);
        ready = (rand_val < bp_cfg.random_ready_pct);
      end
      BP_BURST: begin
        if (burst_accepting) begin
          ready = 1;
          burst_counter++;
          if (burst_counter >= bp_cfg.burst_accept_cycles) begin
            burst_accepting = 0;
            burst_counter   = 0;
          end
        end else begin
          ready = 0;
          burst_counter++;
          if (burst_counter >= bp_cfg.burst_block_cycles) begin
            burst_accepting = 1;
            burst_counter   = 0;
          end
        end
      end
      BP_INTERMITTENT: begin
        int unsigned total_window = bp_cfg.on_window + bp_cfg.off_window;
        int unsigned phase = cycle_count % total_window;
        ready = (phase < bp_cfg.on_window);
        cycle_count++;
      end
      BP_CUSTOM: begin
        ready = 1;
      end
      default: begin
        ready = 1;
      end
    endcase

    return ready;
  endfunction

endclass

`endif // AXI_BP_GENERATOR_SV
