# Makefile
TOOL ?= vcs
TOP = tb_top
TEST ?= axi_smoke_test
SEED ?= random
RUN_ARGS ?=
REGRESSION_LIST ?= config/regression.list
LOG_DIR ?= regression_logs
CHECKER_SIMV ?= checker_simv
CHECKER_REGRESSION_LIST ?= config/checker_regression.list
CHECKER_LOG_DIR ?= checker_logs

RTL_SRC = rtl/axi_if.sv
SRC_PKG = src/axi_types.sv src/axi_pkg.sv
CHK_SRC = checker/axi_protocol_checker.sv
TB_SRC  = test/tb_top.sv

ALL_SRC = $(RTL_SRC) $(SRC_PKG) $(CHK_SRC) $(TB_SRC)

ifeq ($(TOOL),vcs)
COMP = vcs -full64 -sverilog -ntb_opts uvm-1.2 \
       +incdir+src +incdir+seq_lib +incdir+error_inject +incdir+test \
       -timescale=1ns/1ps -debug_access+all \
       $(ALL_SRC) -o simv
RUN  = ./simv +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) $(RUN_ARGS)
endif

ifeq ($(TOOL),xcelium)
COMP = xrun -compile -uvm -sv \
       +incdir+src +incdir+seq_lib +incdir+error_inject +incdir+test \
       -timescale 1ns/1ps $(ALL_SRC)
RUN  = xrun -R +UVM_TESTNAME=$(TEST) -svseed $(SEED) $(RUN_ARGS)
endif

ifeq ($(TOOL),questa)
COMP = vlog -sv +incdir+src +incdir+seq_lib +incdir+error_inject +incdir+test \
       -timescale "1ns/1ps" $(ALL_SRC)
RUN  = vsim -c $(TOP) +UVM_TESTNAME=$(TEST) -sv_seed $(SEED) -do "run -all" $(RUN_ARGS)
endif

.PHONY: compile run regress checker-compile checker-regress print-sources \
	test-scripts static-driver-test clean

compile:
	$(COMP)

run: compile
	$(RUN)

regress: compile
	REGRESSION_LIST="$(REGRESSION_LIST)" LOG_DIR="$(LOG_DIR)" scripts/run_regression.sh

checker-compile:
ifeq ($(TOOL),vcs)
	vcs -full64 -sverilog -timescale=1ns/1ps \
		checker/axi_protocol_checker.sv test/checker/axi_checker_rule_tb.sv \
		-top axi_checker_rule_tb -o "$(CHECKER_SIMV)"
else
	@printf 'FAIL: checker-compile requires TOOL=vcs (got %s)\n' "$(TOOL)" >&2; exit 2
endif

checker-regress: checker-compile
	CHECKER_SIMV="$(CHECKER_SIMV)" CHECKER_REGRESSION_LIST="$(CHECKER_REGRESSION_LIST)" CHECKER_LOG_DIR="$(CHECKER_LOG_DIR)" scripts/run_checker_regression.sh

print-sources:
	@printf '%s\n' "$(ALL_SRC)"

test-scripts:
	scripts/tests/test_vcs_sources.sh
	scripts/tests/test_check_sim_log.sh
	scripts/tests/test_regression_runner.sh
	scripts/tests/test_checker_regression_runner.sh
	python3 -B scripts/tests/test_axi_drive_ownership_scanner.py
	scripts/tests/test_axi_drive_ownership.sh

static-driver-test:
	scripts/test_static_driver_proxies.sh

clean:
	rm -rf simv simv.daidir checker_simv checker_simv.daidir csrc \
	       regression_logs checker_logs *.vcd *.log *.fsdb xcelium.d INCA_libs \
	       work transcript *.wlf
