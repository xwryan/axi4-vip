# AXI VIP Integration Guide

This guide is the engineering entry point for integrating the VIP with a real
DUT. It covers compilation, signal wiring, endpoint configuration, analysis
routing, multi-port construction, and the permanent regression commands.

## 1. Prerequisites and compile order

The default flow requires GNU Make, Bash, a SystemVerilog simulator, and UVM
1.2 or later. For VCS, make sure the VCS executable and license environment are
available; the Makefile selects the bundled UVM 1.2 library with
`-ntb_opts uvm-1.2`. Xcelium and Questa are also supported by the Makefile, but
the permanent regression runner currently executes the VCS-style `simv`
binary.

Do not guess the source order. From the repository root, query it with:

```bash
make -s print-sources TOOL=vcs
```

The current output, and therefore the required top-level compile order, is:

```text
rtl/axi_if.sv src/axi_types.sv src/axi_pkg.sv checker/axi_protocol_checker.sv test/tb_top.sv
```

`src/axi_pkg.sv` then includes the config classes first, the transaction and
reference-model classes, Master components, Slave components, subscribers and
`axi_env`, followed by sequences and tests. The `+incdir+src`,
`+incdir+seq_lib`, `+incdir+error_inject`, and `+incdir+test` options in the
Makefile are consequently required. `checker/axi_checker_bind.sv` is not in the
VCS source list: `test/tb_top.sv` directly instantiates the checker because the
supported VCS flow cannot bind to an interface.

The checker is explicitly instantiated in test/tb_top.sv and connected to the same axi_if.
has_protocol_check is configuration/topology intent and does not instantiate the SystemVerilog module.

The shipped out-of-box VIP path supports only axi_if's default specialization: DATA_WIDTH=64, ADDR_WIDTH=32, ID_WIDTH=4, USER_WIDTH=0.
USER signals are not driven or monitored by the VIP.
Non-default widths or USER support require parameterizing the virtual-interface/type chain and implementing USER transaction and channel support.

## 2. Connect one DUT port

Create exactly one `axi_if` for each physical AXI port. The following template
is based on `test/tb_top.sv` and connects every non-USER AXI4 signal to a DUT
Slave port. Replace only `my_axi_slave_dut` and its port prefixes to match the
DUT. Keep the shown 64-bit data, 32-bit address, 4-bit ID, and zero-width USER
parameters for the shipped path. Although `axi_if` can generate USER nets when
`USER_WIDTH>0`, the current VIP does not put them in its clocking blocks or
modports and does not represent them in transactions, drivers, or monitors.

