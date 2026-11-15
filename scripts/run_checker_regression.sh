#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
invocation_dir=$PWD
simv=${CHECKER_SIMV:-"$repo_root/checker_simv"}
regression_list=${CHECKER_REGRESSION_LIST:-"$repo_root/config/checker_regression.list"}
log_dir=${CHECKER_LOG_DIR:-"$repo_root/checker_logs"}
timeout_kill_after=${TIMEOUT_KILL_AFTER:-5s}
parser="$script_dir/check_sim_log.sh"

[[ "$simv" == /* ]] || simv="$invocation_dir/$simv"
[[ "$regression_list" == /* ]] || regression_list="$invocation_dir/$regression_list"
[[ "$log_dir" == /* ]] || log_dir="$invocation_dir/$log_dir"
summary="$log_dir/checker_regression_summary.tsv"

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
    printf 'FAIL: checker simulator not found or not executable: %s\n' \
        "$simv" >&2
    exit 2
fi
if [[ ! -f "$regression_list" || ! -r "$regression_list" ]]; then
    printf 'FAIL: checker regression list must be a readable regular file: %s\n' \
        "$regression_list" >&2
    exit 2
fi
if [[ ! -f "$parser" || ! -x "$parser" ]]; then
    printf 'FAIL: simulation log checker not found or not executable: %s\n' \
        "$parser" >&2
    exit 2
fi

if ! mapfile -t matrix_lines <"$regression_list"; then
    printf 'FAIL: cannot read checker regression list: %s\n' \
        "$regression_list" >&2
    exit 2
fi

declare -a scenarios=()
declare -a expected_assertions=()
declare -a expected_counts=()
declare -a timeout_values=()
declare -A seen_scenarios=()
line_number=0

for line in "${matrix_lines[@]}"; do
    line_number=$((line_number + 1))
    scenario=
    expected_assertion=
    expected_count=
    timeout_seconds=
    extra=
    read -r scenario expected_assertion expected_count timeout_seconds extra <<<"$line"

    if [[ -z "$scenario" || "$scenario" == \#* ]]; then
        continue
    fi
    if [[ -z "$expected_assertion" || -z "$expected_count" || \
          -z "$timeout_seconds" || -n "$extra" ]]; then
        printf 'FAIL: invalid checker regression row %s: %s\n' \
            "$line_number" "$line" >&2
        exit 2
    fi
    if [[ ! "$scenario" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        printf 'FAIL: invalid scenario on checker regression row %s: %s\n' \
            "$line_number" "$scenario" >&2
        exit 2
    fi
    if [[ "$expected_assertion" == - ]]; then
        if [[ "$expected_count" != 0 ]]; then
            printf 'FAIL: clean checker row %s must use expected fields "- 0"\n' \
                "$line_number" >&2
            exit 2
        fi
    elif [[ ! "$expected_assertion" =~ ^AST_[A-Z0-9_]+(,AST_[A-Z0-9_]+)*$ ||
            ! "$expected_count" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]]; then
        printf 'FAIL: negative checker row %s requires safe AST_* and positive canonical CSV lists\n' \
            "$line_number" >&2
        exit 2
    else
        IFS=, read -r -a row_assertions <<<"$expected_assertion"
        IFS=, read -r -a row_counts <<<"$expected_count"
        if [[ ${#row_assertions[@]} -ne ${#row_counts[@]} ]]; then
            printf 'FAIL: checker row %s assertion/count lists differ in length\n' \
                "$line_number" >&2
            exit 2
        fi
        declare -A seen_row_assertions=()
        for row_assertion in "${row_assertions[@]}"; do
            if [[ -n ${seen_row_assertions[$row_assertion]+present} ]]; then
                printf 'FAIL: duplicate assertion on checker row %s: %s\n' \
                    "$line_number" "$row_assertion" >&2
                exit 2
            fi
            seen_row_assertions[$row_assertion]=1
        done
    fi
    if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
        printf 'FAIL: invalid timeout on checker regression row %s: %s\n' \
            "$line_number" "$timeout_seconds" >&2
        exit 2
    fi
    if [[ -n ${seen_scenarios[$scenario]+present} ]]; then
        printf 'FAIL: duplicate checker scenario on row %s: %s\n' \
            "$line_number" "$scenario" >&2
        exit 2
    fi

    seen_scenarios[$scenario]=1
    scenarios+=("$scenario")
    expected_assertions+=("$expected_assertion")
    expected_counts+=("$expected_count")
    timeout_values+=("$timeout_seconds")
done

if [[ ${#scenarios[@]} -eq 0 ]]; then
    printf 'FAIL: checker regression list contains no scenarios: %s\n' \
        "$regression_list" >&2
    exit 2
fi

if ! mkdir -p -- "$log_dir"; then
    printf 'FAIL: cannot create checker log directory: %s\n' "$log_dir" >&2
    exit 2
fi
if ! printf 'scenario\tsim_rc\tstatus\tparser_rc\tfailure_class\tlog_path\n' \
    >"$summary"; then
    printf 'FAIL: cannot create checker regression summary: %s\n' \
        "$summary" >&2
    exit 2
fi

declare -a log_files=()
for scenario in "${scenarios[@]}"; do
    log_file="$log_dir/$scenario.log"
    if ! : >"$log_file"; then
        printf 'FAIL: cannot create checker simulation log: %s\n' \
            "$log_file" >&2
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
    printf 'FAIL: checker regression runner interrupted\n' >&2
    exit "$signal_rc"
}

finish_with_rc() {
    local result_rc=$1

    printf 'SUMMARY: %s\n' "$summary"
    if ! cat -- "$summary"; then
        printf 'FAIL: cannot read checker regression summary: %s\n' \
            "$summary" >&2
        exit 2
    fi
    exit "$result_rc"
}

trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

for index in "${!scenarios[@]}"; do
    scenario=${scenarios[$index]}
    expected_assertion=${expected_assertions[$index]}
    expected_count=${expected_counts[$index]}
    timeout_seconds=${timeout_values[$index]}
    log_file=${log_files[$index]}

    printf 'RUN: %s timeout=%ss\n' "$scenario" "$timeout_seconds"
    "$timeout_bin" --signal=TERM --kill-after="$timeout_kill_after" \
        "${timeout_seconds}s" "$simv" "+SCENARIO=$scenario" \
        >"$log_file" 2>&1 </dev/null &
    active_timeout_pid=$!
    wait "$active_timeout_pid"
    sim_rc=$?
    active_timeout_pid=

    if [[ ! -f "$log_file" || ! -r "$log_file" ]]; then
        parser_rc=2
    elif [[ "$expected_assertion" == - ]]; then
        "$parser" "$log_file"
        parser_rc=$?
    else
        "$parser" "$log_file" "$expected_assertion" "$expected_count"
        parser_rc=$?
    fi

    if [[ "$sim_rc" -eq 0 && "$parser_rc" -eq 0 ]]; then
        status=PASS
        failure_class=PASS
        printf 'PASS: %s rc=%s\n' "$scenario" "$sim_rc"
    else
        status=FAIL
        if [[ "$parser_rc" -ne 0 && "$parser_rc" -ne 1 ]]; then
            failure_class=INFRA
            overall=2
        elif [[ "$sim_rc" -eq 124 || "$sim_rc" -eq 137 ]]; then
            failure_class=TIMEOUT
            [[ "$overall" -eq 0 ]] && overall=1
        elif [[ "$sim_rc" -ne 0 ]]; then
            failure_class=SIM
            [[ "$overall" -eq 0 ]] && overall=1
        else
            failure_class=LOG
            [[ "$overall" -eq 0 ]] && overall=1
        fi
        printf 'FAIL: %s rc=%s parser_rc=%s class=%s\n' \
            "$scenario" "$sim_rc" "$parser_rc" "$failure_class"
    fi

    if ! printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$scenario" "$sim_rc" "$status" "$parser_rc" \
        "$failure_class" "$log_file" >>"$summary"; then
        printf 'FAIL: cannot append checker regression summary: %s\n' \
            "$summary" >&2
        exit 2
    fi
    if [[ "$overall" -eq 2 ]]; then
        finish_with_rc 2
    fi
done

finish_with_rc "$overall"
