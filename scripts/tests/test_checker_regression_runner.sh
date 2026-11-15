#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
runner="$script_dir/../run_checker_regression.sh"
matrix="$repo_root/config/checker_regression.list"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

fixture_dir="$tmp_dir/checker regression fixture"
simv="$fixture_dir/fake checker_simv"
checker_list="$fixture_dir/checker regression list.txt"
log_dir="$fixture_dir/checker logs"
calls="$fixture_dir/simv calls.txt"
mkdir -p -- "$fixture_dir"

cat >"$simv" <<'FAKE_SIMV'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_SIMV_CALLS"

scenario=
for argument in "$@"; do
    case "$argument" in
        +SCENARIO=*) scenario=${argument#+SCENARIO=} ;;
    esac
done

case "$scenario" in
    CLEAN|STDIN)
        if [[ "$scenario" == STDIN ]] && IFS= read -r polluted_input; then
            printf 'unexpected simulator stdin: %s\n' "$polluted_input" >&2
            exit 9
        fi
        ;;
    EXPECTED)
        cat <<'EOF'
"checker/axi_protocol_checker.sv", 313: tb.dut.AST_AW_4KB_BOUNDARY: started at 10ns failed at 10ns
Error: "checker/axi_protocol_checker.sv", 313: tb.dut.AST_AW_4KB_BOUNDARY: at time 10 ns
EOF
        ;;
    MULTI_EXPECTED)
        cat <<'EOF'
"checker/axi_protocol_checker.sv", 900: tb.dut.AST_R_AFTER_AR: started at 10ns failed at 10ns
Error: "checker/axi_protocol_checker.sv", 900: tb.dut.AST_R_AFTER_AR: at time 10 ns
"checker/axi_protocol_checker.sv", 920: tb.dut.AST_RLAST_NOT_EARLY: started at 20ns failed at 20ns
Error: "checker/axi_protocol_checker.sv", 920: tb.dut.AST_RLAST_NOT_EARLY: at time 20 ns
EOF
        ;;
    EXTRA_DIAGNOSTIC)
        cat <<'EOF'
"checker/axi_protocol_checker.sv", 313: tb.dut.AST_AW_4KB_BOUNDARY: started at 10ns failed at 10ns
Error: "checker/axi_protocol_checker.sv", 313: tb.dut.AST_AW_4KB_BOUNDARY: at time 10 ns
Error-[RUNTIME] unexpected simulator diagnostic
EOF
        ;;
    CRASH)
        sim_rc=42
        ;;
    HANG)
        printf '%s\n' "$$" >"$HANG_PID_FILE"
        trap '' TERM
        while :; do
            sleep 0.05 || true
        done
        ;;
    SUMMARY_APPEND_FAIL)
        chmod 400 "$SUMMARY_MUTATION_PATH"
        ;;
    LOG_READ_FAIL)
        output_path=$(readlink "/proc/$$/fd/1")
        chmod 000 "$output_path"
        ;;
    *)
        printf 'unexpected scenario: %s\n' "$scenario" >&2
        exit 2
        ;;
esac

printf '%s\n' AXI_CHECKER_TEST_COMPLETE
exit "${sim_rc:-0}"
FAKE_SIMV
chmod +x "$simv"

run_checker() {
    local stdout_path=$1
    local stderr_path=$2
    local list_path=${3:-$checker_list}
    local logs_path=${4:-$log_dir}
    local simulator_path=${5:-$simv}
    local runner_path=${6:-$runner}

    set +e
    FAKE_SIMV_CALLS="$calls" \
    CHECKER_SIMV="$simulator_path" \
    CHECKER_REGRESSION_LIST="$list_path" \
    CHECKER_LOG_DIR="$logs_path" \
        "$runner_path" >"$stdout_path" 2>"$stderr_path"
    checker_rc=$?
    set -e
}