```systemverilog
module tb_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi_pkg::*;

  localparam int DATA_WIDTH = 64;
  localparam int ADDR_WIDTH = 32;
  localparam int ID_WIDTH   = 4;

  logic aclk;
  logic aresetn;

  initial aclk = 1'b0;
  always #625ps aclk = ~aclk;
  initial begin
    aresetn = 1'b0;
    repeat (10) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;
  end

  axi_if #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ID_WIDTH  (ID_WIDTH),
    .USER_WIDTH(0)
  ) axi_bus (
    .aclk(aclk),
    .aresetn(aresetn)
  );

  my_axi_slave_dut u_dut (
    .aclk          (aclk),
    .aresetn       (aresetn),

    // AW: Master to Slave, except AWREADY
    .s_axi_awid    (axi_bus.awid),
    .s_axi_awaddr  (axi_bus.awaddr),
    .s_axi_awlen   (axi_bus.awlen),
    .s_axi_awsize  (axi_bus.awsize),
    .s_axi_awburst (axi_bus.awburst),
    .s_axi_awlock  (axi_bus.awlock),
    .s_axi_awcache (axi_bus.awcache),
    .s_axi_awprot  (axi_bus.awprot),
    .s_axi_awqos   (axi_bus.awqos),
    .s_axi_awregion(axi_bus.awregion),
    .s_axi_awvalid (axi_bus.awvalid),
    .s_axi_awready (axi_bus.awready),

    // W: Master to Slave, except WREADY
    .s_axi_wdata   (axi_bus.wdata),
    .s_axi_wstrb   (axi_bus.wstrb),
    .s_axi_wlast   (axi_bus.wlast),
    .s_axi_wvalid  (axi_bus.wvalid),
    .s_axi_wready  (axi_bus.wready),

    // B: Slave to Master, except BREADY
    .s_axi_bid     (axi_bus.bid),
    .s_axi_bresp   (axi_bus.bresp),
    .s_axi_bvalid  (axi_bus.bvalid),
    .s_axi_bready  (axi_bus.bready),

    // AR: Master to Slave, except ARREADY
    .s_axi_arid    (axi_bus.arid),
    .s_axi_araddr  (axi_bus.araddr),
    .s_axi_arlen   (axi_bus.arlen),
    .s_axi_arsize  (axi_bus.arsize),
    .s_axi_arburst (axi_bus.arburst),
    .s_axi_arlock  (axi_bus.arlock),
    .s_axi_arcache (axi_bus.arcache),
    .s_axi_arprot  (axi_bus.arprot),
    .s_axi_arqos   (axi_bus.arqos),
    .s_axi_arregion(axi_bus.arregion),
    .s_axi_arvalid (axi_bus.arvalid),
    .s_axi_arready (axi_bus.arready),

    // R: Slave to Master, except RREADY
    .s_axi_rid     (axi_bus.rid),
    .s_axi_rdata   (axi_bus.rdata),
    .s_axi_rresp   (axi_bus.rresp),
    .s_axi_rlast   (axi_bus.rlast),
    .s_axi_rvalid  (axi_bus.rvalid),
    .s_axi_rready  (axi_bus.rready)
  );

  axi_protocol_checker #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ID_WIDTH  (ID_WIDTH)
  ) u_axi_checker (
    .aclk(aclk), .aresetn(aresetn),
    .awid(axi_bus.awid), .awaddr(axi_bus.awaddr),
    .awlen(axi_bus.awlen), .awsize(axi_bus.awsize),
    .awburst(axi_bus.awburst), .awlock(axi_bus.awlock),
    .awcache(axi_bus.awcache), .awprot(axi_bus.awprot),
    .awqos(axi_bus.awqos), .awregion(axi_bus.awregion),
    .awvalid(axi_bus.awvalid), .awready(axi_bus.awready),
    .wdata(axi_bus.wdata), .wstrb(axi_bus.wstrb),
    .wlast(axi_bus.wlast), .wvalid(axi_bus.wvalid),
    .wready(axi_bus.wready),
    .bid(axi_bus.bid), .bresp(axi_bus.bresp),
    .bvalid(axi_bus.bvalid), .bready(axi_bus.bready),
    .arid(axi_bus.arid), .araddr(axi_bus.araddr),
    .arlen(axi_bus.arlen), .arsize(axi_bus.arsize),
    .arburst(axi_bus.arburst), .arlock(axi_bus.arlock),
    .arcache(axi_bus.arcache), .arprot(axi_bus.arprot),
    .arqos(axi_bus.arqos), .arregion(axi_bus.arregion),
    .arvalid(axi_bus.arvalid), .arready(axi_bus.arready),
    .rid(axi_bus.rid), .rdata(axi_bus.rdata),
    .rresp(axi_bus.rresp), .rlast(axi_bus.rlast),
    .rvalid(axi_bus.rvalid), .rready(axi_bus.rready)
  );

  initial begin
    uvm_config_db #(virtual axi_if)::set(
      null, "uvm_test_top", "vif", axi_bus);
    run_test();
  end
endmodule
```

The scope is significant: `axi_base_test` performs
`get(this, "", "vif", cfg.vif)`, so the single-environment top publishes field
`vif` to `uvm_test_top`. The test copies that handle into `axi_config.vif`; the
environment gives the same config object to its agents, drivers, and monitors.
A `virtual axi_if` is a handle to this physical interface, not a second bus.

For a Master DUT connected to the VIP Slave, use the same complete signal map
with the DUT's `m_axi_*` ports. The net directions reverse at the DUT boundary,
but the `axi_bus.<signal>` names and VIP configuration do not change.

### 2.1 Public-net and role-proxy ownership

The 39 non-USER public signals in `axi_if` are resolved nets. VIP drivers do
not write those nets procedurally; they claim a role and drive private proxies
that feed the public nets. This keeps an unused clocking block from becoming a
second static driver at a real DUT boundary.

Apply this ownership contract to every interface instance:

- Connect DUT ports only to public `axi_if` signals such as `awvalid` and
  `awready`. Never connect a DUT port to a `master_*` or `slave_*` proxy.
