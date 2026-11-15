`ifndef AXI_SLAVE_MONITOR_SV
`define AXI_SLAVE_MONITOR_SV

class axi_slave_monitor extends axi_master_monitor;

  `uvm_component_utils(axi_slave_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass

`endif // AXI_SLAVE_MONITOR_SV
