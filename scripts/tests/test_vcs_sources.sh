#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
sources=$(make -s -C "$repo_root" print-sources TOOL=vcs)
regression_list="$repo_root/config/regression.list"
makefile="$repo_root/Makefile"
integration="$repo_root/docs/INTEGRATION.md"
readme="$repo_root/docs/README.md"
docx_generator="$repo_root/docs/gen_docx.py"
docx="$repo_root/docs/AXI_VIP_Architecture_and_Usage.docx"
doc_tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$doc_tmp_dir"' EXIT
failed=0

required_regressions=(
    axi_config_validation_test
    axi_topology_both_active_test
    axi_topology_master_active_slave_passive_test
    axi_topology_master_passive_slave_active_test
    axi_topology_master_only_test
    axi_topology_checker_only_test
    axi_outstanding_limit_test
    axi_outstanding_reset_test
    axi_high_traffic_test
)

required_regression_rows=(
    'axi_config_validation_test 1101 120'
    'axi_topology_both_active_test 1201 120'
    'axi_topology_master_active_slave_passive_test 1202 120'
    'axi_topology_master_passive_slave_active_test 1203 120'
    'axi_topology_master_only_test 1204 120'
    'axi_topology_checker_only_test 1205 120'
    'axi_outstanding_limit_test 1301 180'
    'axi_outstanding_reset_test 1302 180'
    'axi_high_traffic_test 1402 1800'
)

for test_name in "${required_regressions[@]}"; do
    if ! awk -v wanted="$test_name" '$1 == wanted { found = 1 } END { exit !found }' \
        "$regression_list"; then
        echo "FAIL: regression.list is missing $test_name in its first column" >&2
        failed=1
    fi
done

for expected_row in "${required_regression_rows[@]}"; do
    read -r expected_test expected_seed expected_timeout <<<"$expected_row"
    if ! awk -v wanted_test="$expected_test" \
        -v wanted_seed="$expected_seed" \
        -v wanted_timeout="$expected_timeout" '
        $1 == wanted_test {
            matches++
            if (NF != 3 || $2 != wanted_seed || $3 != wanted_timeout)
                invalid = 1
        }
        END { exit !(matches == 1 && !invalid) }
    ' "$regression_list"; then
        echo "FAIL: regression.list does not contain exactly: $expected_row" >&2
        failed=1
    fi
done

regression_count=$(awk 'NF && $1 !~ /^#/ { count++ } END { print count + 0 }' \
    "$regression_list")
if [[ "$regression_count" -ne 16 ]]; then
    echo "FAIL: expected 16 regression entries, found $regression_count" >&2
    failed=1
fi

if ! awk '
    NF && $1 !~ /^#/ {
        if (NF != 3) invalid_columns = 1
        test_count[$1]++
        seed_count[$2]++
    }
    END {
        for (test_name in test_count)
            if (test_count[test_name] != 1) duplicate_test = 1
        for (seed in seed_count)
            if (seed_count[seed] != 1) duplicate_seed = 1
        exit invalid_columns || duplicate_test || duplicate_seed
    }
' "$regression_list"; then
    echo "FAIL: regression.list must use three columns with unique tests and seeds" >&2
    failed=1
fi

