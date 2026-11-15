#!/usr/bin/env python3
"""Focused tests for the SystemVerilog AXI drive-ownership scanner."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCANNER_PATH = REPO_ROOT / "scripts" / "tests" / "axi_drive_ownership_scan.py"


class AxiDriveOwnershipScannerTest(unittest.TestCase):
    def load_scanner(self):
        self.assertTrue(SCANNER_PATH.is_file(), "ownership scanner helper is missing")
        spec = importlib.util.spec_from_file_location("axi_drive_ownership_scan", SCANNER_PATH)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_detects_no_space_blocking_assignment(self):
        scanner = self.load_scanner()
        text = "virtual axi_if alternate_bus;\nalternate_bus.awvalid=1'b1;\n"

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([(2, "alternate_bus.awvalid", "=")], writes)

    def test_detects_tabbed_nonblocking_assignment(self):
        scanner = self.load_scanner()
        text = "virtual axi_if alternate_bus;\nalternate_bus.awready\t<=\t1'b1;\n"

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([(2, "alternate_bus.awready", "<=")], writes)

    def test_detects_parameterized_comma_declared_second_handle(self):
        scanner = self.load_scanner()
        text = """
virtual axi_if #(.DATA_WIDTH(64), .ID_WIDTH(8)) first_bus, second_bus;
second_bus.wvalid = 1'b1;
"""

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([(3, "second_bus.wvalid", "=")], writes)

    def test_detects_this_qualified_typed_handle(self):
        scanner = self.load_scanner()
        text = "virtual axi_if bus;\nthis.bus.awvalid = 1'b1;\n"

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([(2, "this.bus.awvalid", "=")], writes)

    def test_detects_explicit_nested_root(self):
        scanner = self.load_scanner()
        text = "cfg.vif.wvalid = 1'b1;\n"

        writes = scanner.find_procedural_writes(text, roots=("cfg.vif",))

        self.assertEqual([(1, "cfg.vif.wvalid", "=")], writes)

    def test_ignores_non_interface_objects_with_axi_named_fields(self):
        scanner = self.load_scanner()
        text = "axi_seq_item request;\nrequest.rdata = new[0];\n"

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([], writes)

    def test_distinguishes_relational_from_nonblocking_assignment(self):
        scanner = self.load_scanner()
        text = """
virtual axi_if bus;
if (bus.awlen <= maximum) result = 1;
result = bus.awlen <= maximum;
return bus.awlen <= maximum;
if (ready) bus.awlen <= value;
"""

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([(6, "bus.awlen", "<=")], writes)

    def test_detects_compound_and_increment_decrement_writes(self):
        scanner = self.load_scanner()
        text = """
virtual axi_if bus;
bus.awlen += amount;
bus.awlen -= amount;
bus.awlen++;
--this.bus.awlen;
"""

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([
            (3, "bus.awlen", "+="),
            (4, "bus.awlen", "-="),
            (5, "bus.awlen", "++"),
            (6, "this.bus.awlen", "--"),
        ], writes)

    def test_detects_nonblocking_write_after_semicolon_free_uvm_macro(self):
        scanner = self.load_scanner()
        text = '''
virtual axi_if bus;
`uvm_info("TAG", $sformatf("value=%0d", value), UVM_HIGH)
bus.awready <= value;
'''

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([(4, "bus.awready", "<=")], writes)

    def test_detects_nonblocking_writes_in_case_variants(self):
        scanner = self.load_scanner()
        text = """
virtual axi_if bus;
case (selector)
  2'b00: bus.awlen <= value;
  default: begin : named_default
    bus.awvalid <= value;
  end
endcase
casez (selector)
  4'b1???: this.bus.awready <= value;
endcase
casex (selector)
  named_item: bus.wvalid <= value;
endcase
"""

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([
            (4, "bus.awlen", "<="),
            (6, "bus.awvalid", "<="),
            (10, "this.bus.awready", "<="),
            (13, "bus.wvalid", "<="),
        ], writes)

    def test_detects_nonblocking_writes_after_loop_and_event_controls(self):
        scanner = self.load_scanner()
        text = """
virtual axi_if bus;
for (int i = 0; i < 2; i++) bus.awlen <= value;
while (ready) bus.awvalid <= value;
repeat (2) bus.wvalid <= value;
@(posedge aclk) this.bus.bready <= value;
"""

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([
            (3, "bus.awlen", "<="),
            (4, "bus.awvalid", "<="),
            (5, "bus.wvalid", "<="),
            (6, "this.bus.bready", "<="),
        ], writes)

    def test_ignores_comments_strings_comparisons_and_continuous_assigns(self):
        scanner = self.load_scanner()
        text = r'''
virtual axi_if alternate_bus;
// alternate_bus.awvalid=1'b1;
/* alternate_bus.awready <= 1'b1; */
initial $display("alternate_bus.wvalid=1'b1;");
assign alternate_bus.awvalid = source_awvalid;
assign #(1) alternate_bus.awready = source_awready;
if (alternate_bus.awvalid == expected) result = 1;
if (alternate_bus.awvalid === expected) result = 1;
if (alternate_bus.awvalid != expected) result = 1;
if (alternate_bus.awvalid !== expected) result = 1;
if ((alternate_bus.awlen <= maximum)) result = 1;
'''

        writes = scanner.find_procedural_writes(text)

        self.assertEqual([], writes)

    def test_bare_scan_ignores_legal_continuous_assign(self):
        scanner = self.load_scanner()
        text = "assign awvalid = master_drive_enabled ? master_awvalid : 'z;\n"

        writes = scanner.find_procedural_writes(text, include_bare=True)

        self.assertEqual([], writes)

    def test_bare_scan_ignores_master_and_slave_clocking_bindings(self):
        scanner = self.load_scanner()
        text = """