cat >"$checker_list" <<'EOF'
CLEAN - 0 5
EXPECTED AST_AW_4KB_BOUNDARY 1 5
EXTRA_DIAGNOSTIC AST_AW_4KB_BOUNDARY 1 5
CRASH - 0 5
CLEAN_AGAIN - 0 5
EOF

# The fake simulator accepts CLEAN, while CLEAN_AGAIN deliberately proves that
# an earlier scenario failure does not stop later rows from being attempted.
# It exits 2 for CLEAN_AGAIN, and that exact simulator status must be retained.
: >"$calls"
run_checker "$tmp_dir/main.stdout" "$tmp_dir/main.stderr"
if [[ "$checker_rc" -ne 1 ]]; then
    printf 'FAIL: mixed checker regression expected rc=1, got rc=%s\n' \
        "$checker_rc" >&2
    exit 1
fi

summary="$log_dir/checker_regression_summary.tsv"
expected_summary=$(printf \
    'scenario\tsim_rc\tstatus\tparser_rc\tfailure_class\tlog_path\n%s\t%s\t%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\t%s' \
    CLEAN 0 PASS 0 PASS "$log_dir/CLEAN.log" \
    EXPECTED 0 PASS 0 PASS "$log_dir/EXPECTED.log" \
    EXTRA_DIAGNOSTIC 0 FAIL 1 LOG "$log_dir/EXTRA_DIAGNOSTIC.log" \
    CRASH 42 FAIL 0 SIM "$log_dir/CRASH.log" \
    CLEAN_AGAIN 2 FAIL 1 SIM "$log_dir/CLEAN_AGAIN.log")
if [[ ! -f "$summary" ]] || [[ "$(cat -- "$summary")" != "$expected_summary" ]]; then
    printf 'FAIL: checker summary did not preserve exact verdicts\n' >&2
    diff -u <(printf '%s\n' "$expected_summary") "$summary" >&2 || true
    exit 1
fi
if [[ $(wc -l <"$calls") -ne 5 ]] ||
   ! grep -Fxq -- '+SCENARIO=CLEAN' "$calls" ||
   ! grep -Fxq -- '+SCENARIO=EXPECTED' "$calls" ||
   ! grep -Fxq -- '+SCENARIO=CLEAN_AGAIN' "$calls"; then
    printf 'FAIL: runner did not invoke every scenario with exact plusargs\n' >&2
    exit 1
fi

# Make passes its configurable defaults as relative paths. A simulator basename
# must remain a filesystem path rather than being looked up through PATH.
printf 'CLEAN - 0 5\n' >"$checker_list"
: >"$calls"
set +e
(
    cd -- "$fixture_dir"
    FAKE_SIMV_CALLS="$calls" \
    CHECKER_SIMV='fake checker_simv' \
    CHECKER_REGRESSION_LIST='checker regression list.txt' \
    CHECKER_LOG_DIR='relative checker logs' \
        "$runner" >"$tmp_dir/relative.stdout" 2>"$tmp_dir/relative.stderr"
)
checker_rc=$?
set -e
if [[ "$checker_rc" -ne 0 ]] ||
   [[ ! -f "$fixture_dir/relative checker logs/checker_regression_summary.tsv" ]]; then
    printf 'FAIL: relative checker paths were not resolved from the caller\n' >&2
    exit 1
fi

# A negative row may require multiple exact assertion/count pairs.  The CSV
# fields contain no spaces and remain one matrix column each.
printf '%s\n' \
    'MULTI_EXPECTED AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1,1 5' \
    >"$checker_list"
: >"$calls"
multi_logs="$fixture_dir/multi assertion logs"
run_checker "$tmp_dir/multi.stdout" "$tmp_dir/multi.stderr" \
    "$checker_list" "$multi_logs"
if [[ "$checker_rc" -ne 0 ]] ||
   ! grep -Fxq -- '+SCENARIO=MULTI_EXPECTED' "$calls" ||
   ! grep -Fq $'MULTI_EXPECTED\t0\tPASS\t0\tPASS\t' \
        "$multi_logs/checker_regression_summary.tsv"; then
    printf 'FAIL: multi-assertion checker row did not preserve exact verdict\n' >&2
    exit 1
