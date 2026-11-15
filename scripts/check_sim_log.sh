#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 && $# -ne 3 ]]; then
    printf 'usage: %s LOG [EXPECTED_ASSERTION EXPECTED_COUNT]\n' "$0" >&2
    exit 2
fi

log=$1
expected_assertions=${2:-}
expected_counts=${3:-}
checker_completion_marker=AXI_CHECKER_TEST_COMPLETE
declare -a expected_assertion_list=()
declare -a expected_count_list=()
expected_total=0

decimal_add() {
    local left=$1
    local right=$2
    local left_index=$(( ${#left} - 1 ))
    local right_index=$(( ${#right} - 1 ))
    local carry=0
    local result=
    local left_digit
    local right_digit
    local sum

    while [[ "$left_index" -ge 0 || "$right_index" -ge 0 || \
             "$carry" -ne 0 ]]; do
        left_digit=0
        right_digit=0
        if [[ "$left_index" -ge 0 ]]; then
            left_digit=${left:left_index:1}
            left_index=$((left_index - 1))
        fi
        if [[ "$right_index" -ge 0 ]]; then
            right_digit=${right:right_index:1}
            right_index=$((right_index - 1))
        fi
        sum=$((10#$left_digit + 10#$right_digit + carry))
        result="$((sum % 10))$result"
        carry=$((sum / 10))
    done
    printf '%s\n' "$result"
}

if [[ ! -f "$log" ]]; then
    printf 'FAIL: log not found: %s\n' "$log" >&2
    exit 2
fi

if [[ $# -eq 3 ]]; then
    if [[ ! "$expected_assertions" =~ ^AST_[A-Z0-9_]+(,AST_[A-Z0-9_]+)*$ ||
          ! "$expected_counts" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]]; then
        printf 'usage: %s LOG [EXPECTED_ASSERTION EXPECTED_COUNT]\n' "$0" >&2
        exit 2
    fi

    IFS=, read -r -a expected_assertion_list <<<"$expected_assertions"
    IFS=, read -r -a expected_count_list <<<"$expected_counts"
    if [[ ${#expected_assertion_list[@]} -ne \
          ${#expected_count_list[@]} ]]; then
        printf 'FAIL: expected assertion and count lists must have equal lengths\n' >&2
        exit 2
    fi

    declare -A seen_expected_assertions=()
    for index in "${!expected_assertion_list[@]}"; do
        expected_assertion=${expected_assertion_list[$index]}
        if [[ -n ${seen_expected_assertions[$expected_assertion]+present} ]]; then
            printf 'FAIL: duplicate expected assertion: %s\n' \
                "$expected_assertion" >&2
            exit 2
        fi
        seen_expected_assertions[$expected_assertion]=1
        expected_total=$(decimal_add \
            "$expected_total" "${expected_count_list[$index]}")
    done
fi

summary_count=$(awk '
    {
        line = $0
        sub(/\r$/, "", line)
        if (line == "--- UVM Report Summary ---") {
            count++
        }
    }
    END { print count+0 }
' "$log")

if [[ "$summary_count" != 0 ]]; then
    if ! summary_counts=$(awk '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line == "--- UVM Report Summary ---") {
                found = 1
                errors = ""
                fatals = ""
                next
            }
            if (found) {
                split(line, fields)
                if (fields[1] == "UVM_ERROR" && fields[2] == ":") {
                    errors = fields[3]
                }
                if (fields[1] == "UVM_FATAL" && fields[2] == ":") {
                    fatals = fields[3]
                }
            }
        }
        END {
            if (errors !~ /^[0-9]+$/ || fatals !~ /^[0-9]+$/) {
                exit 1
            }
            print errors, fatals
        }
    ' "$log"); then
        printf 'FAIL: missing or invalid final UVM Report Summary\n' >&2
        exit 1
    fi
    read -r uvm_errors uvm_fatals <<<"$summary_counts"
else
    completion_count=$(awk -v marker="$checker_completion_marker" '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line == marker) {
                count++
            }
        }
        END { print count+0 }
    ' "$log")
    if [[ "$completion_count" != 1 ]]; then
        printf 'FAIL: checker-only completion marker count=%s, expected 1\n' \
            "$completion_count" >&2
        exit 1
    fi
    uvm_errors=0
    uvm_fatals=0
fi

diagnostic_counts=$(awk -v assertions="$expected_assertions" '
    BEGIN {
        assertion_count = 0
        if (assertions != "") {
            assertion_count = split(assertions, assertion_list, ",")
        }
    }
    function normalize_diagnostic(line) {
        sub(/\r$/, "", line)
        gsub(/\033\[[0-?]*[ -\/]*[@-~]/, "", line)
        sub(/^[[:space:]]+/, "", line)
        while (line ~ /^\[[^]]+\][[:space:]]*/) {
            sub(/^\[[^]]+\][[:space:]]*/, "", line)
        }
        return line
    }
    function is_runtime_diagnostic(line) {
        return line ~ /^(Error|Fatal):/ || \
            line ~ /^(Error|Fatal)-\[[^]]+\]/
    }
    function has_exact_rule(line, rule) {
        return index(line, "." rule ":") != 0
    }
    {
        line = normalize_diagnostic($0)
        if (is_runtime_diagnostic(line)) {
            runtime_diagnostics++
        }
        if (line ~ /^Error:/ && \
            index(line, "checker/axi_protocol_checker.sv")) {
            checker_errors++
            for (rule_index = 1;
                 rule_index <= assertion_count;
                 rule_index++) {
                if (has_exact_rule(line, assertion_list[rule_index])) {
                    assertion_errors[rule_index]++
                }
            }
        }
        if (index(line, "checker/axi_protocol_checker.sv") && \
            line ~ /started.*failed/) {
            checker_hits++
            for (rule_index = 1;
                 rule_index <= assertion_count;
                 rule_index++) {
                if (has_exact_rule(line, assertion_list[rule_index])) {
                    assertion_hits[rule_index]++
                }
            }
        }
    }
    END {
        printf "%d %d %d %d", checker_errors+0, \
            runtime_diagnostics+0, checker_hits+0, assertion_count
        for (rule_index = 1;
             rule_index <= assertion_count;
             rule_index++) {
            printf " %d %d", assertion_hits[rule_index]+0, \
                assertion_errors[rule_index]+0
        }
        printf "\n"
    }
' "$log")
read -r -a diagnostic_fields <<<"$diagnostic_counts"
checker_errors=${diagnostic_fields[0]}
runtime_diagnostics=${diagnostic_fields[1]}
checker_hits=${diagnostic_fields[2]}
diagnostic_assertion_count=${diagnostic_fields[3]}

if [[ ! "$uvm_errors" =~ ^0+$ || ! "$uvm_fatals" =~ ^0+$ ]]; then
    printf 'FAIL: UVM_ERROR=%s UVM_FATAL=%s\n' \
        "$uvm_errors" "$uvm_fatals" >&2
    exit 1
fi

if [[ -z "$expected_assertions" ]]; then
    if [[ "$runtime_diagnostics" != 0 || "$checker_errors" != 0 || \
          "$checker_hits" != 0 ]]; then
        printf 'FAIL: unexpected runtime diagnostics=%s checker_errors=%s checker_hits=%s\n' \
            "$runtime_diagnostics" "$checker_errors" "$checker_hits" >&2
        exit 1
    fi
else
    if [[ "$diagnostic_assertion_count" != \
          "${#expected_assertion_list[@]}" ]]; then
        printf 'FAIL: internal expected assertion list mismatch\n' >&2
        exit 1
    fi

    label_mismatch=0
    for index in "${!expected_assertion_list[@]}"; do
        assertion_hits=${diagnostic_fields[$((4 + index * 2))]}
        assertion_errors=${diagnostic_fields[$((5 + index * 2))]}
        expected_count=${expected_count_list[$index]}
        if [[ "$assertion_hits" != "$expected_count" || \
              "$assertion_errors" != "$expected_count" ]]; then
            printf 'FAIL: expected %s %s time(s), saw assertion=%s rule_errors=%s\n' \
                "${expected_assertion_list[$index]}" "$expected_count" \
                "$assertion_hits" "$assertion_errors" >&2
            label_mismatch=1
        fi
    done

    if [[ "$label_mismatch" -ne 0 || \
          "$checker_hits" != "$expected_total" || \
          "$checker_errors" != "$expected_total" || \
          "$runtime_diagnostics" != "$expected_total" ]]; then
        printf 'FAIL: expected total=%s, saw checker_hits=%s checker_errors=%s runtime_diagnostics=%s\n' \
            "$expected_total" "$checker_hits" "$checker_errors" \
            "$runtime_diagnostics" >&2
        exit 1
    fi
fi

printf 'PASS: UVM_ERROR=0 UVM_FATAL=0 checker_errors=%s\n' "$checker_errors"
