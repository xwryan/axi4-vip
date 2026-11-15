#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../check_sim_log.sh"
fixtures="$script_dir/fixtures"
failures=0
test_tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$test_tmp_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

expect_rc() {
    local expected_rc=$1
    local description=$2
    local actual_rc
    shift 2

    set +e
    "$@" >/dev/null 2>&1
    actual_rc=$?
    set -e
    if [[ "$actual_rc" -ne "$expected_rc" ]]; then
        fail "$description expected rc=$expected_rc, got rc=$actual_rc"
    fi
}

whitespace_runtime_log="$test_tmp_dir/whitespace_runtime.log"
ansi_runtime_log="$test_tmp_dir/ansi_runtime.log"
timestamp_runtime_log="$test_tmp_dir/timestamp_runtime.log"
expected_with_prefixed_runtime_log="$test_tmp_dir/expected_with_prefixed_runtime.log"
prefixed_expected_log="$test_tmp_dir/prefixed_expected.log"
crlf_clean_log="$test_tmp_dir/crlf_clean.log"
crlf_checker_log="$test_tmp_dir/crlf_checker.log"
multi_checker_log="$test_tmp_dir/multi_checker.log"
multi_missing_log="$test_tmp_dir/multi_missing.log"
multi_extra_log="$test_tmp_dir/multi_extra.log"

printf '%s\n' \
    '   Error-[NOA] whitespace-prefixed runtime diagnostic' \
    '--- UVM Report Summary ---' \
    'UVM_INFO : 10' 'UVM_WARNING : 0' 'UVM_ERROR : 0' 'UVM_FATAL : 0' \
    >"$whitespace_runtime_log"

printf '\033[31mError-[NOA]\033[0m ANSI-prefixed runtime diagnostic\n' \
    >"$ansi_runtime_log"
printf '%s\n' \
    '--- UVM Report Summary ---' \
    'UVM_INFO : 10' 'UVM_WARNING : 0' 'UVM_ERROR : 0' 'UVM_FATAL : 0' \
    >>"$ansi_runtime_log"

printf '%s\n' \
    '[2026-08-17T12:00:00] Error: "test/runtime_error_test.sv", 61' \
    '--- UVM Report Summary ---' \
    'UVM_INFO : 10' 'UVM_WARNING : 0' 'UVM_ERROR : 0' 'UVM_FATAL : 0' \
    >"$timestamp_runtime_log"

printf '%s\n' \
    '"checker/axi_protocol_checker.sv", 313: tb.dut.AST_WLAST_ON_LAST_BEAT: started at 10ns failed at 10ns' \
    'Error: "checker/axi_protocol_checker.sv", 313: tb.dut.AST_WLAST_ON_LAST_BEAT: at time 10 ns' \
    >"$expected_with_prefixed_runtime_log"
printf '\033[31m   [2026-08-17T12:00:00][simv] Error: "test/runtime_error_test.sv", 62\033[0m\n' \
    >>"$expected_with_prefixed_runtime_log"
printf '%s\n' \
    '--- UVM Report Summary ---' \
    'UVM_INFO : 10' 'UVM_WARNING : 0' 'UVM_ERROR : 0' 'UVM_FATAL : 0' \
    >>"$expected_with_prefixed_runtime_log"

printf '\033[36m   [2026-08-17T12:00:00] "checker/axi_protocol_checker.sv", 313: tb.dut.AST_WLAST_ON_LAST_BEAT: started at 10ns failed at 10ns\033[0m\n' \
    >"$prefixed_expected_log"
printf '\033[31m   [2026-08-17T12:00:00] Error: "checker/axi_protocol_checker.sv", 313: tb.dut.AST_WLAST_ON_LAST_BEAT: at time 10 ns\033[0m\n' \
    >>"$prefixed_expected_log"
printf '%s\n' \
    '--- UVM Report Summary ---' \
    'UVM_INFO : 10' 'UVM_WARNING : 0' 'UVM_ERROR : 0' 'UVM_FATAL : 0' \
    >>"$prefixed_expected_log"

printf '%s\r\n' \
    '--- UVM Report Summary ---' \
    'UVM_INFO : 10' 'UVM_WARNING : 0' 'UVM_ERROR : 0' 'UVM_FATAL : 0' \
    >"$crlf_clean_log"

