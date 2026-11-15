`ifndef AXI_BW_LIMITER_SV
`define AXI_BW_LIMITER_SV

class axi_bw_limiter extends uvm_object;

  `uvm_object_utils(axi_bw_limiter)

  bit          enabled;
  int unsigned max_bytes_per_window;
  int unsigned window_cycles;

  protected int unsigned byte_counter;
  protected int unsigned cycle_counter;

  function new(string name = "axi_bw_limiter");
    super.new(name);
    enabled              = 0;
    max_bytes_per_window = 1024;
    window_cycles        = 100;
    byte_counter         = 0;
    cycle_counter        = 0;
  endfunction

  function void configure(bit en, int unsigned max_bytes, int unsigned win_cycles);
    this.enabled              = en;
    this.max_bytes_per_window = max_bytes;
    this.window_cycles        = win_cycles;
    reset();
  endfunction

  function void reset();
    byte_counter  = 0;
    cycle_counter = 0;
  endfunction

  function void tick();
    if (!enabled) return;
    cycle_counter++;
    if (cycle_counter >= window_cycles) begin
      cycle_counter = 0;
      byte_counter  = 0;
    end
  endfunction

  function bit can_send(int unsigned num_bytes);
    if (!enabled) return 1;
    return (byte_counter + num_bytes) <= max_bytes_per_window;
  endfunction

  function void record_sent(int unsigned num_bytes);
    if (!enabled) return;
    byte_counter += num_bytes;
  endfunction

  function bit is_throttled();
    if (!enabled) return 0;
    return (byte_counter >= max_bytes_per_window);
  endfunction

endclass

`endif // AXI_BW_LIMITER_SV
