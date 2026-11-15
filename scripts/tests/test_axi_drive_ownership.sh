#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
axi_if="${repo_root}/rtl/axi_if.sv"
scanner="${repo_root}/scripts/tests/axi_drive_ownership_scan.py"
sources=(
  "${repo_root}/src/axi_master_driver.sv"
  "${repo_root}/src/axi_slave_driver.sv"
  "${repo_root}/test/axi_agent_topology_test.sv"
  "${repo_root}/test/axi_response_lifecycle_test.sv"
)
root_specs=(
  "vif"
  "vif"
  "cfg.vif"
  "vif,cfg.vif"
)

fail=0
policy_violation_status=3

if ! command -v python3 >/dev/null 2>&1; then
  printf 'ERROR: python3 is required by the AXI ownership guard\n' >&2
  exit 2
fi

for required_file in "${scanner}" "${axi_if}" "${sources[@]}"; do
  if [[ ! -r "${required_file}" ]]; then
    printf 'ERROR: required readable file is missing: %s\n' "${required_file}" >&2
    exit 2
  fi
done

if python3 "${scanner}" check-interface "${axi_if}"; then
  :
else
  status=$?
  if [[ "${status}" -eq "${policy_violation_status}" ]]; then
    fail=1
  else
    printf 'ERROR: interface ownership scan failed with status %s\n' "${status}" >&2
    exit 2
  fi
fi

for index in "${!sources[@]}"; do
  source="${sources[${index}]}"
  IFS=',' read -r -a scan_roots <<< "${root_specs[${index}]}"
  root_args=()
  for root in "${scan_roots[@]}"; do
    root_args+=(--root "${root}")
  done
  if python3 "${scanner}" scan-writes "${root_args[@]}" "${source}"; then
    :
  else
    status=$?
    if [[ "${status}" -eq "${policy_violation_status}" ]]; then
      printf 'FAIL: direct procedural public-signal write in %s\n' "${source}" >&2
      fail=1
    else
      printf 'ERROR: ownership scan failed for %s with status %s\n' \
        "${source}" "${status}" >&2
      exit 2
    fi
  fi
done

if python3 "${scanner}" scan-writes --include-bare "${axi_if}"; then
  :
else
  status=$?
  if [[ "${status}" -eq "${policy_violation_status}" ]]; then
    printf 'FAIL: bare public-signal assignment in rtl/axi_if.sv\n' >&2
    fail=1
  else
    printf 'ERROR: interface write scan failed with status %s\n' "${status}" >&2
    exit 2
  fi
fi

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi

printf 'PASS: AXI public-drive ownership structure is enforced\n'