run_args_definition_count=$(awk '
    /^[[:space:]]*RUN_ARGS[[:space:]]*\?=/ { count++ }
    END { print count + 0 }
' "$makefile")
if [[ "$run_args_definition_count" -ne 1 ]]; then
    echo "FAIL: expected exactly one RUN_ARGS ?= definition, found $run_args_definition_count" >&2
    failed=1
fi

run_args_fixture='+AXI_TRAFFIC_TXNS=20000 +AXI_TRAFFIC_OUTSTANDING=32 +AXI_TRAFFIC_BURST_MAX=16'
for tool in vcs xcelium questa; do
    run_dry_run=$(make -s -n -C "$repo_root" run TOOL="$tool" \
        TEST=axi_high_traffic_test SEED=1402 RUN_ARGS="$run_args_fixture")
    fixture_count=$(awk -v needle="$run_args_fixture" '
        {
            line = $0
            while ((pos = index(line, needle)) != 0) {
                count++
                line = substr(line, pos + length(needle))
            }
        }
        END { print count + 0 }
    ' <<<"$run_dry_run")
    if [[ "$fixture_count" -ne 1 ]]; then
        echo "FAIL: $tool run command forwards the RUN_ARGS fixture $fixture_count times (expected once)" >&2
        failed=1
    fi
done

generated_docx_one="$doc_tmp_dir/generated-one.docx"
generated_docx_two="$doc_tmp_dir/generated-two.docx"
if ! python3 "$docx_generator" --output "$generated_docx_one" >/dev/null; then
    echo "FAIL: gen_docx.py --output failed for the first temporary DOCX" >&2
    failed=1
fi
if ! python3 "$docx_generator" --output "$generated_docx_two" >/dev/null; then
    echo "FAIL: gen_docx.py --output failed for the second temporary DOCX" >&2
    failed=1
fi

for generated_docx in "$generated_docx_one" "$generated_docx_two"; do
    if [[ ! -f "$generated_docx" ]]; then
        echo "FAIL: gen_docx.py --output did not create $generated_docx" >&2
        failed=1
    elif ! unzip -t "$generated_docx" >/dev/null; then
        echo "FAIL: generated DOCX is not a valid ZIP archive: $generated_docx" >&2
        failed=1
    fi
done

if [[ -f "$generated_docx_one" && -f "$generated_docx_two" ]]; then
    if ! cmp -s "$generated_docx_one" "$generated_docx_two"; then
        echo "FAIL: two --output DOCX generations are not byte-identical" >&2
        failed=1
    fi
    if ! cmp -s "$generated_docx_one" "$docx"; then
        echo "FAIL: temporary generation differs from the committed DOCX" >&2
        failed=1
    fi
fi

if ! python3 - "$integration" "$readme" "$docx" \
    "$generated_docx_one" "$generated_docx_two" "$sources" \
    "$repo_root/rtl/axi_if.sv" "$repo_root/src/axi_config.sv" <<'PY'
import pathlib
import re
import stat
import sys
import zipfile
from xml.etree import ElementTree
from xml.sax.saxutils import escape

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
W_P = f"{{{W_NS}}}p"
W_T = f"{{{W_NS}}}t"

CHECKER_EXPLANATION = (
    "explicitly instantiated in test/tb_top.sv and connected to the same axi_if"
)
PROTOCOL_INTENT = (
    "has_protocol_check is configuration/topology intent and does not "
    "instantiate the SystemVerilog module"
)
USER_LIMIT = "USER signals are not driven or monitored by the VIP."
EXTENSION_REQUIREMENT = (
    "Non-default widths or USER support require parameterizing the "
    "virtual-interface/type chain and implementing USER transaction and "
    "channel support."
)
FORBIDDEN_DEFAULT_FLOW = (
    "bound to the interface",
    "bind axi_protocol_checker",
    "checker (bind)",
)


def render_word_xml(xml_bytes):
    root = ElementTree.fromstring(xml_bytes)
    paragraphs = []
    for paragraph in root.iter(W_P):
        paragraphs.append("".join(
            node.text or "" for node in paragraph.iter(W_T)))
    return "\n".join(paragraphs)


def read_docx(path):
    with zipfile.ZipFile(path) as archive:
        return render_word_xml(archive.read("word/document.xml"))


def semantic_errors(text, require_source_order=False, source_order=""):
    errors = []
    for required in (
        CHECKER_EXPLANATION,
        PROTOCOL_INTENT,
        DEFAULT_SUPPORT,
        USER_LIMIT,
        EXTENSION_REQUIREMENT,
    ):
        if required not in text:
            errors.append(f"missing required text: {required}")
    lowered = text.lower()
    for forbidden in FORBIDDEN_DEFAULT_FLOW:
        if forbidden.lower() in lowered:
            errors.append(f"claims default checker flow uses bind: {forbidden}")
    if require_source_order:
        normalized_text = " ".join(text.split())
        normalized_sources = " ".join(source_order.split())
        if normalized_sources not in normalized_text:
            errors.append(f"missing make print-sources order: {source_order}")
    return errors


def zip_mode_errors(path):
    errors = []
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            mode = info.external_attr >> 16
            if not stat.S_ISREG(mode) or stat.S_IMODE(mode) != 0o644:
                errors.append(
                    f"{info.filename} mode={oct(mode)} is not regular 0644")
    return errors


def parse_defaults(path, pattern):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    return {
        name: int(value.replace("_", ""))
        for name, value in re.findall(pattern, text)
    }


(integration_path, readme_path, committed_path, generated_one, generated_two,
 source_order, interface_path, config_path) = sys.argv[1:]
failures = []

interface_defaults = parse_defaults(
    interface_path,
    r"parameter\s+int\s+(DATA_WIDTH|ADDR_WIDTH|ID_WIDTH|USER_WIDTH)\s*=\s*([0-9_]+)")
config_defaults = parse_defaults(
    config_path,
    r"int\s+unsigned\s+(data_width|addr_width|id_width|user_width)\s*=\s*([0-9_]+)")
expected_interface_names = ("DATA_WIDTH", "ADDR_WIDTH", "ID_WIDTH", "USER_WIDTH")
expected_config_names = ("data_width", "addr_width", "id_width", "user_width")
if tuple(interface_defaults) != expected_interface_names:
    failures.append(
        f"cannot parse interface defaults in declaration order: {interface_defaults}")
if tuple(config_defaults) != expected_config_names:
    failures.append(
        f"cannot parse config defaults in declaration order: {config_defaults}")
interface_values = tuple(interface_defaults.get(name) for name in expected_interface_names)
config_values = tuple(config_defaults.get(name) for name in expected_config_names)
if interface_values != config_values:
    failures.append(
        f"axi_if defaults {interface_values} differ from axi_config {config_values}")
DEFAULT_SUPPORT = (
    "The shipped out-of-box VIP path supports only axi_if's default "
    f"specialization: DATA_WIDTH={interface_values[0]}, "
    f"ADDR_WIDTH={interface_values[1]}, ID_WIDTH={interface_values[2]}, "
    f"USER_WIDTH={interface_values[3]}."
)

integration_text = pathlib.Path(integration_path).read_text(encoding="utf-8")
readme_text = pathlib.Path(readme_path).read_text(encoding="utf-8")
for error in semantic_errors(
        integration_text, require_source_order=True, source_order=source_order):
    failures.append(f"INTEGRATION.md: {error}")
for error in semantic_errors(readme_text):
    failures.append(f"README.md: {error}")

for label, path in (
    ("committed DOCX", committed_path),
    ("first generated DOCX", generated_one),
    ("second generated DOCX", generated_two),
):
    docx_path = pathlib.Path(path)
    if not docx_path.is_file():
        failures.append(f"{label}: missing file {path}")
        continue
    try:
        rendered_text = read_docx(docx_path)
        for error in semantic_errors(
                rendered_text, require_source_order=True,
                source_order=source_order):
            failures.append(f"{label}: {error}")
        for error in zip_mode_errors(docx_path):
            failures.append(f"{label}: {error}")
    except (KeyError, OSError, zipfile.BadZipFile,
            ElementTree.ParseError) as error:
        failures.append(f"{label}: cannot parse DOCX: {error}")

split_at = len(CHECKER_EXPLANATION) // 2
split_run_xml = (
    f'<w:document xmlns:w="{W_NS}"><w:body><w:p>'
    f'<w:r><w:t>{escape(CHECKER_EXPLANATION[:split_at])}</w:t></w:r>'
    f'<w:r><w:t>{escape(CHECKER_EXPLANATION[split_at:])}</w:t></w:r>'
    '</w:p></w:body></w:document>'
).encode()
if render_word_xml(split_run_xml) != CHECKER_EXPLANATION:
    failures.append("split-run WordML fixture was not rendered as one sentence")

broken_integration = integration_text.replace(
    CHECKER_EXPLANATION, "the checker is bound to the interface", 1)
if (broken_integration == integration_text or
        not semantic_errors(broken_integration)):
    failures.append("broken INTEGRATION fixture did not trigger semantic checks")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    raise SystemExit(1)
PY
then
    failed=1
fi

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

if grep -Fq 'checker/axi_checker_bind.sv' <<<"$sources"; then
    echo "FAIL: VCS sources include checker/axi_checker_bind.sv" >&2
    exit 1
fi

checker_count=$(awk '{ for (i = 1; i <= NF; i++) if ($i == "checker/axi_protocol_checker.sv") count++ } END { print count + 0 }' <<<"$sources")
if [[ "$checker_count" -ne 1 ]]; then
    echo "FAIL: expected checker/axi_protocol_checker.sv exactly once, found $checker_count" >&2
    exit 1
fi

if ! awk '{ for (i = 1; i <= NF; i++) if ($i == "test/tb_top.sv") found = 1 } END { exit !found }' <<<"$sources"; then
    echo "FAIL: VCS sources do not include test/tb_top.sv" >&2
    exit 1
fi

regress_dry_run=$(make -s -n -C "$repo_root" regress TOOL=vcs \
    REGRESSION_LIST='config/regression list.txt' \
    LOG_DIR='regression logs')
expected_regress='REGRESSION_LIST="config/regression list.txt" LOG_DIR="regression logs" scripts/run_regression.sh'
if ! grep -Fqx "$expected_regress" <<<"$regress_dry_run"; then
    echo "FAIL: regress does not preserve paths containing spaces as quoted arguments" >&2
    exit 1
fi

echo "PASS: VCS uses one directly instantiated checker"
