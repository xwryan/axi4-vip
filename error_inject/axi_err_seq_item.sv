// error_inject/axi_err_seq_item.sv
`ifndef AXI_ERR_SEQ_ITEM_SV
`define AXI_ERR_SEQ_ITEM_SV

// Extended sequence item with error injection enabled by default.
// Overrides the base class default_no_err_c constraint so that
// inject_err is freely randomisable and err_type is not forced to
// ERR_NONE.  Sequences that use this item must also call
// cfg.resolve_agent_configs() and set cfg.slave_cfg.enable_err_inject = 1
// so the slave driver acts on the knobs.
class axi_err_seq_item extends axi_seq_item;

  `uvm_object_utils(axi_err_seq_item)

  // Re-declare constraint to release the base-class "always off" lock.
  // inject_err is now freely randomisable; err_type must be non-NONE
  // whenever inject_err is asserted.
  constraint default_no_err_c {
    inject_err -> err_type != ERR_NONE;
    !inject_err -> err_type == ERR_NONE;
  }

  // By default weight inject_err=1 higher so errors appear frequently.
  constraint err_enable_c {
    inject_err dist { 1'b1 := 70, 1'b0 := 30 };
  }

  // When injecting, select uniformly among all real error types.
  constraint err_type_dist_c {
    if (inject_err)
      err_type inside { ERR_RESP, ERR_TIMEOUT, ERR_DATA_CORRUPT };
  }

  function new(string name = "axi_err_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    string base_str = super.convert2string();
    if (inject_err)
      return $sformatf("%s ERR=%s@beat%0d", base_str, err_type.name(), err_beat);
    return base_str;
  endfunction

endclass

`endif // AXI_ERR_SEQ_ITEM_SV
