`ifndef AXI_BP_CONFIG_SV
`define AXI_BP_CONFIG_SV

class axi_bp_config extends uvm_object;

  `uvm_object_utils(axi_bp_config)

  axi_bp_mode_e mode = BP_NONE;

  int unsigned fixed_delay = 5;
  int unsigned random_ready_pct = 50;
  int unsigned burst_accept_cycles = 8;
  int unsigned burst_block_cycles  = 4;
  int unsigned on_window  = 20;
  int unsigned off_window = 5;

  function new(string name = "axi_bp_config");
    super.new(name);
  endfunction

  function axi_bp_config copy_config();
    axi_bp_config c = axi_bp_config::type_id::create("bp_cfg_copy");
    c.mode                = this.mode;
    c.fixed_delay         = this.fixed_delay;
    c.random_ready_pct    = this.random_ready_pct;
    c.burst_accept_cycles = this.burst_accept_cycles;
    c.burst_block_cycles  = this.burst_block_cycles;
    c.on_window           = this.on_window;
    c.off_window          = this.off_window;
    return c;
  endfunction

  function bit validate(string scope, output string reason);
    reason = "";
    case (mode)
      BP_RANDOM: begin
        if (random_ready_pct > 100) begin
          reason = $sformatf("%s random_ready_pct=%0d exceeds 100",
                             scope, random_ready_pct);
          return 0;
        end
      end
      BP_BURST: begin
        if (burst_accept_cycles == 0 || burst_block_cycles == 0) begin
          reason = $sformatf(
            "%s BP_BURST requires nonzero accept and block windows", scope);
          return 0;
        end
      end
      BP_INTERMITTENT: begin
        if (on_window == 0 || off_window == 0) begin
          reason = $sformatf(
            "%s BP_INTERMITTENT requires nonzero on and off windows", scope);
          return 0;
        end
      end
      BP_NONE, BP_FIXED_DELAY, BP_CUSTOM: begin end
      default: begin
        reason = $sformatf("%s mode=%0d is not a valid axi_bp_mode_e",
                           scope, mode);
        return 0;
      end
    endcase
    return 1;
  endfunction

endclass

`endif // AXI_BP_CONFIG_SV