fi

expect_infrastructure_failure() {
    local description=$1
    local list_path=$2
    local logs_path=$3
    local simulator_path=${4:-$simv}
    local runner_path=${5:-$runner}

    : >"$calls"
    run_checker "$tmp_dir/infra.stdout" "$tmp_dir/infra.stderr" \
        "$list_path" "$logs_path" "$simulator_path" "$runner_path"
    if [[ "$checker_rc" -ne 2 ]]; then
        printf 'FAIL: %s expected rc=2, got rc=%s\n' \
            "$description" "$checker_rc" >&2
        exit 1
    fi
    if [[ -s "$calls" ]]; then
        printf 'FAIL: %s invoked the simulator\n' "$description" >&2
        exit 1
    fi
}

empty_list="$fixture_dir/empty.list"
: >"$empty_list"
expect_infrastructure_failure "empty matrix" "$empty_list" \
    "$fixture_dir/empty logs"

comment_list="$fixture_dir/comments.list"
cat >"$comment_list" <<'EOF'

# no checker scenarios
    # still no checker scenarios
EOF
expect_infrastructure_failure "comment-only matrix" "$comment_list" \
    "$fixture_dir/comment logs"

valid_list="$fixture_dir/valid.list"
printf 'CLEAN - 0 5\n' >"$valid_list"

unreadable_list="$fixture_dir/unreadable.list"
printf 'CLEAN - 0 5\n' >"$unreadable_list"
chmod 000 "$unreadable_list"
expect_infrastructure_failure "unreadable matrix" "$unreadable_list" \
    "$fixture_dir/unreadable logs"
chmod 600 "$unreadable_list"

expect_infrastructure_failure "non-regular matrix" "$fixture_dir" \
    "$fixture_dir/nonregular logs"
expect_infrastructure_failure "missing matrix" "$fixture_dir/missing.list" \
    "$fixture_dir/missing logs"
expect_infrastructure_failure "missing simulator" "$valid_list" \
    "$fixture_dir/missing simulator logs" "$fixture_dir/missing checker_simv"

nonexec_simv="$fixture_dir/non-executable checker_simv"
cp -- "$simv" "$nonexec_simv"
chmod 600 "$nonexec_simv"
expect_infrastructure_failure "non-executable simulator" "$valid_list" \
    "$fixture_dir/nonexec simulator logs" "$nonexec_simv"

log_parent_file="$fixture_dir/not a directory"
: >"$log_parent_file"
expect_infrastructure_failure "log directory creation failure" \
    "$valid_list" "$log_parent_file/child"

summary_failure_logs="$fixture_dir/summary creation failure logs"
mkdir -p "$summary_failure_logs/checker_regression_summary.tsv"
expect_infrastructure_failure "summary creation failure" \
    "$valid_list" "$summary_failure_logs"

log_failure_logs="$fixture_dir/log creation failure logs"
mkdir -p "$log_failure_logs/CLEAN.log"
expect_infrastructure_failure "log creation failure" \
    "$valid_list" "$log_failure_logs"

isolated_scripts="$fixture_dir/isolated scripts"
mkdir -p "$isolated_scripts"
cp -- "$runner" "$isolated_scripts/run_checker_regression.sh"
chmod +x "$isolated_scripts/run_checker_regression.sh"
expect_infrastructure_failure "missing parser" "$valid_list" \
    "$fixture_dir/missing parser logs" "$simv" \
    "$isolated_scripts/run_checker_regression.sh"

printf '#!/usr/bin/env bash\nexit 0\n' >"$isolated_scripts/check_sim_log.sh"
chmod 600 "$isolated_scripts/check_sim_log.sh"
expect_infrastructure_failure "non-executable parser" "$valid_list" \
    "$fixture_dir/nonexec parser logs" "$simv" \
    "$isolated_scripts/run_checker_regression.sh"

