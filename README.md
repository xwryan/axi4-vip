# AXI4 UVM VIP

Reusable SystemVerilog/UVM AXI4 verification IP with independently configurable
Master and Slave agents, protocol checking, scoreboarding, coverage,
performance monitoring, and sustained-traffic regression.

- [Usage and feature guide](docs/README.md)
- [DUT integration and configuration](docs/INTEGRATION.md)
- [Architecture and usage handbook](docs/AXI_VIP_Architecture_and_Usage.docx)

Connect DUT ports only to the public signals of `axi_if`. Active VIP drivers
automatically claim their role-private proxies; passive and disabled roles stay
at high impedance. A resolved `X` indicates that two same-direction producers
are connected to the same physical link.

Use one `axi_env`, one independent `axi_config`, and one `axi_if` for each
physical AXI link. A design with multiple Master ports creates one
environment/interface pair per port; coordinate them with a system-level
virtual sequence and predictor when they share an address space.

```bash
make compile TOOL=vcs
make regress TOOL=vcs
make checker-regress TOOL=vcs
```

VCS regression requires UVM 1.2 and a valid simulator license.
