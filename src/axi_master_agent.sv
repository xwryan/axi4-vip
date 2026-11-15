`ifndef AXI_MASTER_AGENT_SV
`define AXI_MASTER_AGENT_SV

class axi_master_agent extends uvm_agent;

  `uvm_component_utils(axi_master_agent)

  axi_config             cfg;
  axi_master_config      agent_cfg;
  axi_master_driver      driver;
  axi_master_sequencer   sequencer;
  axi_master_monitor     monitor;

  uvm_analysis_port #(axi_seq_item) item_collected_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null)
      `uvm_fatal("CFG", "axi_master_agent: common config is null")
    if (agent_cfg == null)
      `uvm_fatal("CFG", "axi_master_agent: master config is null")
    if (cfg.vif == null)
      `uvm_fatal("CFG", "axi_master_agent: virtual interface is null")

    monitor     = axi_master_monitor::type_id::create("monitor", this);
    monitor.cfg = cfg;
    monitor.vif = cfg.vif;
    if (is_active == UVM_ACTIVE) begin
      driver           = axi_master_driver::type_id::create("driver", this);
      driver.cfg       = cfg;
      driver.agent_cfg = agent_cfg;
      driver.vif       = cfg.vif;
      sequencer        = axi_master_sequencer::type_id::create("sequencer", this);
      sequencer.cfg    = cfg;
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    item_collected_port = monitor.item_collected_port;
    if (is_active == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass

`endif // AXI_MASTER_AGENT_SV