: >"$calls"
limited_path="$fixture_dir/limited path"
mkdir -p "$limited_path"
ln -s "$(type -P bash)" "$limited_path/bash"
ln -s "$(type -P dirname)" "$limited_path/dirname"
set +e
PATH="$limited_path" \
FAKE_SIMV_CALLS="$calls" \
CHECKER_SIMV="$simv" \
CHECKER_REGRESSION_LIST="$valid_list" \
CHECKER_LOG_DIR="$fixture_dir/missing timeout logs" \
    "$runner" >"$tmp_dir/missing-timeout.stdout" \
    2>"$tmp_dir/missing-timeout.stderr"
checker_rc=$?
set -e
if [[ "$checker_rc" -ne 2 || -s "$calls" ]]; then
    printf 'FAIL: missing timeout command was not rejected before simulation\n' >&2
    exit 1
fi

: >"$calls"
set +e
TIMEOUT_KILL_AFTER=0s \
FAKE_SIMV_CALLS="$calls" \
CHECKER_SIMV="$simv" \
CHECKER_REGRESSION_LIST="$valid_list" \
CHECKER_LOG_DIR="$fixture_dir/invalid kill-after logs" \
    "$runner" >"$tmp_dir/kill-after.stdout" 2>"$tmp_dir/kill-after.stderr"
checker_rc=$?
set -e
if [[ "$checker_rc" -ne 2 || -s "$calls" ]]; then
    printf 'FAIL: invalid TIMEOUT_KILL_AFTER was not rejected\n' >&2
    exit 1
fi

expect_invalid_matrix() {
    local description=$1
    local contents=$2
    local invalid_list="$fixture_dir/invalid-${description// /-}.list"

    printf '%s\n' "$contents" >"$invalid_list"
    expect_infrastructure_failure "$description" "$invalid_list" \
        "$fixture_dir/invalid-${description// /-}-logs"
}

expect_invalid_matrix "path escaping scenario" "../CLEAN - 0 5"
expect_invalid_matrix "lowercase scenario" "clean - 0 5"
expect_invalid_matrix "leading digit scenario" "1CLEAN - 0 5"
expect_invalid_matrix "missing column" "CLEAN - 5"
expect_invalid_matrix "extra column" "CLEAN - 0 5 extra"
expect_invalid_matrix "clean nonzero count" "CLEAN - 1 5"
expect_invalid_matrix "negative zero assertion" "BAD -0 1 5"
expect_invalid_matrix "invalid assertion prefix" "BAD AW_4KB 1 5"
expect_invalid_matrix "lowercase assertion" "BAD AST_aw_4KB 1 5"
expect_invalid_matrix "zero expected count" "BAD AST_AW_4KB_BOUNDARY 0 5"
expect_invalid_matrix "leading-zero count" "BAD AST_AW_4KB_BOUNDARY 01 5"
expect_invalid_matrix "negative count" "BAD AST_AW_4KB_BOUNDARY -1 5"
expect_invalid_matrix "nonnumeric count" "BAD AST_AW_4KB_BOUNDARY many 5"
expect_invalid_matrix "duplicate assertion in list" \
    "BAD AST_R_AFTER_AR,AST_R_AFTER_AR 1,1 5"
expect_invalid_matrix "assertion count list length mismatch" \
    "BAD AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1 5"
expect_invalid_matrix "empty assertion list entry" \
    "BAD AST_R_AFTER_AR,,AST_RLAST_NOT_EARLY 1,1,1 5"
expect_invalid_matrix "unsafe assertion list entry" \
    "BAD AST_R_AFTER_AR,NOT_AST 1,1 5"
expect_invalid_matrix "leading-zero count list entry" \
    "BAD AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1,01 5"
