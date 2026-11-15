`ifndef AXI_SLAVE_CONFIG_SV
`define AXI_SLAVE_CONFIG_SV

class axi_slave_config extends uvm_object;

  `uvm_object_utils(axi_slave_config)

  bit enabled = 1;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  int unsigned resp_delay_min = 0;
  int unsigned resp_delay_max = 10;

  bit enable_err_inject = 0;
  bit per_channel_bp_enable = 0;

  axi_bp_config aw_bp_cfg;
  axi_bp_config w_bp_cfg;
  axi_bp_config ar_bp_cfg;
  axi_bp_config global_bp_cfg;

  function new(string name = "axi_slave_config");
    super.new(name);
    global_bp_cfg = axi_bp_config::type_id::create("global_bp_cfg");
    aw_bp_cfg     = axi_bp_config::type_id::create("aw_bp_cfg");
    w_bp_cfg      = axi_bp_config::type_id::create("w_bp_cfg");
    ar_bp_cfg     = axi_bp_config::type_id::create("ar_bp_cfg");
  endfunction

  function axi_bp_config get_bp_cfg(string channel);
    if (!per_channel_bp_enable)
      return global_bp_cfg;
    case (channel)
      "aw": return aw_bp_cfg;
      "w":  return w_bp_cfg;
      "ar": return ar_bp_cfg;
      default: return global_bp_cfg;
    endcase
  endfunction

  function bit validate(output string reason);
    axi_bp_config active_bp_cfg;

    if (!enabled) begin
      reason = "";
      return 1;
    end

    if (resp_delay_min > resp_delay_max) begin
      reason = $sformatf(
        "slave response delay minimum %0d exceeds maximum %0d",
        resp_delay_min, resp_delay_max);
      return 0;
    end

    active_bp_cfg = get_bp_cfg("aw");
    if (active_bp_cfg != null &&
        !active_bp_cfg.validate("slave AW", reason))
      return 0;
    active_bp_cfg = get_bp_cfg("w");
    if (active_bp_cfg != null &&
        !active_bp_cfg.validate("slave W", reason))
      return 0;
    active_bp_cfg = get_bp_cfg("ar");
    if (active_bp_cfg != null &&
        !active_bp_cfg.validate("slave AR", reason))
      return 0;

    reason = "";
    return 1;
  endfunction

endclass

`endif // AXI_SLAVE_CONFIG_SV
