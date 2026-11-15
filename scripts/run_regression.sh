#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
simv=${SIMV:-"$repo_root/simv"}
regression_list=${REGRESSION_LIST:-"$repo_root/config/regression.list"}
log_dir=${LOG_DIR:-"$repo_root/regression_logs"}
timeout_kill_after=${TIMEOUT_KILL_AFTER:-5s}
checker="$script_dir/check_sim_log.sh"
summary="$log_dir/regression_summary.tsv"

if ! timeout_bin=$(type -P timeout) || [[ ! -x "$timeout_bin" ]]; then
    printf 'FAIL: GNU timeout command not found or not executable\n' >&2
    exit 2
fi
if [[ ! "$timeout_kill_after" =~ ^([1-9][0-9]*([.][0-9]+)?|0[.][0-9]*[1-9][0-9]*)s$ ]]; then
    printf 'FAIL: TIMEOUT_KILL_AFTER must be a positive duration in seconds: %s\n' \
        "$timeout_kill_after" >&2
    exit 2
fi

if [[ ! -f "$simv" || ! -x "$simv" ]]; then
    printf 'FAIL: simulator executable not found or not executable: %s\n' \
        "$simv" >&2
    exit 2
fi
if [[ ! -f "$regression_list" || ! -r "$regression_list" ]]; then
    printf 'FAIL: regression list must be a readable regular file: %s\n' \
        "$regression_list" >&2
    exit 2
fi
if [[ ! -f "$checker" || ! -x "$checker" ]]; then
    printf 'FAIL: simulation log checker not found or not executable: %s\n' \
        "$checker" >&2
    exit 2
fi

if ! mapfile -t matrix_lines <"$regression_list"; then
    printf 'FAIL: cannot read regression list: %s\n' "$regression_list" >&2
    exit 2
fi

declare -a test_names=()
declare -a seeds=()
declare -a timeout_values=()
declare -A seen_test_seeds=()
line_number=0

for line in "${matrix_lines[@]}"; do
    line_number=$((line_number + 1))
    test_name=
    seed=
    timeout_seconds=
    extra=
    read -r test_name seed timeout_seconds extra <<<"$line"

    if [[ -z "$test_name" || "$test_name" == \#* ]]; then
        continue
    fi
    if [[ -z "$seed" || -z "$timeout_seconds" || -n "$extra" ]]; then
        printf 'FAIL: invalid regression row %s: %s\n' \
            "$line_number" "$line" >&2
        exit 2
    fi
    if [[ ! "$test_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf 'FAIL: invalid test name on regression row %s: %s\n' \
            "$line_number" "$test_name" >&2
        exit 2
    fi
    if [[ ! "$seed" =~ ^(0|[1-9][0-9]*)$ ]]; then
        printf 'FAIL: invalid seed on regression row %s: %s\n' \
            "$line_number" "$seed" >&2
        exit 2
    fi
    if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
        printf 'FAIL: invalid timeout on regression row %s: %s\n' \
            "$line_number" "$timeout_seconds" >&2
        exit 2
    fi

    test_seed_key="$test_name:$seed"
    if [[ -n ${seen_test_seeds[$test_seed_key]+present} ]]; then
        printf 'FAIL: duplicate test and seed on regression row %s: %s %s\n' \
            "$line_number" "$test_name" "$seed" >&2
        exit 2
    fi
    seen_test_seeds[$test_seed_key]=1
    test_names+=("$test_name")
    seeds+=("$seed")
    timeout_values+=("$timeout_seconds")
done

if [[ ${#test_names[@]} -eq 0 ]]; then
    printf 'FAIL: regression list contains no tests: %s\n' \
        "$regression_list" >&2
    exit 2
fi

if ! mkdir -p -- "$log_dir"; then
    printf 'FAIL: cannot create log directory: %s\n' "$log_dir" >&2
    exit 2
fi

if ! printf 'test\tseed\trc\tstatus\tparser_rc\tfailure_class\tlog_path\n' \
    >"$summary"; then
    printf 'FAIL: cannot create regression summary: %s\n' "$summary" >&2
    exit 2
fi

declare -a log_files=()
for index in "${!test_names[@]}"; do
    log_file="$log_dir/${test_names[$index]}_${seeds[$index]}.log"
    if ! : >"$log_file"; then
        printf 'FAIL: cannot create simulation log: %s\n' "$log_file" >&2
        exit 2
    fi
    log_files+=("$log_file")
done

overall=0
active_timeout_pid=

terminate_active_simulation() {
    local pid=${active_timeout_pid:-}

    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        return
    fi
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    active_timeout_pid=
}

handle_signal() {
    local signal_rc=$1

    trap - INT TERM
    terminate_active_simulation
    printf 'FAIL: regression runner interrupted\n' >&2
    exit "$signal_rc"
}

trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

for index in "${!test_names[@]}"; do
    test_name=${test_names[$index]}
    seed=${seeds[$index]}
    timeout_seconds=${timeout_values[$index]}

    log_file=${log_files[$index]}
    printf 'RUN: %s seed=%s timeout=%ss\n' \
        "$test_name" "$seed" "$timeout_seconds"

    "$timeout_bin" --signal=TERM --kill-after="$timeout_kill_after" \
        "${timeout_seconds}s" "$simv" \
        "+UVM_TESTNAME=$test_name" "+ntb_random_seed=$seed" \
        >"$log_file" 2>&1 </dev/null &
    active_timeout_pid=$!
    wait "$active_timeout_pid"
    sim_rc=$?
    active_timeout_pid=

    "$checker" "$log_file"
    parser_rc=$?

    if [[ "$sim_rc" -eq 0 && "$parser_rc" -eq 0 ]]; then
        status=PASS
        failure_class=PASS
        printf 'PASS: %s seed=%s rc=%s\n' \
            "$test_name" "$seed" "$sim_rc"
    else
        status=FAIL
        overall=1
        if [[ "$sim_rc" -eq 124 || "$sim_rc" -eq 137 ]]; then
            failure_class=TIMEOUT
        elif [[ "$sim_rc" -ne 0 ]]; then
            failure_class=SIM
        else
            failure_class=LOG
        fi
        printf 'FAIL: %s seed=%s rc=%s parser_rc=%s class=%s\n' \
            "$test_name" "$seed" "$sim_rc" "$parser_rc" \
            "$failure_class"
    fi
    if ! printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$test_name" "$seed" "$sim_rc" "$status" "$parser_rc" \
        "$failure_class" "$log_file" >>"$summary"; then
        printf 'FAIL: cannot append regression summary: %s\n' \
            "$summary" >&2
        exit 2
    fi
done

printf 'SUMMARY: %s\n' "$summary"
if ! cat -- "$summary"; then
    printf 'FAIL: cannot read regression summary: %s\n' "$summary" >&2
    exit 2
fi
exit "$overall"