- An active VIP Master or Slave driver claims its proxy direction
  automatically for its `run_phase` lifetime.
- A custom module or component using `axi_if.master_mp` or `axi_if.slave_mp`
  may invoke the matching claim/release tasks through that modport. Claim
  before driving the existing `master_cb` or `slave_cb` clockvars.
- A passive or disabled role contributes high impedance and therefore does
  not mask a DUT output.
- Prefer module ports for testbench modules that emulate external endpoints.
  A class-based synthetic fixture must explicitly call
  `claim_master_drive()` or `claim_slave_drive()`, write only the matching
  `master_*` or `slave_*` proxies, and call the release task when its finite
  drive lifetime ends.
- Monitors, checkers, DUTs, and fixture handshake observations always read the
  public resolved nets.
- Never procedurally assign a public AXI net from a class. If two
  same-direction producers are connected by mistake, the public net resolves
  to `X`; treat that as an integration error.

The two normal DUT topologies are:

```text
master_agent -> axi_if public nets -> DUT slave port
slave_agent  <- axi_if public nets <- DUT master port
```

| VIP role | VIP-produced public signals | Signals sampled from DUT/peer |
|---|---|---|
| Master | AW payload/`awvalid`, W payload/`wvalid`, `bready`, AR payload/`arvalid`, `rready` | `awready`, `wready`, B payload/`bvalid`, `arready`, R payload/`rvalid` |
| Slave | `awready`, `wready`, B payload/`bvalid`, `arready`, R payload/`rvalid` | AW payload/`awvalid`, W payload/`wvalid`, `bready`, AR payload/`arvalid`, `rready` |

One `axi_if` represents one physical link and accepts at most one VIP Master
producer and one VIP Slave producer. Do not configure two Master drivers on
one interface. Multiple Master ports require multiple interface/environment
pairs, as shown in Section 5.

## 3. Configure endpoint topology

Call `resolve_agent_configs()` before changing endpoint fields. It creates
independent `master_cfg` and `slave_cfg` objects and copies legacy common
settings once. After that call, change only the endpoint objects; later changes
to legacy fields such as `cfg.max_outstanding_rd`, `cfg.resp_delay_min`, or
`cfg.aw_bp_cfg` are not re-copied. The legacy `cfg.role` field does not select
which agent `axi_env` builds.

Each snippet below is a compilable `configure_test()` override in a class that
extends `axi_base_test`.

### 3.1 Self-test: VIP Master and VIP Slave active

```systemverilog
virtual function void configure_test();
  super.configure_test();
  cfg.resolve_agent_configs();
  cfg.master_cfg.enabled   = 1;
  cfg.master_cfg.is_active = UVM_ACTIVE;
  cfg.slave_cfg.enabled    = 1;
  cfg.slave_cfg.is_active  = UVM_ACTIVE;
  cfg.has_scoreboard       = 1;
  cfg.has_coverage         = 1;
  cfg.has_protocol_check   = 1;
endfunction
```

### 3.2 VIP Master to a Slave DUT

```systemverilog
virtual function void configure_test();
  super.configure_test();
  cfg.resolve_agent_configs();
  cfg.master_cfg.enabled   = 1;
  cfg.master_cfg.is_active = UVM_ACTIVE;
  cfg.slave_cfg.enabled    = 0;
  cfg.slave_cfg.is_active  = UVM_PASSIVE;
  cfg.has_scoreboard       = 0;
  cfg.has_coverage         = 1;
  cfg.has_protocol_check   = 1;
endfunction
```

Start sequences on `env.master_agent.sequencer`. The DUT supplies AW/W/AR
READY and B/R responses. Disable the built-in scoreboard because it is a
single-bus memory-consistency model, not a predictor for an arbitrary DUT.

### 3.3 Master DUT to the VIP Slave

```systemverilog
virtual function void configure_test();
  super.configure_test();
  cfg.resolve_agent_configs();
  cfg.master_cfg.enabled   = 0;
  cfg.master_cfg.is_active = UVM_PASSIVE;
  cfg.slave_cfg.enabled    = 1;
  cfg.slave_cfg.is_active  = UVM_ACTIVE;
  cfg.has_scoreboard       = 0;
  cfg.has_coverage         = 1;
  cfg.has_protocol_check   = 1;
endfunction
```

