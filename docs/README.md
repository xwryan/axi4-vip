# AXI VIP

UVM-based AXI4/AXI4-Lite Verification IP with Master/Slave agents, protocol checker, coverage, error injection, performance monitoring, and configurable backpressure.

## Directory Structure

```
rtl/           - AXI interface (axi_if.sv)
src/           - UVM components (types, config, agents, env, pkg)
seq_lib/       - Reusable sequences (single, burst, advanced)
error_inject/  - Error injection sequences
checker/       - SVA protocol checker and bind file
test/          - Test library (base test, smoke test, testbench top)
docs/          - Documentation and plans
```

## Quick Start

### Prerequisites

- SystemVerilog simulator: VCS, Xcelium, or Questa
- UVM 1.2 or later

### Compile and Run (VCS, default)

```bash
make run
```

### Compile and Run with a specific tool

```bash
make run TOOL=xcelium
make run TOOL=questa
```

### Run a specific test with a fixed seed

```bash
make run TEST=axi_smoke_test SEED=12345
```

### Compile only

```bash
make compile
```

### Clean build artifacts

```bash
make clean
```

## Integration

See [INTEGRATION.md](INTEGRATION.md) for complete DUT signal wiring, compile
order, validation rules, multi-port construction, analysis routing, and exact
regression commands.

### Interface ownership contract

`axi_if` separates the public resolved AXI nets from role-private VIP drive
proxies. Follow these rules for every physical link:

- Connect DUT ports only to public signals such as `awvalid` and `awready`.
- Active VIP drivers claim and drive the appropriate role-private proxies
  automatically.
- A custom component using `axi_if.master_mp` or `axi_if.slave_mp` can call the
  matching claim/release tasks through that modport before driving the existing
  `master_cb` or `slave_cb` clockvars.
- Passive and disabled roles remain at high impedance and do not drive DUT
  outputs.
- Prefer module ports when a testbench module emulates an external endpoint.
  A class-based synthetic fixture must first call `claim_master_drive()` or
  `claim_slave_drive()` and then write `master_*` or `slave_*` proxies.
- Never procedurally assign a public AXI net from a class.
- A resolved `X` means that two same-direction producers are connected to the
  same physical link.

The normal DUT topologies are:

```text
master_agent -> axi_if public nets -> DUT slave port
slave_agent  <- axi_if public nets <- DUT master port
```

| VIP role | VIP-produced public signals | Signals sampled from DUT/peer |
|---|---|---|
| Master | AW payload/`awvalid`, W payload/`wvalid`, `bready`, AR payload/`arvalid`, `rready` | `awready`, `wready`, B payload/`bvalid`, `arready`, R payload/`rvalid` |
| Slave | `awready`, `wready`, B payload/`bvalid`, `arready`, R payload/`rvalid` | AW payload/`awvalid`, W payload/`wvalid`, `bready`, AR payload/`arvalid`, `rready` |

Do not configure two Master drivers on one `axi_if`. Multiple Master ports use
multiple `axi_env`/`axi_if` pairs.

The shipped out-of-box VIP path supports only axi_if's default specialization: DATA_WIDTH=64, ADDR_WIDTH=32, ID_WIDTH=4, USER_WIDTH=0.
USER signals are not driven or monitored by the VIP.
Non-default widths or USER support require parameterizing the virtual-interface/type chain and implementing USER transaction and channel support.

| Use case | `master_cfg` | `slave_cfg` | Built-in scoreboard |
|----------|--------------|-------------|---------------------|
| VIP self-test | `enabled=1`, `is_active=UVM_ACTIVE` | `enabled=1`, `is_active=UVM_ACTIVE` | On |
| VIP Master to Slave DUT | `enabled=1`, `is_active=UVM_ACTIVE` | `enabled=0` | Off |
| Master DUT to VIP Slave | `enabled=0` | `enabled=1`, `is_active=UVM_ACTIVE` | Off |

Always call `cfg.resolve_agent_configs()` before changing `cfg.master_cfg` or
`cfg.slave_cfg`. Master-specific outstanding, bandwidth, and B/R backpressure
belong in `master_cfg`; Slave response delay, error injection, and AW/W/AR
backpressure belong in `slave_cfg`. Do not use the legacy `role` or common
endpoint fields to select topology.

Use one `axi_env`, one independent `axi_config`, and one `virtual axi_if` per
physical AXI port. Multiple Master ports require multiple environments; use a
system-level predictor/reference model for shared address spaces because the
built-in scoreboard does not compare across environments.

## Available Tests

| Test | Description |
|------|-------------|
| `axi_smoke_test` | Basic single read/write transactions |
| `axi_high_traffic_test` | Sustained mixed traffic; defaults to 20,000 transactions, 32 outstanding, burst 16 |

## Key Features

- **Master Agent**: 5-channel concurrent AXI driver with full burst support
- **Slave Agent**: Configurable response latency and backpressure
- **Protocol Checker**: explicitly instantiated in test/tb_top.sv and connected to the same axi_if; has_protocol_check is configuration/topology intent and does not instantiate the SystemVerilog module. External integrations may explicitly instantiate the checker or provide their own bind, but must not use both.
- **Scoreboard**: Write/read data integrity checking via reference memory model
- **Coverage**: Functional coverage for transaction types, burst lengths, sizes, and responses
- **Error Injection**: Response errors, timeouts, and data corruption sequences
- **Performance Monitor**: Throughput and latency tracking with configurable thresholds
- **Backpressure**: Sliding-window bandwidth limiter with random READY generation
