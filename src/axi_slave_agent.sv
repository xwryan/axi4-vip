`ifndef AXI_SLAVE_AGENT_SV
`define AXI_SLAVE_AGENT_SV

class axi_slave_agent extends uvm_agent;

  `uvm_component_utils(axi_slave_agent)

  axi_config           cfg;
  axi_slave_config     agent_cfg;
  axi_slave_driver     driver;
  axi_slave_sequencer  sequencer;
  axi_slave_monitor    monitor;
  axi_ref_model        ref_mem;

  uvm_analysis_port #(axi_seq_item) item_collected_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null)
      `uvm_fatal("CFG", "axi_slave_agent: common config is null")
    if (agent_cfg == null)
      `uvm_fatal("CFG", "axi_slave_agent: slave config is null")
    if (cfg.vif == null)
      `uvm_fatal("CFG", "axi_slave_agent: virtual interface is null")

    monitor     = axi_slave_monitor::type_id::create("monitor", this);
    monitor.cfg = cfg;
    monitor.vif = cfg.vif;
    if (is_active == UVM_ACTIVE) begin
      driver           = axi_slave_driver::type_id::create("driver", this);
      driver.cfg       = cfg;
      driver.agent_cfg = agent_cfg;
      driver.vif       = cfg.vif;
      driver.ref_mem   = ref_mem;
      sequencer        = axi_slave_sequencer::type_id::create("sequencer", this);
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

`endif // AXI_SLAVE_AGENT_SV