printf '%s\r\n' \
    '"checker/axi_protocol_checker.sv", 313: tb.dut.AST_WLAST_ON_LAST_BEAT: started at 10ns failed at 10ns' \
    'Error: "checker/axi_protocol_checker.sv", 313: tb.dut.AST_WLAST_ON_LAST_BEAT: at time 10 ns' \
    'AXI_CHECKER_TEST_COMPLETE' \
    >"$crlf_checker_log"

printf '%s\n' \
    '"checker/axi_protocol_checker.sv", 900: tb.dut.AST_R_AFTER_AR: started at 10ns failed at 10ns' \
    'Error: "checker/axi_protocol_checker.sv", 900: tb.dut.AST_R_AFTER_AR: at time 10 ns' \
    '"checker/axi_protocol_checker.sv", 920: tb.dut.AST_RLAST_NOT_EARLY: started at 20ns failed at 20ns' \
    'Error: "checker/axi_protocol_checker.sv", 920: tb.dut.AST_RLAST_NOT_EARLY: at time 20 ns' \
    'AXI_CHECKER_TEST_COMPLETE' \
    >"$multi_checker_log"

printf '%s\n' \
    '"checker/axi_protocol_checker.sv", 900: tb.dut.AST_R_AFTER_AR: started at 10ns failed at 10ns' \
    'Error: "checker/axi_protocol_checker.sv", 900: tb.dut.AST_R_AFTER_AR: at time 10 ns' \
    'AXI_CHECKER_TEST_COMPLETE' \
    >"$multi_missing_log"

printf '%s\n' \
    '"checker/axi_protocol_checker.sv", 900: tb.dut.AST_R_AFTER_AR: started at 10ns failed at 10ns' \
    'Error: "checker/axi_protocol_checker.sv", 900: tb.dut.AST_R_AFTER_AR: at time 10 ns' \
    '"checker/axi_protocol_checker.sv", 920: tb.dut.AST_RLAST_NOT_EARLY: started at 20ns failed at 20ns' \
    'Error: "checker/axi_protocol_checker.sv", 920: tb.dut.AST_RLAST_NOT_EARLY: at time 20 ns' \
    '"checker/axi_protocol_checker.sv", 930: tb.dut.AST_RID_OUTSTANDING: started at 30ns failed at 30ns' \
    'Error: "checker/axi_protocol_checker.sv", 930: tb.dut.AST_RID_OUTSTANDING: at time 30 ns' \
    'AXI_CHECKER_TEST_COMPLETE' \
    >"$multi_extra_log"

expect_rc 0 "clean log" "$checker" "$fixtures/clean.log"
expect_rc 1 "UVM error" "$checker" "$fixtures/uvm_error.log"
expect_rc 1 "unexpected checker error" "$checker" "$fixtures/checker_error.log"
expect_rc 1 "non-checker VCS runtime error" \
    "$checker" "$fixtures/runtime_error.log"
expect_rc 1 "whitespace-prefixed VCS runtime error" \
    "$checker" "$whitespace_runtime_log"
expect_rc 1 "ANSI-prefixed VCS runtime error" \
    "$checker" "$ansi_runtime_log"
expect_rc 1 "timestamp-prefixed VCS runtime error" \
    "$checker" "$timestamp_runtime_log"
expect_rc 0 "expected checker assertion" \
    "$checker" "$fixtures/checker_error.log" AST_WLAST_ON_LAST_BEAT 1
expect_rc 1 "wrong expected checker assertion" \
    "$checker" "$fixtures/checker_error.log" AST_RLAST_ON_LAST_BEAT 1
expect_rc 1 "expected checker assertion cannot hide runtime diagnostics" \
    "$checker" "$fixtures/expected_checker_with_runtime_error.log" \
    AST_WLAST_ON_LAST_BEAT 1
expect_rc 1 "expected checker assertion cannot hide prefixed diagnostics" \
    "$checker" "$expected_with_prefixed_runtime_log" \
    AST_WLAST_ON_LAST_BEAT 1
expect_rc 0 "prefixed expected checker assertion is recognized" \
    "$checker" "$prefixed_expected_log" AST_WLAST_ON_LAST_BEAT 1
expect_rc 0 "CRLF UVM summary" "$checker" "$crlf_clean_log"

expect_rc 1 "missing UVM summary" "$checker" "$fixtures/no_summary.log"
expect_rc 1 "truncated UVM summary" "$checker" "$fixtures/truncated_summary.log"
expect_rc 1 "non-numeric UVM count" "$checker" "$fixtures/non_numeric_summary.log"
expect_rc 0 "final clean UVM summary wins" \
    "$checker" "$fixtures/multiple_summary_clean.log"
