`ifndef AXI_CONFIG_SV
`define AXI_CONFIG_SV

class axi_config extends uvm_object;

  `uvm_object_utils(axi_config)

  axi_mode_e       mode = AXI4;
  axi_agent_role_e role = AXI_MASTER;

  int unsigned data_width  = 64;
  int unsigned addr_width  = 32;
  int unsigned id_width    = 4;
  int unsigned user_width  = 0;

  bit has_coverage       = 0;
  bit has_protocol_check = 1;
  bit has_scoreboard     = 1;

  int unsigned resp_delay_min = 0;
  int unsigned resp_delay_max = 10;

  int unsigned max_outstanding_rd = 16;
  int unsigned max_outstanding_wr = 16;

  bit enable_err_inject = 0;

  bit          enable_bw_limit       = 0;
  int unsigned max_bytes_per_window  = 1024;
  int unsigned bw_window_cycles      = 100;

  bit per_channel_bp_enable = 0;

  axi_bp_config aw_bp_cfg;
  axi_bp_config w_bp_cfg;
  axi_bp_config ar_bp_cfg;
  axi_bp_config b_bp_cfg;
  axi_bp_config r_bp_cfg;
  axi_bp_config global_bp_cfg;

  axi_master_config master_cfg;
  axi_slave_config  slave_cfg;

  virtual axi_if vif;

  function new(string name = "axi_config");
    super.new(name);
    global_bp_cfg = axi_bp_config::type_id::create("global_bp_cfg");
    aw_bp_cfg     = axi_bp_config::type_id::create("aw_bp_cfg");
    w_bp_cfg      = axi_bp_config::type_id::create("w_bp_cfg");
    ar_bp_cfg     = axi_bp_config::type_id::create("ar_bp_cfg");
    b_bp_cfg      = axi_bp_config::type_id::create("b_bp_cfg");
    r_bp_cfg      = axi_bp_config::type_id::create("r_bp_cfg");
  endfunction

  function axi_bp_config get_bp_cfg(string channel);
    if (!per_channel_bp_enable)
      return global_bp_cfg;
    case (channel)
      "aw": return aw_bp_cfg;
      "w":  return w_bp_cfg;
      "ar": return ar_bp_cfg;
      "b":  return b_bp_cfg;
      "r":  return r_bp_cfg;
      default: return global_bp_cfg;
    endcase
  endfunction

  function int unsigned get_strb_width();
    return data_width / 8;
  endfunction

  function int unsigned get_max_burst_size();
    return $clog2(data_width / 8);
  endfunction

  function void resolve_agent_configs();
    if (master_cfg == null) begin
      master_cfg = axi_master_config::type_id::create("master_cfg");
      master_cfg.max_outstanding_rd    = max_outstanding_rd;
      master_cfg.max_outstanding_wr    = max_outstanding_wr;
      master_cfg.enable_bw_limit       = enable_bw_limit;
      master_cfg.max_bytes_per_window  = max_bytes_per_window;
      master_cfg.bw_window_cycles      = bw_window_cycles;
      master_cfg.per_channel_bp_enable = per_channel_bp_enable;
      if (global_bp_cfg != null)
        master_cfg.global_bp_cfg = global_bp_cfg.copy_config();
      if (b_bp_cfg != null)
        master_cfg.b_bp_cfg = b_bp_cfg.copy_config();
      if (r_bp_cfg != null)
        master_cfg.r_bp_cfg = r_bp_cfg.copy_config();
    end

    if (slave_cfg == null) begin
      slave_cfg = axi_slave_config::type_id::create("slave_cfg");
      slave_cfg.resp_delay_min         = resp_delay_min;
      slave_cfg.resp_delay_max         = resp_delay_max;
      slave_cfg.enable_err_inject      = enable_err_inject;
      slave_cfg.per_channel_bp_enable = per_channel_bp_enable;
      if (global_bp_cfg != null)
        slave_cfg.global_bp_cfg = global_bp_cfg.copy_config();
      if (aw_bp_cfg != null)
        slave_cfg.aw_bp_cfg = aw_bp_cfg.copy_config();
      if (w_bp_cfg != null)
        slave_cfg.w_bp_cfg = w_bp_cfg.copy_config();
      if (ar_bp_cfg != null)
        slave_cfg.ar_bp_cfg = ar_bp_cfg.copy_config();
    end
  endfunction

  function bit validate(output string reason);
    resolve_agent_configs();

    if ((master_cfg.enabled || slave_cfg.enabled) && vif == null) begin
      reason = "an enabled endpoint requires a virtual interface";
      return 0;
    end

    if (!master_cfg.validate(reason))
      return 0;
    if (!slave_cfg.validate(reason))
      return 0;

    if (!master_cfg.enabled && !slave_cfg.enabled &&
        (has_scoreboard || has_coverage)) begin
      reason = "scoreboard or coverage requires an enabled endpoint monitor";
      return 0;
    end

    if (!master_cfg.enabled && !slave_cfg.enabled && !has_protocol_check) begin
      reason = "environment must enable an endpoint or protocol checker";
      return 0;
    end

    reason = "";
    return 1;
  endfunction

endclass

`endif // AXI_CONFIG_SV