The DUT supplies AW/W/AR and B/R READY. The VIP Slave drives AW/W/AR READY and
B/R responses. Configure its response, error, and request-channel
backpressure knobs in `slave_cfg`.

### 3.4 Checker-only (no UVM endpoint)

```systemverilog
virtual function void configure_test();
  super.configure_test();
  cfg.resolve_agent_configs();
  cfg.master_cfg.enabled   = 0;
  cfg.master_cfg.is_active = UVM_PASSIVE;
  cfg.slave_cfg.enabled    = 0;
  cfg.slave_cfg.is_active  = UVM_PASSIVE;
  cfg.has_scoreboard       = 0;
  cfg.has_coverage         = 0;
  cfg.has_protocol_check   = 1;
endfunction
```

This is checker-only rather than an enabled passive agent: there is no UVM
monitor, analysis source, or performance monitor. `has_protocol_check` records
the configuration intent and makes this topology valid; it does not create or
gate RTL. Keep the explicit `axi_protocol_checker` instance in the top. To
observe traffic through UVM instead, enable either endpoint and set its
`is_active=UVM_PASSIVE`; that creates a monitor without a driver or sequencer.

## 4. Endpoint knob reference

The endpoint objects are independent. The common `axi_config` records bus-shape
metadata (`mode`, `data_width`, `addr_width`, `id_width`, `user_width`), optional
subscriber switches (`has_scoreboard`, `has_coverage`,
`has_protocol_check`), and `vif`. Those width fields do not parameterize the
current `virtual axi_if` type chain and must remain 64/32/4/0 in the shipped
flow.

| Object | Field | Default | Meaning |
|---|---|---:|---|
| `master_cfg` | `enabled` / `is_active` | `1` / `UVM_ACTIVE` | Build the Master monitor; active also builds its driver and sequencer. |
| `master_cfg` | `max_outstanding_rd`, `max_outstanding_wr` | `16`, `16` | Independent nonzero read/write outstanding limits. |
| `master_cfg` | `enable_bw_limit` | `0` | Enable Master request throttling. |
| `master_cfg` | `max_bytes_per_window`, `bw_window_cycles` | `1024`, `100` | Nonzero bandwidth allowance and window when limiting is enabled. |
| `master_cfg` | `per_channel_bp_enable` | `0` | Select independent B/R READY policies instead of `global_bp_cfg`. |
| `master_cfg` | `b_bp_cfg`, `r_bp_cfg`, `global_bp_cfg` | `BP_NONE` | Master-side response-channel backpressure. There are no Master AW/W/AR backpressure objects. |
| `slave_cfg` | `enabled` / `is_active` | `1` / `UVM_ACTIVE` | Build the Slave monitor; active also builds its driver and sequencer. |
| `slave_cfg` | `resp_delay_min`, `resp_delay_max` | `0`, `10` | Inclusive Slave response-delay range; minimum must not exceed maximum. |
| `slave_cfg` | `enable_err_inject` | `0` | Allow Slave response/data/timeout injection requested by an error sequence item. |
| `slave_cfg` | `per_channel_bp_enable` | `0` | Select independent AW/W/AR READY policies instead of `global_bp_cfg`. |
| `slave_cfg` | `aw_bp_cfg`, `w_bp_cfg`, `ar_bp_cfg`, `global_bp_cfg` | `BP_NONE` | Slave-side request-channel backpressure. There are no Slave B/R backpressure objects. |
| any `axi_bp_config` | `mode` | `BP_NONE` | `BP_NONE`, `BP_FIXED_DELAY`, `BP_RANDOM`, `BP_BURST`, `BP_INTERMITTENT`, or `BP_CUSTOM`. |
| any `axi_bp_config` | `fixed_delay` | `5` | Delay used by `BP_FIXED_DELAY`. |
| any `axi_bp_config` | `random_ready_pct` | `50` | READY percentage for `BP_RANDOM`; valid range is 0 through 100. |
| any `axi_bp_config` | `burst_accept_cycles`, `burst_block_cycles` | `8`, `4` | Both must be nonzero for `BP_BURST`. |
| any `axi_bp_config` | `on_window`, `off_window` | `20`, `5` | Both must be nonzero for `BP_INTERMITTENT`. |

An example with independent policies is:

