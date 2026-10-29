# ============================================================================
# Makefile -- run every target from the repo root (docs/plan.md §4.5): the .f file
# lists hold repo-root-relative paths, and all outputs go to build/.
#
#   make check      BEFORE EVERY COMMIT: lint, smoke, gen-check, props-sim and
#                   regress SEEDS=5, all local (about a minute). A change that
#                   was only run on one simulator must not be committed.
#   make lint       verilator --lint-only + slang over rtl/rtl.f
#   make smoke      iverilog directed smoke test (tb/tb_smoke.sv)
#   make gen        regenerate formal/jtag_fsm_arcs.svh from docs/design_spec.md
#   make props-sim  formal properties in a random simulation (Verilator, local)
#   make formal     Questa Formal proof run (needs qverify)
#   make uvm        UVM test under Verilator (local): make uvm TEST=jtag_idcode_test SEED=1
#   make sim        UVM test under QuestaSim: make sim TEST=jtag_idcode_test SEED=1
#   make sim-directed  every directed test once under QuestaSim (one build)
#   make regress    directed tests + random test on SEEDS seeds, Verilator, merged TB coverage
#   make regress-questa  the same on QuestaSim, plus vcover merge (sign-off)
#   make mutate     mutation testing (mutations/*.patch): make mutate [ONLY=M05,M16] [MUT_SEEDS=5]
#                   (Verilator if on PATH, else QuestaSim; Questa Formal if qverify is on PATH)
#   make clean
#
# Every Questa target starts with `mkdir -p build`; run_formal.tcl stops if
# MODELSIM is not set (i.e. when started outside make).
#
# Questa outputs, all under build/ (nothing is written to the repo root):
#   build/modelsim.ini, build/questa_work/, build/formal_work/   libraries
#   build/formal/   qverify -od: qverify.log, formal_*.rpt / *.log,
#                   formal_report.txt, propcheck.db/, .qverify/, qverify_cmds.tcl
#   build/sim/      vlog / vopt logs, <test>_<seed>.log, summary.log, tr_db.log
#                   (vsim runs inside build/sim/ so its scratch files stay there)
#   build/cov/      <test>_<seed>.ucdb
# ============================================================================

BUILD    := build
RTL_F    := rtl/rtl.f
RTL_SRCS := $(shell cat $(RTL_F))

VERILATOR ?= verilator
SLANG     ?= slang
IVERILOG  ?= iverilog
VVP       ?= vvp
QVERIFY   ?= qverify
PYTHON    ?= python3