expect_invalid_matrix "zero timeout" "CLEAN - 0 0"
expect_invalid_matrix "leading-zero timeout" "CLEAN - 0 05"
expect_invalid_matrix "nonnumeric timeout" "CLEAN - 0 fast"
expect_invalid_matrix "duplicate scenario" $'CLEAN - 0 5\nCLEAN - 0 6'
expect_invalid_matrix "late invalid row" $'CLEAN - 0 5\nBAD AST_AW_4KB_BOUNDARY 0 5'

# Polluted runner stdin must never reach the simulator or consume matrix rows.
cat >"$checker_list" <<'EOF'
STDIN - 0 5
CLEAN - 0 5
EOF
: >"$calls"
stdin_logs="$fixture_dir/stdin isolation logs"
set +e
printf 'polluted runner stdin\n' | \
    FAKE_SIMV_CALLS="$calls" \
    CHECKER_SIMV="$simv" \
    CHECKER_REGRESSION_LIST="$checker_list" \
    CHECKER_LOG_DIR="$stdin_logs" \
    "$runner" >"$tmp_dir/stdin.stdout" 2>"$tmp_dir/stdin.stderr"
checker_rc=${PIPESTATUS[1]}
set -e
if [[ "$checker_rc" -ne 0 ]] || [[ $(wc -l <"$calls") -ne 2 ]]; then
    printf 'FAIL: checker simulator inherited stdin or skipped a row\n' >&2
    exit 1
fi

# A TERM-ignoring simulator must be hard-killed and a later row must run.
cat >"$checker_list" <<'EOF'
HANG - 0 1
CLEAN - 0 5
EOF
: >"$calls"
hang_logs="$fixture_dir/forced timeout logs"
hang_pid_file="$fixture_dir/hang pid"
set +e
timeout --signal=TERM --kill-after=1s 3s \
    env FAKE_SIMV_CALLS="$calls" HANG_PID_FILE="$hang_pid_file" \
        TIMEOUT_KILL_AFTER=0.2s CHECKER_SIMV="$simv" \
        CHECKER_REGRESSION_LIST="$checker_list" \
        CHECKER_LOG_DIR="$hang_logs" \
        "$runner" >"$tmp_dir/timeout.stdout" 2>"$tmp_dir/timeout.stderr"
checker_rc=$?
set -e
if [[ "$checker_rc" -ne 1 ]] ||
   ! grep -Eq $'^HANG\t(124|137)\tFAIL\t1\tTIMEOUT\t' \
       "$hang_logs/checker_regression_summary.tsv" ||
   ! grep -q $'^CLEAN\t0\tPASS\t0\tPASS\t' \
       "$hang_logs/checker_regression_summary.tsv"; then
    [[ -f "$hang_pid_file" ]] && kill -KILL "$(cat -- "$hang_pid_file")" 2>/dev/null || true
    printf 'FAIL: hard timeout did not converge and continue\n' >&2
    exit 1
fi
if kill -0 "$(cat -- "$hang_pid_file")" 2>/dev/null; then
    kill -KILL "$(cat -- "$hang_pid_file")" 2>/dev/null || true
    printf 'FAIL: timed-out checker simulator remains running\n' >&2
    exit 1
fi

# TERM sent to the runner must reap its active checker simulator.
printf 'HANG - 0 20\n' >"$checker_list"
: >"$calls"
interrupt_logs="$fixture_dir/interrupt logs"
interrupt_pid_file="$fixture_dir/interrupt pid"
FAKE_SIMV_CALLS="$calls" HANG_PID_FILE="$interrupt_pid_file" \
TIMEOUT_KILL_AFTER=0.2s CHECKER_SIMV="$simv" \
CHECKER_REGRESSION_LIST="$checker_list" CHECKER_LOG_DIR="$interrupt_logs" \
    "$runner" >"$tmp_dir/interrupt.stdout" 2>"$tmp_dir/interrupt.stderr" &
runner_pid=$!
for _ in {1..100}; do
    [[ -s "$interrupt_pid_file" ]] && break
    sleep 0.02
