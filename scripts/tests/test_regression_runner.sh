#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runner="$script_dir/../run_regression.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

fixture_dir="$tmp_dir/regression fixture"
simv="$fixture_dir/fake simv"
regression_list="$fixture_dir/regression list.txt"
log_dir="$fixture_dir/regression logs"
calls="$fixture_dir/simv calls.txt"
mkdir -p -- "$fixture_dir"

cat >"$simv" <<'FAKE_SIMV'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_SIMV_CALLS"

case " $* " in
    *" +UVM_TESTNAME=good_test "*)
        uvm_errors=0
        ;;
    *" +UVM_TESTNAME=bad_test "*)
        uvm_errors=1
        ;;
    *" +UVM_TESTNAME=crash_test "*)
        uvm_errors=0
        sim_rc=42
        ;;
    *" +UVM_TESTNAME=stdin_test "*)
        if IFS= read -r polluted_input; then
            printf 'unexpected simulator stdin: %s\n' "$polluted_input" >&2
            exit 9
        fi
        uvm_errors=0
        ;;
    *" +UVM_TESTNAME=hang_test "*)
        printf '%s\n' "$$" >"$HANG_PID_FILE"
        trap '' TERM
        stop_at=$((SECONDS + 3))
        while [[ $SECONDS -lt $stop_at ]]; do
            sleep 0.05 || true
        done
        uvm_errors=0
        ;;
    *" +UVM_TESTNAME=summary_append_test "*)
        uvm_errors=0
        chmod 400 "$SUMMARY_MUTATION_PATH"
        ;;
    *)
        printf 'unexpected test arguments: %s\n' "$*" >&2
        exit 2
        ;;
esac

cat <<EOF
--- UVM Report Summary ---
UVM_ERROR : $uvm_errors
UVM_FATAL : 0
EOF
exit "${sim_rc:-0}"
FAKE_SIMV
chmod +x "$simv"

cat >"$regression_list" <<'EOF'
good_test 11 5
bad_test 12 5
EOF

set +e
FAKE_SIMV_CALLS="$calls" \
SIMV="$simv" \
REGRESSION_LIST="$regression_list" \
LOG_DIR="$log_dir" \
    "$runner" >"$tmp_dir/runner.stdout" 2>"$tmp_dir/runner.stderr"
runner_rc=$?
set -e

if [[ "$runner_rc" -eq 0 ]]; then
    printf 'FAIL: regression runner returned success despite a failing test\n' >&2
    exit 1
fi

summary="$log_dir/regression_summary.tsv"
if [[ ! -f "$summary" ]]; then
    printf 'FAIL: regression summary was not created\n' >&2
    exit 1
fi