TB_F     := tb/tb.f
TB_SRCS  := $(wildcard tb/*.sv tb/sequences/*.sv tb/tests/*.sv)
UVM_HOME ?= $(HOME)/tools/uvm-kit/1800.2-2020.3.1/src
TEST     ?= jtag_idcode_test
SEED     ?= 1
SEEDS    ?= 20
PLUSARGS ?=

# QuestaSim: UVM 1.2 shipped with Questa (no 1800.2 in the install; the
# testbench only uses API common to both, so it runs on UVM 1.2 here and on
# 1800.2-2020 under Verilator). Code coverage on the RTL only.
# QUESTA_HOME: the questasim directory; taken from the vsim on PATH if not set.
VLIB      ?= vlib
VMAP      ?= vmap
VLOG      ?= vlog
VOPT      ?= vopt
VSIM      ?= vsim
QUESTA_HOME     ?= $(abspath $(dir $(shell which vsim 2>/dev/null))/..)
QUESTA_UVM_HOME ?= $(QUESTA_HOME)/verilog_src/uvm-1.2/src
CODE_COV  ?= bcesf
UVM_VERBOSITY ?= UVM_LOW
FORMAL_DIR  := $(BUILD)/formal
SIM_DIR     := $(BUILD)/sim
SIM_COV_DIR := $(BUILD)/cov
DIRECTED  := jtag_reset_test jtag_idcode_test jtag_bypass_test jtag_unused_opcode_test \
             jtag_dft_test jtag_pause_test

FORMAL_F    := formal/formal.f
FORMAL_SRCS := $(shell grep -v '^+' $(FORMAL_F)) formal/jtag_fsm_arcs.svh formal/jtag_checker_defaults.svh formal/jtag_binds.svh
# The checker modules alone (formal.f without the formal harness), bound into
# the UVM DUT by tb_top.sv when JTAG_SIM_CHECKERS is defined
CHECKER_SRCS := $(filter-out formal/formal_top.sv,$(shell grep -v '^+' $(FORMAL_F)))
# UVM_CHECKERS=no builds the UVM bench without them: black-box simulation only
# (the mutation flow scores simulation that way, and formal separately)
UVM_CHECKERS ?= yes
ifeq ($(UVM_CHECKERS),yes)
CHECKERS     := +incdir+formal +define+JTAG_SIM_CHECKERS $(CHECKER_SRCS)
else
CHECKERS     :=
endif

export MODELSIM := $(CURDIR)/$(BUILD)/modelsim.ini

.PHONY: check lint lint-verilator lint-slang smoke gen gen-check props-sim formal uvm uvm-build sim-build sim sim-run sim-directed regress regress-questa mutate clean

# Pre-commit check: every local flow, stops at the first failure
check:
	$(MAKE) lint
	$(MAKE) smoke
	$(MAKE) gen-check
	$(MAKE) props-sim
	$(MAKE) regress SEEDS=5
	@echo "CHECK PASSED: lint, smoke, gen-check, props-sim, regress (5 seeds)"

lint: lint-verilator lint-slang

lint-verilator:
	$(VERILATOR) --lint-only -Wall --timing --top-module jtag_tap_top -f $(RTL_F)

lint-slang:
	$(SLANG) --top jtag_tap_top -f $(RTL_F)

smoke: $(RTL_SRCS) tb/tb_smoke.sv
	mkdir -p $(BUILD)
	$(IVERILOG) -g2012 -Wall -Wno-timescale -o $(BUILD)/tb_smoke.vvp -c $(RTL_F) tb/tb_smoke.sv
	$(VVP) -n $(BUILD)/tb_smoke.vvp | tee $(BUILD)/tb_smoke.log
	@grep -q "SMOKE TEST PASSED" $(BUILD)/tb_smoke.log

gen:
	$(PYTHON) scripts/gen_fsm_props.py

gen-check:
	$(PYTHON) scripts/gen_fsm_props.py --check

props-sim: gen-check $(RTL_SRCS) $(FORMAL_SRCS) formal/props_sim.sv
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --assert --timing --timescale 1ns/1ps -Wno-fatal -Wno-lint -Wno-style \
	    --top-module props_sim -Mdir $(BUILD)/props_sim -f $(RTL_F) -f $(FORMAL_F) formal/props_sim.sv > $(BUILD)/props_sim_build.log
	$(BUILD)/props_sim/Vprops_sim | tee $(BUILD)/props_sim.log
	@grep -q "PROPS SIM DONE" $(BUILD)/props_sim.log

formal: gen-check
	mkdir -p $(FORMAL_DIR)
	$(QVERIFY) -c -od $(FORMAL_DIR) -do formal/run_formal.tcl

# UVM under Verilator: rebuilt only when a source changes (the UVM library
# takes about a minute to compile). UVM_NO_DPI: no C side needed.
# Verilator is 2-state: --x-initial unique + rand reset start every flop at a
# random value, the closest stand-in for X, so code that depends on
# uninitialised state fails here instead of first on Questa.
# The formal checkers are bound in too (--assert): a failing property stops
# the simulation, so the UVM summary is missing and the run counts as failed.
$(BUILD)/uvm/Vtb_top: $(RTL_SRCS) $(TB_SRCS) $(TB_F) $(FORMAL_SRCS)
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing --assert --timescale 1ns/1ps -j 0 -Wno-fatal -Wno-lint -Wno-style \
	    -Wno-SYMRSVDWORD --x-initial unique +define+UVM_NO_DPI +incdir+$(UVM_HOME) \
	    --top-module tb_top -Mdir $(BUILD)/uvm $(UVM_HOME)/uvm_pkg.sv -f $(RTL_F) $(CHECKERS) -f $(TB_F) \
	    > $(BUILD)/uvm_build.log 2>&1 || (tail -30 $(BUILD)/uvm_build.log; exit 1)

uvm-build: $(BUILD)/uvm/Vtb_top

uvm: $(BUILD)/uvm/Vtb_top
	$(BUILD)/uvm/Vtb_top +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED) +verilator+rand+reset+2 $(PLUSARGS) | tee $(BUILD)/uvm_$(TEST)_$(SEED).log
	@grep -qE "UVM_ERROR :\s+0" $(BUILD)/uvm_$(TEST)_$(SEED).log && grep -qE "UVM_FATAL :\s+0" $(BUILD)/uvm_$(TEST)_$(SEED).log \
	    && ! grep -q "%Error" $(BUILD)/uvm_$(TEST)_$(SEED).log \
	    || (echo "TEST FAILED: $(TEST) seed $(SEED)"; exit 1)

# UVM under QuestaSim. Three vlog calls: the UVM library, the RTL with +cover
# (so code coverage is collected on the DUT only), then the formal checkers and
# the testbench. UVM_NO_DPI is not needed on Questa (it has DPI); it is kept so
# both simulators run the same UVM configuration (the test name is read with
# $value$plusargs in tb_top either way).
# The library is mapped with an absolute path, so vsim finds it from build/sim/.
sim-build:
	mkdir -p $(SIM_DIR)
	$(VLIB) $(BUILD)/questa_work
	$(VMAP) work $(CURDIR)/$(BUILD)/questa_work
	$(VLOG) -sv -timescale 1ns/1ps +incdir+$(QUESTA_UVM_HOME) +define+UVM_NO_DPI \
	    -l $(SIM_DIR)/vlog_uvm.log $(QUESTA_UVM_HOME)/uvm_pkg.sv
	$(VLOG) -sv -timescale 1ns/1ps +cover=$(CODE_COV) -l $(SIM_DIR)/vlog_rtl.log -f $(RTL_F)
	$(VLOG) -sv -timescale 1ns/1ps +incdir+$(QUESTA_UVM_HOME) +define+UVM_NO_DPI \
	    -l $(SIM_DIR)/vlog_tb.log $(CHECKERS) -f $(TB_F)
	$(VOPT) +acc tb_top -o tb_top_opt -l $(SIM_DIR)/vopt.log

# One run, inside build/sim/ (vsim writes scratch files such as tr_db.log to
# its working directory): -onfinish stop returns to the do script after
# run_test's $finish, so the coverage of the run is saved to
# build/cov/<test>_<seed>.ucdb. Pass/fail from the UVM report summary, and no
# simulator error: a failing bound property reports "** Error" (not UVM_ERROR)
# on Questa. Each result is also appended to build/sim/summary.log.
SIM_RUN = mkdir -p $(SIM_COV_DIR); log=$(SIM_DIR)/$${t}_$$s.log; \
	(cd $(SIM_DIR) && $(VSIM) -c -coverage tb_top_opt +UVM_TESTNAME=$$t -sv_seed $$s +UVM_VERBOSITY=$(UVM_VERBOSITY) $(PLUSARGS) \
	    -onfinish stop -l $(CURDIR)/$$log \
	    -do "run -all; coverage save $(CURDIR)/$(SIM_COV_DIR)/$${t}_$$s.ucdb; quit -f") > /dev/null 2>&1; \
	if grep -qE "UVM_ERROR :\s+0" $$log && grep -qE "UVM_FATAL :\s+0" $$log \
	    && ! grep -qE "\*\* (Error|Fatal)" $$log; \
	then echo "PASS: $$t seed $$s" | tee -a $(SIM_DIR)/summary.log; \
	else echo "FAIL: $$t seed $$s (see $$log)" | tee -a $(SIM_DIR)/summary.log; fail=1; fi

sim: sim-build
	@fail=0; t=$(TEST); s=$(SEED); $(SIM_RUN); exit $$fail

sim-directed: sim-build
	@fail=0; s=$(SEED); for t in $(DIRECTED); do $(SIM_RUN); done; exit $$fail

# One run without rebuilding (after sim-build); used by scripts/regress.py
sim-run:
	@fail=0; t=$(TEST); s=$(SEED); $(SIM_RUN); exit $$fail

regress: gen-check
	$(PYTHON) scripts/regress.py --sim verilator --seeds $(SEEDS)

regress-questa:
	$(PYTHON) scripts/regress.py --sim questa --seeds $(SEEDS)

# Mutation testing: every patch in mutations/ in a throwaway copy, scored by
# black-box simulation and by formal (Questa) or the props-sim proxy
MUT_SEEDS ?= 5
mutate: gen-check
	$(PYTHON) scripts/run_mutations.py --seeds $(MUT_SEEDS) $(if $(ONLY),--only $(ONLY))

clean:
	rm -rf $(BUILD) obj_dir