clocking master_cb @(posedge aclk);
  output awid = master_awid;
endclocking
clocking slave_cb @(posedge aclk);
  output awready = slave_awready;
endclocking
"""

        writes = scanner.find_procedural_writes(text, include_bare=True)

        self.assertEqual([], writes)

    def test_bare_scan_ignores_multiline_clocking_bindings(self):
        scanner = self.load_scanner()
        text = """
clocking master_cb @(posedge aclk);
  output awid = master_awid,
         awaddr = master_awaddr,
         awvalid = master_awvalid;
endclocking
"""

        writes = scanner.find_procedural_writes(text, include_bare=True)

        self.assertEqual([], writes)

    def test_bare_scan_still_detects_assignment_in_interface_task(self):
        scanner = self.load_scanner()
        text = """
task automatic reset_signal(output logic temporary);
  awvalid = 1'b0;
endtask
"""

        writes = scanner.find_procedural_writes(text, include_bare=True)

        self.assertEqual([(3, "awvalid", "=")], writes)

    def test_comments_and_strings_do_not_change_clocking_spans(self):
        scanner = self.load_scanner()
        text = '''
// clocking fake_cb @(posedge aclk);
initial $display("endclocking output awvalid = master_awvalid");
clocking real_cb @(posedge aclk);
  // endclocking
  output awvalid = master_awvalid;
endclocking
task automatic reset_signal();
  awvalid = 1'b0;
endtask
'''

        writes = scanner.find_procedural_writes(text, include_bare=True)

        self.assertEqual([(9, "awvalid", "=")], writes)

    def test_interface_check_requires_exactly_one_expected_mapping(self):
        scanner = self.load_scanner()
        valid = """
wire logic awvalid;
assign\tawvalid = master_drive_enabled
                   ? master_awvalid
                   : 'z;
"""
        duplicate = valid + "assign #1 awvalid = slave_drive_enabled ? slave_awvalid : 'z;\n"
        wrong_role = """
wire logic awvalid;
assign awvalid = slave_drive_enabled ? slave_awvalid : 'z;
"""
        missing = "wire logic awvalid;\n"

        self.assertEqual([], scanner.check_interface_text(valid, {"master": ("awvalid",)}))
        self.assertIn("found 2", scanner.check_interface_text(
            duplicate, {"master": ("awvalid",)})[0])
        self.assertIn("wrong proxy assignment", scanner.check_interface_text(
            wrong_role, {"master": ("awvalid",)})[0])
        self.assertIn("found 0", scanner.check_interface_text(
            missing, {"master": ("awvalid",)})[0])

    def test_interface_check_requires_one_declaration_on_its_own_line(self):
        scanner = self.load_scanner()
        duplicate_declaration = """
wire logic awvalid;
wire logic awvalid;
assign awvalid = master_drive_enabled ? master_awvalid : 'z;
"""

        errors = scanner.check_interface_text(
            duplicate_declaration, {"master": ("awvalid",)})

        self.assertIn("found 2", errors[0])

    def test_all_39_role_mappings_form_a_valid_interface(self):
        scanner = self.load_scanner()
        lines = []
        for role, signals in scanner.ROLE_SIGNALS.items():
            for signal in signals:
                lines.append(f"wire logic {signal};")
                lines.append(
                    f"assign {signal} = {role}_drive_enabled ? {role}_{signal} : 'z;"
                )

        self.assertEqual(28, len(scanner.MASTER_SIGNALS))
        self.assertEqual(11, len(scanner.SLAVE_SIGNALS))
        self.assertEqual([], scanner.check_interface_text("\n".join(lines)))

    def test_missing_input_file_is_a_tool_error(self):
        self.assertTrue(SCANNER_PATH.is_file(), "ownership scanner helper is missing")
        with tempfile.TemporaryDirectory() as temp_dir:
            missing = Path(temp_dir) / "missing.sv"
            result = subprocess.run(
                ["python3", str(SCANNER_PATH), "scan-writes", str(missing)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(2, result.returncode)
        self.assertIn("ERROR:", result.stderr)

    def test_cli_distinguishes_clean_policy_and_tool_results(self):
        self.assertTrue(SCANNER_PATH.is_file(), "ownership scanner helper is missing")
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            clean = temp_path / "clean.sv"
            violation = temp_path / "violation.sv"
            missing = temp_path / "missing.sv"
            clean.write_text(
                "virtual axi_if bus;\nassign bus.awvalid = source;\n",
                encoding="utf-8",
            )
            violation.write_text(
                "virtual axi_if bus;\nbus.awvalid=1'b1;\n",
                encoding="utf-8",
            )

            statuses = []
            for path in (clean, violation, missing):
                result = subprocess.run(
                    ["python3", str(SCANNER_PATH), "scan-writes", str(path)],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                statuses.append(result.returncode)

        self.assertEqual([0, 3, 2], statuses)

    def test_cli_accepts_multiple_explicit_roots_for_one_file(self):
        self.assertTrue(SCANNER_PATH.is_file(), "ownership scanner helper is missing")
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = Path(temp_dir) / "nested.sv"
            fixture.write_text(
                "vif.awvalid=1'b1;\ncfg.vif.awready=1'b1;\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    "python3", str(SCANNER_PATH), "scan-writes",
                    "--root", "vif", "--root", "cfg.vif", str(fixture),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(3, result.returncode)
        self.assertIn("vif.awvalid", result.stdout)
        self.assertIn("cfg.vif.awready", result.stdout)


if __name__ == "__main__":
    unittest.main()