```systemverilog
cfg.resolve_agent_configs();
cfg.master_cfg.per_channel_bp_enable = 1;
cfg.master_cfg.b_bp_cfg.mode = BP_RANDOM;
cfg.master_cfg.b_bp_cfg.random_ready_pct = 75;
cfg.master_cfg.r_bp_cfg.mode = BP_FIXED_DELAY;
cfg.master_cfg.r_bp_cfg.fixed_delay = 3;

cfg.slave_cfg.per_channel_bp_enable = 1;
cfg.slave_cfg.aw_bp_cfg.mode = BP_BURST;
cfg.slave_cfg.aw_bp_cfg.burst_accept_cycles = 8;
cfg.slave_cfg.aw_bp_cfg.burst_block_cycles  = 4;
cfg.slave_cfg.w_bp_cfg.mode = BP_RANDOM;
cfg.slave_cfg.w_bp_cfg.random_ready_pct = 60;
cfg.slave_cfg.ar_bp_cfg.mode = BP_INTERMITTENT;
cfg.slave_cfg.ar_bp_cfg.on_window  = 20;
cfg.slave_cfg.ar_bp_cfg.off_window = 5;
```

`axi_env::build_phase` calls `cfg.validate(reason)` and reports
`UVM_FATAL [CFG] axi_env: invalid configuration: <reason>` on failure. Invalid
enabled configurations include: a null `vif`; zero Master read or write
outstanding limit; enabled bandwidth limiting with zero bytes or cycles;
reversed Slave response delays; a random READY percentage above 100; a zero
accept/block window in `BP_BURST`; a zero on/off window in
`BP_INTERMITTENT`; and an invalid backpressure enum. When both endpoints are
disabled, scoreboard or coverage is illegal because there is no endpoint
monitor, and disabling the protocol-check intent too produces an empty invalid
environment. Knobs belonging to a disabled endpoint are dormant and are not
validated.

The diagnostic text identifies the failing scope. The stable reasons include
`an enabled endpoint requires a virtual interface`,
`master outstanding read and write limits must be nonzero`,
`master bandwidth limit requires nonzero bytes and cycles`, and
`scoreboard or coverage requires an enabled endpoint monitor`. Delay failures
report `slave response delay minimum <min> exceeds maximum <max>`; channel
policy failures are prefixed with `master B`, `master R`, `slave AW`,
`slave W`, or `slave AR` and name the invalid percentage, window, or enum.
With both endpoints and the protocol-check intent disabled, validation reports
`environment must enable an endpoint or protocol checker`.

## 5. Multiple physical ports and environments

The rule is one physical AXI interface per `axi_env`. Therefore two Master
ports and one Slave port require three interface instances, three independent
`axi_config` objects, and three environments. Publish each interface with a
different field name and the test path scope:

```systemverilog
initial begin
  uvm_config_db #(virtual axi_if)::set(
    null, "uvm_test_top", "m0_vif", m0_bus);
  uvm_config_db #(virtual axi_if)::set(
    null, "uvm_test_top", "m1_vif", m1_bus);
  uvm_config_db #(virtual axi_if)::set(
    null, "uvm_test_top", "s0_vif", s0_bus);
  run_test();
end
```

Use a custom test derived directly from `uvm_test` so it can construct and
scope all three environments:

```systemverilog
class three_port_test extends uvm_test;
  `uvm_component_utils(three_port_test)

  axi_env m0_env, m1_env, s0_env;
  axi_config m0_cfg, m1_cfg, s0_cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  protected function axi_config make_port_cfg(
    string name, virtual axi_if vif, bit master_enabled, bit slave_enabled);
    axi_config port_cfg = axi_config::type_id::create(name);
    port_cfg.vif = vif;
    port_cfg.resolve_agent_configs();
    port_cfg.master_cfg.enabled   = master_enabled;
    port_cfg.master_cfg.is_active = UVM_ACTIVE;
    port_cfg.slave_cfg.enabled    = slave_enabled;
    port_cfg.slave_cfg.is_active  = UVM_ACTIVE;
    port_cfg.has_scoreboard       = 0;
    port_cfg.has_coverage         = 1;
    port_cfg.has_protocol_check   = 1;
    return port_cfg;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual axi_if m0_vif, m1_vif, s0_vif;
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "m0_vif", m0_vif))
      `uvm_fatal("CFG", "m0_vif not found")
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "m1_vif", m1_vif))
      `uvm_fatal("CFG", "m1_vif not found")
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "s0_vif", s0_vif))
      `uvm_fatal("CFG", "s0_vif not found")

    m0_cfg = make_port_cfg("m0_cfg", m0_vif, 1, 0);
    m1_cfg = make_port_cfg("m1_cfg", m1_vif, 1, 0);
    s0_cfg = make_port_cfg("s0_cfg", s0_vif, 0, 1);

    uvm_config_db #(axi_config)::set(this, "m0_env", "cfg", m0_cfg);
    uvm_config_db #(axi_config)::set(this, "m1_env", "cfg", m1_cfg);
    uvm_config_db #(axi_config)::set(this, "s0_env", "cfg", s0_cfg);
    m0_env = axi_env::type_id::create("m0_env", this);
    m1_env = axi_env::type_id::create("m1_env", this);
    s0_env = axi_env::type_id::create("s0_env", this);
  endfunction
endclass
```