done
if [[ ! -s "$interrupt_pid_file" ]]; then
    kill -KILL "$runner_pid" 2>/dev/null || true
    printf 'FAIL: interrupt test checker simulator did not start\n' >&2
    exit 1
fi
kill -TERM "$runner_pid"
set +e
wait "$runner_pid"
checker_rc=$?
set -e
if [[ "$checker_rc" -ne 143 ]]; then
    printf 'FAIL: interrupted runner expected rc=143, got rc=%s\n' \
        "$checker_rc" >&2
    exit 1
fi
if kill -0 "$(cat -- "$interrupt_pid_file")" 2>/dev/null; then
    kill -KILL "$(cat -- "$interrupt_pid_file")" 2>/dev/null || true
    printf 'FAIL: interrupted checker runner left simulator running\n' >&2
    exit 1
fi

# Parser rc=2 is infrastructure failure and must not be downgraded to rc=1.
parser_rc2_scripts="$fixture_dir/parser rc2 scripts"
mkdir -p "$parser_rc2_scripts"
cp -- "$runner" "$parser_rc2_scripts/run_checker_regression.sh"
cat >"$parser_rc2_scripts/check_sim_log.sh" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
chmod +x "$parser_rc2_scripts"/*.sh
printf 'CLEAN - 0 5\n' >"$checker_list"
: >"$calls"
run_checker "$tmp_dir/parser-rc2.stdout" "$tmp_dir/parser-rc2.stderr" \
    "$checker_list" "$fixture_dir/parser rc2 logs" "$simv" \
    "$parser_rc2_scripts/run_checker_regression.sh"
if [[ "$checker_rc" -ne 2 ]] ||
   ! grep -q $'^CLEAN\t0\tFAIL\t2\tINFRA\t' \
       "$fixture_dir/parser rc2 logs/checker_regression_summary.tsv"; then
    printf 'FAIL: parser rc=2 was not preserved as infrastructure failure\n' >&2
    exit 1
fi

# Summary append, summary read, and log read failures are infrastructure.
printf 'SUMMARY_APPEND_FAIL - 0 5\n' >"$checker_list"
append_logs="$fixture_dir/append failure logs"
mkdir -p "$append_logs"
append_summary="$append_logs/checker_regression_summary.tsv"
set +e
FAKE_SIMV_CALLS="$calls" SUMMARY_MUTATION_PATH="$append_summary" \
CHECKER_SIMV="$simv" CHECKER_REGRESSION_LIST="$checker_list" \
CHECKER_LOG_DIR="$append_logs" \
    "$runner" >"$tmp_dir/append.stdout" 2>"$tmp_dir/append.stderr"
checker_rc=$?
set -e
chmod 600 "$append_summary"
if [[ "$checker_rc" -ne 2 ]]; then
    printf 'FAIL: summary append failure expected rc=2, got rc=%s\n' \
        "$checker_rc" >&2
    exit 1
fi

printf 'CLEAN - 0 5\n' >"$checker_list"
read_logs="$fixture_dir/read failure logs"
mkdir -p "$read_logs"
read_summary="$read_logs/checker_regression_summary.tsv"
: >"$read_summary"
chmod 200 "$read_summary"
run_checker "$tmp_dir/read.stdout" "$tmp_dir/read.stderr" \
    "$checker_list" "$read_logs"
chmod 600 "$read_summary"
if [[ "$checker_rc" -ne 2 ]]; then
    printf 'FAIL: summary read failure expected rc=2, got rc=%s\n' \
        "$checker_rc" >&2
    exit 1
fi

printf 'LOG_READ_FAIL - 0 5\n' >"$checker_list"
log_read_logs="$fixture_dir/log read failure logs"
run_checker "$tmp_dir/log-read.stdout" "$tmp_dir/log-read.stderr" \
    "$checker_list" "$log_read_logs"
chmod 600 "$log_read_logs/LOG_READ_FAIL.log"
if [[ "$checker_rc" -ne 2 ]]; then
    printf 'FAIL: log read failure expected rc=2, got rc=%s\n' \
        "$checker_rc" >&2
    exit 1
fi

# The checked-in matrix is an exact, reviewable 62-scenario capability list.
expected_matrix="$tmp_dir/expected checker regression.list"
cat >"$expected_matrix" <<'EOF'
ZERO_WSTRB - 0 30
WRAP_OFFSET - 0 30
AR_WRAP_OFFSET - 0 30
UNALIGNED_SINGLE_NEAR_4KB - 0 30
AR_UNALIGNED_SINGLE_NEAR_4KB - 0 30
AT_4KB_LIMIT - 0 30
AR_AT_4KB_LIMIT - 0 30
FIXED_MAX - 0 30
AR_FIXED_MAX - 0 30
CROSS_4KB AST_AW_4KB_BOUNDARY 1 30
AR_CROSS_4KB AST_AR_4KB_BOUNDARY 1 30
RESERVED_BURST AST_AW_BURST_ENCODING 1 30
AR_RESERVED_BURST AST_AR_BURST_ENCODING 1 30
RESERVED_NEAR_4KB AST_AW_BURST_ENCODING 1 30
AR_RESERVED_NEAR_4KB AST_AR_BURST_ENCODING 1 30
FIXED_TOO_LONG AST_AW_FIXED_LEN 1 30
AR_FIXED_TOO_LONG AST_AR_FIXED_LEN 1 30
WRAP_MISALIGNED AST_AW_WRAP_ALIGN 1 30
AR_WRAP_MISALIGNED AST_AR_WRAP_ALIGN 1 30
WRITE_AW_BEFORE_W_CLEAN - 0 30
WRITE_W_BEFORE_AW_CLEAN - 0 30
WRITE_W_STARTS_BEFORE_AW_CLEAN - 0 30
WRITE_W_LAST_AND_AW_SAME_CYCLE_CLEAN - 0 30
WRITE_TWO_W_BEFORE_AW_CLEAN - 0 30
WRITE_DIFFERENT_ID_B_REORDER_CLEAN - 0 30
WRITE_SAME_ID_RESPONSES_CLEAN - 0 30
B_AFTER_AW_W_CLEAN - 0 30
B_BEFORE_W_COMPLETE AST_B_AFTER_AW_W 1 30
B_BEFORE_W_COMPLETE_STALLED AST_B_AFTER_AW_W 1 30
BID_NOT_OUTSTANDING AST_BID_OUTSTANDING 1 30
READ_SINGLE_CLEAN - 0 30
READ_INTERLEAVE_IDS_CLEAN - 0 30
READ_SAME_ID_ORDER_CLEAN - 0 30
RLAST_EARLY AST_RLAST_NOT_EARLY 1 30
RLAST_MISSING AST_RLAST_ON_LAST_BEAT 1 30
RLAST_LATE AST_RLAST_ON_LAST_BEAT 1 30
RLAST_MISSING_THEN_NEXT_SAME_ID_CLEAN AST_RLAST_ON_LAST_BEAT 1 30
R_WITHOUT_AR AST_R_AFTER_AR 1 30
R_WITHOUT_AR_STALLED AST_R_AFTER_AR 1 30
RID_NOT_OUTSTANDING AST_RID_OUTSTANDING 1 30
B_STALLED_EARLY_THEN_COMPLETES AST_B_AFTER_AW_W 1 30
R_STALLED_EARLY_THEN_AR AST_R_AFTER_AR 1 30
R_RECOVERY_RLAST_EARLY AST_R_AFTER_AR,AST_RLAST_NOT_EARLY 1,1 30
R_RECOVERY_RLAST_MISSING AST_R_AFTER_AR,AST_RLAST_ON_LAST_BEAT 1,1 30
B_HANDSHAKE_AND_NEXT_WRITE_COMPLETE_SAME_CYCLE - 0 30
OLD_RLAST_AND_NEXT_AR_SAME_ID_SAME_CYCLE - 0 30
WLAST_EARLY AST_WLAST_NOT_EARLY 1 30
WLAST_MISSING AST_WLAST_ON_LAST_BEAT 1 30
WLAST_LATE AST_WLAST_ON_LAST_BEAT 1 30
WLAST_MISSING_THEN_NEXT_WRITE_CLEAN AST_WLAST_ON_LAST_BEAT 1 30
W_BEFORE_AW_WLAST_EARLY AST_WLAST_NOT_EARLY 1 30
W_BEFORE_AW_WLAST_LATE AST_WLAST_ON_LAST_BEAT 1 30
AW_ARRIVES_AFTER_EXPECTED_BEAT AST_WLAST_ON_LAST_BEAT 1 30
RESET_CLEARS_PENDING_CLEAN - 0 30
B_AFTER_RESET_INVALID AST_BID_OUTSTANDING 1 30
R_AFTER_RESET_INVALID AST_R_AFTER_AR 1 30
AW_W_SAME_CYCLE_CLEAN - 0 30
AR_R_SAME_CYCLE_INVALID AST_R_AFTER_AR 1 30
AW_W_B_SAME_CYCLE_INVALID AST_B_AFTER_AW_W 1 30
W_RECOVERY_RESET_THEN_CLEAN AST_WLAST_ON_LAST_BEAT 1 30
R_RECOVERY_RESET_THEN_CLEAN AST_RLAST_ON_LAST_BEAT 1 30
ASYNC_RESET_CLEARS_STATE_CLEAN - 0 30
EOF
if ! cmp -s -- "$expected_matrix" "$matrix"; then
    printf 'FAIL: checked-in checker matrix is not the exact 62-scenario set\n' >&2
    diff -u "$expected_matrix" "$matrix" >&2 || true
    exit 1
fi

# Make must quote all configurable checker paths, expose the test, and reject
# unsupported simulators without invoking their compiler.
make_dry_run="$tmp_dir/make dry run.txt"
make -n -C "$repo_root" TOOL=vcs \
    CHECKER_SIMV='build/checker simv' \
    CHECKER_REGRESSION_LIST='config/checker list.txt' \
    CHECKER_LOG_DIR='checker logs' checker-regress >"$make_dry_run"
if ! grep -Fq -- '-o "build/checker simv"' "$make_dry_run" ||
   ! grep -Fq -- 'CHECKER_SIMV="build/checker simv" CHECKER_REGRESSION_LIST="config/checker list.txt" CHECKER_LOG_DIR="checker logs" scripts/run_checker_regression.sh' "$make_dry_run"; then
    printf 'FAIL: Make checker paths are not safely quoted\n' >&2
    exit 1
fi
if ! make -n -C "$repo_root" test-scripts | \
        grep -Fxq -- 'scripts/tests/test_checker_regression_runner.sh'; then
    printf 'FAIL: make test-scripts omits checker runner test\n' >&2
    exit 1
fi
set +e
make -s -C "$repo_root" TOOL=questa checker-compile \
    >"$tmp_dir/unsupported.stdout" 2>"$tmp_dir/unsupported.stderr"
unsupported_rc=$?
set -e
if [[ "$unsupported_rc" -eq 0 ]] ||
   ! grep -Fqi -- 'checker-compile requires TOOL=vcs' \
       "$tmp_dir/unsupported.stderr"; then
    printf 'FAIL: unsupported checker compiler did not fail clearly\n' >&2
    exit 1
fi
make -n -C "$repo_root" CHECKER_SIMV='/tmp/do not remove' clean \
    >"$tmp_dir/clean dry run.txt"
if grep -Fq -- '/tmp/do not remove' "$tmp_dir/clean dry run.txt" ||
   ! grep -Fq -- 'checker_logs' "$tmp_dir/clean dry run.txt"; then
    printf 'FAIL: make clean is unsafe or omits checker logs\n' >&2
    exit 1
fi

printf 'PASS: checker regression runner records exact verdicts\n'
