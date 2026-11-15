#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

compile_probe() {
  local top="$1"
  local testbench="$2"
  local label="$3"
  local log_file="${tmp_dir}/${label}.compile.log"
  local simv="${tmp_dir}/${label}.simv"

  local compile_status=0
  if ! (
    cd "${tmp_dir}"
    vcs -full64 -sverilog -timescale=1ns/1ps \
      "${repo_root}/rtl/axi_if.sv" "${repo_root}/${testbench}" \
      -top "${top}" -o "${simv}"
  ) >"${log_file}" 2>&1; then
    compile_status=1
  fi

  if grep -E 'ICPSD_W|ICPD_W' "${log_file}" >&2; then
    printf 'FAIL: %s emitted static-driver diagnostics\n' "${label}" >&2
    exit 1
  fi

  if [[ "${compile_status}" -ne 0 ]]; then
    cat "${log_file}" >&2
    exit 1
  fi

  printf '%s\n' "${simv}"
}

real_dut_simv="$(compile_probe axi_real_dut_compile_probe test/integration/axi_real_dut_compile_probe.sv real_dut)"
proxy_simv="$(compile_probe axi_proxy_resolution_tb test/integration/axi_proxy_resolution_tb.sv proxy_resolution)"

proxy_log="${tmp_dir}/proxy_resolution.run.log"
if ! "${proxy_simv}" >"${proxy_log}" 2>&1; then
  cat "${proxy_log}" >&2
  exit 1
fi

if ! grep -q 'AXI_STATIC_DRIVER_PROXY_PASS' "${proxy_log}"; then
  cat "${proxy_log}" >&2
  printf 'FAIL: proxy resolution simulation did not report success\n' >&2
  exit 1
fi

printf 'PASS: real-DUT AXI static-driver probes compiled and resolved correctly\n'