Also instantiate one protocol checker per physical interface at the top. Never
attach multiple `axi_env` instances to the same physical bus to represent
multiple Masters. Multiple Master ports mean multiple environments. The
built-in scoreboard never compares traffic across environments. If the ports
share an address space, add a system-level predictor/reference model above the
environments, subscribe it to the required analysis ports, and define ordering
and coherency rules there.

## 6. Analysis source and scoreboard boundary

`enabled`, rather than `is_active`, controls whether an endpoint monitor
exists. An active endpoint adds driver and sequencer; a passive endpoint keeps
the identical monitor and analysis ports. `axi_env` chooses exactly one
`analysis_monitor`:

| Topology | Analysis source | Subscribers |
|---|---|---|
| Both endpoints enabled, active or passive | Master monitor | Optional scoreboard/coverage and the performance monitor |
| Master-only | Master monitor | Optional scoreboard/coverage and the performance monitor |
| Slave-only | Slave monitor (it extends the Master monitor) | Optional scoreboard/coverage and the performance monitor |
| Checker-only, both endpoints disabled | None | Scoreboard/coverage forbidden; no performance monitor |

The selected monitor sends write-commit snapshots, read-request snapshots, and
completed transactions. The built-in scoreboard updates an internal expected
memory at completed writes and snapshots expected read data at AR. It is useful
for a memory-like, single-interface ordering model such as the VIP self-test.
It does not understand DUT register side effects, transformations, bridges,
interconnect arbitration, coherency, or traffic observed in another `axi_env`.
Disable it for the two real-DUT examples above unless that exact memory model
is valid; connect a DUT-aware predictor or system reference model instead.

The RTL protocol checker observes the physical interface independently of UVM
analysis routing. Active, passive, Master-only, Slave-only, and checker-only
topologies can all retain protocol checking as long as the top instantiates the
checker for that interface.

## 7. Run and regression commands

Smoke test with an explicit seed:

```bash
make run TOOL=vcs TEST=axi_smoke_test SEED=1
```

Run the permanent 16-test regression matrix:

```bash
make regress TOOL=vcs
```

Run the high-traffic test with explicit defaults (20,000 transactions,
outstanding window 32, maximum burst 16):

```bash
make run TOOL=vcs TEST=axi_high_traffic_test SEED=1402 RUN_ARGS='+AXI_TRAFFIC_TXNS=20000 +AXI_TRAFFIC_OUTSTANDING=32 +AXI_TRAFFIC_BURST_MAX=16'
```

Run the standalone checker rule matrix:

```bash
make checker-regress TOOL=vcs
```

`axi_high_traffic_test` defaults to the same permanent-matrix values
20,000/32/16, so `make regress TOOL=vcs` needs no extra arguments. Its override
rules are strict:

- `AXI_TRAFFIC_TXNS` must be at least 4.
- `AXI_TRAFFIC_OUTSTANDING` must be at least 2.
- `AXI_TRAFFIC_BURST_MAX` must be exactly 1, 4, 8, or 16.
- Values must be non-empty ASCII decimal digits `0` through `9`; signs,
  whitespace, prefixes, and non-ASCII digits are rejected.
- Repeating the same plusarg, specifying it without a value, or overflowing
  unsigned 32-bit decimal (`4294967295` maximum) is fatal.

`RUN_ARGS` is appended once by each supported simulator run command. Quote the
Make value as shown so all three plusargs remain one shell argument to Make and
are then expanded as three simulator arguments.