expected_summary=$(printf \
    'test\tseed\trc\tstatus\tparser_rc\tfailure_class\tlog_path\n%s\t%s\t%s\t%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    good_test 11 0 PASS 0 PASS "$log_dir/good_test_11.log" \
    bad_test 12 0 FAIL 1 LOG "$log_dir/bad_test_12.log")
if [[ "$(cat -- "$summary")" != "$expected_summary" ]]; then
    printf 'FAIL: unexpected regression summary\n' >&2
    diff -u <(printf '%s\n' "$expected_summary") "$summary" >&2 || true
    exit 1
fi

if [[ $(wc -l <"$calls") -ne 2 ]]; then
    printf 'FAIL: regression runner did not execute every test\n' >&2
    exit 1
fi

if ! grep -Fxq -- '+UVM_TESTNAME=good_test +ntb_random_seed=11' "$calls" ||
   ! grep -Fxq -- '+UVM_TESTNAME=bad_test +ntb_random_seed=12' "$calls"; then
    printf 'FAIL: simulator arguments were not recorded as expected\n' >&2
    exit 1
fi

# A failing parser verdict and a nonzero simulator status must not prevent a
# later test from running. The simulator status must be preserved verbatim.
cat >"$regression_list" <<'EOF'
bad_test 12 5
crash_test 13 5
good_test 11 5
EOF
: >"$calls"
continuation_log_dir="$fixture_dir/continuation logs"

set +e
FAKE_SIMV_CALLS="$calls" \
SIMV="$simv" \
REGRESSION_LIST="$regression_list" \
LOG_DIR="$continuation_log_dir" \
    "$runner" >"$tmp_dir/continuation.stdout" \
    2>"$tmp_dir/continuation.stderr"
runner_rc=$?
set -e

if [[ "$runner_rc" -eq 0 ]]; then
    printf 'FAIL: continuation regression returned success\n' >&2
    exit 1
fi

expected_continuation_summary=$(printf \
    'test\tseed\trc\tstatus\tparser_rc\tfailure_class\tlog_path\n%s\t%s\t%s\t%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    bad_test 12 0 FAIL 1 LOG \
        "$continuation_log_dir/bad_test_12.log" \
    crash_test 13 42 FAIL 0 SIM \
        "$continuation_log_dir/crash_test_13.log" \
    good_test 11 0 PASS 0 PASS \
        "$continuation_log_dir/good_test_11.log")
continuation_summary="$continuation_log_dir/regression_summary.tsv"
if [[ "$(cat -- "$continuation_summary")" != \
      "$expected_continuation_summary" ]]; then
    printf 'FAIL: failures stopped later tests or simulator rc was lost\n' >&2
    diff -u <(printf '%s\n' "$expected_continuation_summary") \
        "$continuation_summary" >&2 || true
    exit 1
fi
if [[ $(wc -l <"$calls") -ne 3 ]]; then
    printf 'FAIL: a failed test prevented a later test from running\n' >&2
    exit 1
fi

cat >"$regression_list" <<'EOF'
invalid_test 14 5 extra
EOF
: >"$calls"

set +e
FAKE_SIMV_CALLS="$calls" \
SIMV="$simv" \
REGRESSION_LIST="$regression_list" \
LOG_DIR="$fixture_dir/invalid row logs" \
    "$runner" >"$tmp_dir/invalid.stdout" 2>"$tmp_dir/invalid.stderr"
runner_rc=$?
set -e

if [[ "$runner_rc" -ne 2 ]]; then
    printf 'FAIL: invalid regression row expected rc=2, got rc=%s\n' \
        "$runner_rc" >&2
    exit 1
fi
if [[ -s "$calls" ]]; then
    printf 'FAIL: invalid regression row invoked the simulator\n' >&2
    exit 1
fi

expect_infrastructure_failure() {
    local description=$1
    local list_path=$2
    local logs_path=$3
    local simulator_path=${4:-$simv}
    local runner_path=${5:-$runner}

    : >"$calls"
    set +e
    FAKE_SIMV_CALLS="$calls" \
    SIMV="$simulator_path" \
    REGRESSION_LIST="$list_path" \
    LOG_DIR="$logs_path" \
        "$runner_path" >"$tmp_dir/infra.stdout" 2>"$tmp_dir/infra.stderr"
    runner_rc=$?
    set -e
    if [[ "$runner_rc" -ne 2 ]]; then
        printf 'FAIL: %s expected rc=2, got rc=%s\n' \
            "$description" "$runner_rc" >&2
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

# no tests
    # still no tests
EOF
expect_infrastructure_failure "comment-only matrix" "$comment_list" \
    "$fixture_dir/comment logs"

valid_infra_list="$fixture_dir/valid-infrastructure.list"
printf 'good_test 11 5\n' >"$valid_infra_list"

unreadable_list="$fixture_dir/unreadable.list"
printf 'good_test 11 5\n' >"$unreadable_list"
chmod 000 "$unreadable_list"
expect_infrastructure_failure "unreadable matrix" "$unreadable_list" \
    "$fixture_dir/unreadable logs"
chmod 600 "$unreadable_list"

expect_infrastructure_failure "non-regular matrix" "$fixture_dir" \
    "$fixture_dir/nonregular logs"
expect_infrastructure_failure "missing matrix" "$fixture_dir/missing.list" \
    "$fixture_dir/missing logs"
expect_infrastructure_failure "missing simulator" "$valid_infra_list" \
    "$fixture_dir/missing simulator logs" "$fixture_dir/missing simv"

log_parent_file="$fixture_dir/not a directory"
: >"$log_parent_file"
expect_infrastructure_failure "log directory creation failure" \
    "$valid_infra_list" "$log_parent_file/child"

header_failure_logs="$fixture_dir/header failure logs"
mkdir -p "$header_failure_logs/regression_summary.tsv"
expect_infrastructure_failure "summary header creation failure" \
    "$valid_infra_list" "$header_failure_logs"

log_file_failure_logs="$fixture_dir/log file failure logs"
mkdir -p "$log_file_failure_logs/good_test_11.log"
expect_infrastructure_failure "simulation log creation failure" \
    "$valid_infra_list" "$log_file_failure_logs"

isolated_scripts="$fixture_dir/isolated scripts"
mkdir -p "$isolated_scripts"
cp -- "$runner" "$isolated_scripts/run_regression.sh"
chmod +x "$isolated_scripts/run_regression.sh"
expect_infrastructure_failure "missing parser" "$valid_infra_list" \
    "$fixture_dir/missing parser logs" "$simv" \
    "$isolated_scripts/run_regression.sh"

: >"$calls"
limited_path="$fixture_dir/limited path"
mkdir -p "$limited_path"
ln -s "$(type -P bash)" "$limited_path/bash"
ln -s "$(type -P dirname)" "$limited_path/dirname"
set +e
PATH="$limited_path" \
FAKE_SIMV_CALLS="$calls" \
SIMV="$simv" \
REGRESSION_LIST="$valid_infra_list" \
LOG_DIR="$fixture_dir/missing timeout logs" \
    "$runner" >"$tmp_dir/missing-timeout.stdout" \
    2>"$tmp_dir/missing-timeout.stderr"
runner_rc=$?
set -e
if [[ "$runner_rc" -ne 2 || -s "$calls" ]]; then
    printf 'FAIL: missing timeout command was not rejected before simulation\n' >&2
    exit 1
fi

: >"$calls"
set +e
TIMEOUT_KILL_AFTER=0s \
FAKE_SIMV_CALLS="$calls" \
SIMV="$simv" \
REGRESSION_LIST="$valid_infra_list" \
LOG_DIR="$fixture_dir/invalid kill-after logs" \
    "$runner" >"$tmp_dir/kill-after.stdout" \
    2>"$tmp_dir/kill-after.stderr"
runner_rc=$?
set -e
if [[ "$runner_rc" -ne 2 || -s "$calls" ]]; then
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

expect_invalid_matrix "path escaping test name" "../escaped 11 5"
expect_invalid_matrix "invalid test identifier" "1bad_test 11 5"
expect_invalid_matrix "nonnumeric seed" "good_test random 5"
expect_invalid_matrix "leading-zero seed" "good_test 011 5"
expect_invalid_matrix "zero timeout" "good_test 11 0"
expect_invalid_matrix "nonnumeric timeout" "good_test 11 fast"
expect_invalid_matrix "extra column" "good_test 11 5 extra"
expect_invalid_matrix "duplicate test and seed" $'good_test 11 5\ngood_test 11 6'
expect_invalid_matrix "late invalid row" $'good_test 11 5\n../escaped 12 5'

cat >"$regression_list" <<'EOF'
stdin_test 20 5
good_test 11 5
EOF
: >"$calls"
stdin_logs="$fixture_dir/stdin isolation logs"

set +e
printf 'polluted runner stdin\n' | \
    FAKE_SIMV_CALLS="$calls" \
    SIMV="$simv" \
    REGRESSION_LIST="$regression_list" \
    LOG_DIR="$stdin_logs" \
    "$runner" >"$tmp_dir/stdin.stdout" 2>"$tmp_dir/stdin.stderr"
runner_rc=${PIPESTATUS[1]}
set -e

if [[ "$runner_rc" -ne 0 ]]; then
    printf 'FAIL: simulator inherited runner stdin, runner rc=%s\n' \
        "$runner_rc" >&2
    exit 1
fi
expected_stdin_summary=$(printf \
    'test\tseed\trc\tstatus\tparser_rc\tfailure_class\tlog_path\n%s\t%s\t%s\t%s\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    stdin_test 20 0 PASS 0 PASS "$stdin_logs/stdin_test_20.log" \
    good_test 11 0 PASS 0 PASS "$stdin_logs/good_test_11.log")
if [[ "$(cat -- "$stdin_logs/regression_summary.tsv")" != \
      "$expected_stdin_summary" ]]; then
    printf 'FAIL: stdin isolation did not preserve the full matrix\n' >&2
    exit 1
fi
if [[ $(wc -l <"$calls") -ne 2 ]]; then
    printf 'FAIL: stdin-reading simulator prevented a later test\n' >&2
    exit 1
fi

cat >"$regression_list" <<'EOF'
hang_test 30 1
good_test 11 5
EOF
: >"$calls"
hang_logs="$fixture_dir/forced timeout logs"
hang_pid_file="$fixture_dir/hang pid"

set +e
timeout --signal=TERM --kill-after=1s 2s \
    env FAKE_SIMV_CALLS="$calls" \
        HANG_PID_FILE="$hang_pid_file" \
        TIMEOUT_KILL_AFTER=0.2s \
        SIMV="$simv" \
        REGRESSION_LIST="$regression_list" \
        LOG_DIR="$hang_logs" \
        "$runner" >"$tmp_dir/timeout.stdout" 2>"$tmp_dir/timeout.stderr"
runner_rc=$?
set -e

if [[ "$runner_rc" -ne 1 ]]; then
    if [[ -f "$hang_pid_file" ]] && \
       kill -0 "$(cat -- "$hang_pid_file")" 2>/dev/null; then
        kill -KILL "$(cat -- "$hang_pid_file")" 2>/dev/null || true
    fi
    printf 'FAIL: forced timeout did not converge and continue, rc=%s\n' \
        "$runner_rc" >&2
    exit 1
fi
if [[ ! -f "$hang_logs/regression_summary.tsv" ]] ||
   ! grep -Eq $'^hang_test\t30\t(124|137)\tFAIL\t1\tTIMEOUT\t' \
       "$hang_logs/regression_summary.tsv" ||
   ! grep -q $'^good_test\t11\t0\tPASS\t0\tPASS\t' \
       "$hang_logs/regression_summary.tsv"; then
    printf 'FAIL: timeout result or later test missing from summary\n' >&2
    exit 1
fi
if kill -0 "$(cat -- "$hang_pid_file")" 2>/dev/null; then
    kill -KILL "$(cat -- "$hang_pid_file")" 2>/dev/null || true
    printf 'FAIL: timed-out simulator process is still running\n' >&2
    exit 1
fi

cat >"$regression_list" <<'EOF'
hang_test 31 20
EOF
: >"$calls"
interrupt_logs="$fixture_dir/interrupt logs"
interrupt_pid_file="$fixture_dir/interrupt pid"

FAKE_SIMV_CALLS="$calls" \
HANG_PID_FILE="$interrupt_pid_file" \
TIMEOUT_KILL_AFTER=0.2s \
SIMV="$simv" \
REGRESSION_LIST="$regression_list" \
LOG_DIR="$interrupt_logs" \
    "$runner" >"$tmp_dir/interrupt.stdout" \
    2>"$tmp_dir/interrupt.stderr" &
runner_pid=$!
for _ in {1..100}; do
    [[ -s "$interrupt_pid_file" ]] && break
    sleep 0.02
done
if [[ ! -s "$interrupt_pid_file" ]]; then
    kill -KILL "$runner_pid" 2>/dev/null || true
    printf 'FAIL: interrupt test simulator did not start\n' >&2
    exit 1
fi
kill -TERM "$runner_pid"
set +e
wait "$runner_pid"
runner_rc=$?
set -e
if [[ "$runner_rc" -ne 143 ]]; then
    printf 'FAIL: interrupted runner expected rc=143, got rc=%s\n' \
        "$runner_rc" >&2
    exit 1
fi
if kill -0 "$(cat -- "$interrupt_pid_file")" 2>/dev/null; then
    kill -KILL "$(cat -- "$interrupt_pid_file")" 2>/dev/null || true
    printf 'FAIL: interrupted runner left its simulator running\n' >&2
    exit 1
fi

cat >"$regression_list" <<'EOF'
summary_append_test 40 5
EOF
append_failure_logs="$fixture_dir/append failure logs"
mkdir -p "$append_failure_logs"
append_failure_summary="$append_failure_logs/regression_summary.tsv"

set +e
FAKE_SIMV_CALLS="$calls" \
SUMMARY_MUTATION_PATH="$append_failure_summary" \
SIMV="$simv" \
REGRESSION_LIST="$regression_list" \
LOG_DIR="$append_failure_logs" \
    "$runner" >"$tmp_dir/append.stdout" 2>"$tmp_dir/append.stderr"
runner_rc=$?
set -e
chmod 600 "$append_failure_summary"

if [[ "$runner_rc" -ne 2 ]]; then
    printf 'FAIL: summary append failure expected rc=2, got rc=%s\n' \
        "$runner_rc" >&2
    exit 1
fi

cat >"$regression_list" <<'EOF'
good_test 41 5
EOF
read_failure_logs="$fixture_dir/read failure logs"
mkdir -p "$read_failure_logs"
read_failure_summary="$read_failure_logs/regression_summary.tsv"
: >"$read_failure_summary"
chmod 200 "$read_failure_summary"

set +e
FAKE_SIMV_CALLS="$calls" \
SIMV="$simv" \
REGRESSION_LIST="$regression_list" \
LOG_DIR="$read_failure_logs" \
    "$runner" >"$tmp_dir/read.stdout" 2>"$tmp_dir/read.stderr"
runner_rc=$?
set -e
chmod 600 "$read_failure_summary"
if [[ "$runner_rc" -ne 2 ]]; then
    printf 'FAIL: summary read failure expected rc=2, got rc=%s\n' \
        "$runner_rc" >&2
    exit 1
fi

printf 'PASS: regression runner records all tests and returns failure\n'