expect_rc 1 "final failing UVM summary wins" \
    "$checker" "$fixtures/multiple_summary_error.log"
expect_rc 1 "truncated final UVM summary is invalid" \
    "$checker" "$fixtures/truncated_final_summary.log"

expect_rc 1 "assertion prefix is not an exact rule" \
    "$checker" "$fixtures/checker_error.log" AST_WLAST 1
expect_rc 1 "started rule must match Error rule" \
    "$checker" "$fixtures/mismatched_checker_rule.log" \
    AST_WLAST_ON_LAST_BEAT 1
expect_rc 1 "extra checker rule is rejected" \
    "$checker" "$fixtures/extra_checker_rule.log" \
    AST_WLAST_ON_LAST_BEAT 2
expect_rc 0 "two expected checker assertions" \
    "$checker" "$multi_checker_log" \
    AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1,1
expect_rc 1 "multi-assertion log missing one expected rule" \
    "$checker" "$multi_missing_log" \
    AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1,1
expect_rc 1 "multi-assertion wrong count is rejected" \
    "$checker" "$multi_checker_log" \
    AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1,2
expect_rc 1 "multi-assertion extra checker error is rejected" \
    "$checker" "$multi_extra_log" \
    AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1,1

expect_rc 2 "zero arguments" "$checker"
expect_rc 2 "two arguments" "$checker" "$fixtures/clean.log" AST_NONE
expect_rc 2 "four arguments" \
    "$checker" "$fixtures/clean.log" AST_NONE 0 extra
expect_rc 2 "missing log file" "$checker" "$fixtures/missing.log"
expect_rc 2 "leading-zero count" \
    "$checker" "$fixtures/clean.log" AST_NONE 08
expect_rc 2 "empty assertion" "$checker" "$fixtures/clean.log" "" 1
expect_rc 2 "negative count" "$checker" "$fixtures/clean.log" AST_NONE -1
expect_rc 2 "non-numeric count" \
    "$checker" "$fixtures/clean.log" AST_NONE invalid
expect_rc 2 "duplicate assertion list entry" \
    "$checker" "$multi_checker_log" AST_R_AFTER_AR,AST_R_AFTER_AR 1,1
expect_rc 2 "assertion and count list lengths differ" \
    "$checker" "$multi_checker_log" \
    AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1
expect_rc 2 "empty assertion list entry" \
    "$checker" "$multi_checker_log" \
    AST_R_AFTER_AR,,AST_RLAST_NOT_EARLY 1,1,1
expect_rc 2 "unsafe assertion list format" \
    "$checker" "$multi_checker_log" AST_R_AFTER_AR,NOT_AST 1,1
expect_rc 2 "leading-zero list count" \
    "$checker" "$multi_checker_log" \
    AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1,01
expect_rc 1 "arbitrarily large count is compared safely" \
    "$checker" "$fixtures/clean.log" AST_NONE \
    99999999999999999999999999999999999999999999999999

# Task 4 checker_rule_tb contract: a non-UVM test must print this exact
# completion marker once, after the checker scenario has finished.
expect_rc 0 "completed checker-only clean log" \
    "$checker" "$fixtures/checker_only_clean.log"
expect_rc 0 "completed checker-only expected assertion" \
    "$checker" "$fixtures/checker_only_expected_error.log" \
    AST_WLAST_ON_LAST_BEAT 1
expect_rc 1 "checker-only unexpected assertion" \
    "$checker" "$fixtures/checker_only_expected_error.log"
expect_rc 1 "checker-only VCS runtime fatal" \
    "$checker" "$fixtures/checker_only_runtime_fatal.log"
expect_rc 0 "CRLF checker-only expected assertion and marker" \
    "$checker" "$crlf_checker_log" AST_WLAST_ON_LAST_BEAT 1
expect_rc 1 "checker-only missing completion marker" \
    "$checker" "$fixtures/checker_only_missing_marker.log"
expect_rc 1 "checker-only approximate completion marker" \
    "$checker" "$fixtures/checker_only_similar_marker.log"
expect_rc 1 "checker-only duplicate completion marker" \
    "$checker" "$fixtures/checker_only_duplicate_marker.log"
expect_rc 1 "completion marker cannot bypass damaged UVM summary" \
    "$checker" "$fixtures/damaged_uvm_with_marker.log"

if [[ "$failures" -ne 0 ]]; then
    exit 1
fi

printf 'PASS: simulation log verdict parser\n'
