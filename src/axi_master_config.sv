`ifndef AXI_MASTER_CONFIG_SV
`define AXI_MASTER_CONFIG_SV

class axi_master_config extends uvm_object;

  `uvm_object_utils(axi_master_config)

  bit enabled = 1;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  int unsigned max_outstanding_rd = 16;
  int unsigned max_outstanding_wr = 16;

  bit          enable_bw_limit      = 0;
  int unsigned max_bytes_per_window = 1024;
  int unsigned bw_window_cycles     = 100;

  bit per_channel_bp_enable = 0;

  axi_bp_config b_bp_cfg;
  axi_bp_config r_bp_cfg;
  axi_bp_config global_bp_cfg;

  function new(string name = "axi_master_config");
    super.new(name);
    global_bp_cfg = axi_bp_config::type_id::create("global_bp_cfg");
    b_bp_cfg      = axi_bp_config::type_id::create("b_bp_cfg");
    r_bp_cfg      = axi_bp_config::type_id::create("r_bp_cfg");
  endfunction

  function axi_bp_config get_bp_cfg(string channel);
    if (!per_channel_bp_enable)
      return global_bp_cfg;
    case (channel)
      "b": return b_bp_cfg;
      "r": return r_bp_cfg;
      default: return global_bp_cfg;
    endcase
  endfunction

  function bit validate(output string reason);
    axi_bp_config active_bp_cfg;

    if (!enabled) begin
      reason = "";
      return 1;
    end

    if (max_outstanding_rd == 0 || max_outstanding_wr == 0) begin
      reason = "master outstanding read and write limits must be nonzero";
      return 0;
    end

    if (enable_bw_limit &&
        (max_bytes_per_window == 0 || bw_window_cycles == 0)) begin
      reason = "master bandwidth limit requires nonzero bytes and cycles";
      return 0;
    end

    active_bp_cfg = get_bp_cfg("b");
    if (active_bp_cfg != null &&
        !active_bp_cfg.validate("master B", reason))
      return 0;
    active_bp_cfg = get_bp_cfg("r");
    if (active_bp_cfg != null &&
        !active_bp_cfg.validate("master R", reason))
      return 0;

    reason = "";
    return 1;
  endfunction

endclass

`endif // AXI_MASTER_CONFIG_SV
