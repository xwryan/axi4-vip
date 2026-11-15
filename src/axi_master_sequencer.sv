`ifndef AXI_MASTER_SEQUENCER_SV
`define AXI_MASTER_SEQUENCER_SV

class axi_master_sequencer extends uvm_sequencer #(axi_seq_item);

  `uvm_component_utils(axi_master_sequencer)

  axi_config cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass

`endif // AXI_MASTER_SEQUENCER_SV
