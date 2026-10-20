# ============================================================================
# Makefile -- run every target from the repo root (docs/plan.md §4.5): the .f file
# lists hold repo-root-relative paths, and all outputs go to build/.
#
#   make lint       verilator --lint-only + slang over rtl/rtl.f
#   make smoke      iverilog directed smoke test (tb/tb_smoke.sv)
#   make gen        regenerate formal/jtag_fsm_arcs.svh from docs/design_spec.md
#   make props-sim  formal properties in a random simulation (Verilator, local)
#   make formal     Questa Formal proof run (needs qverify)
#   make uvm        UVM test under Verilator (local): make uvm TEST=jtag_idcode_test SEED=1
#   make sim        UVM test under QuestaSim: make sim TEST=jtag_idcode_test SEED=1
#   make sim-directed  every directed test once under QuestaSim (one build)
#   make clean
#
# Every Questa target starts with `mkdir -p build`; run_formal.tcl stops if
# MODELSIM is not set (i.e. when started outside make).
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

# QuestaSim: UVM 1.2 shipped with Questa (no 1800.2 in the install; the
# testbench only uses API common to both). Code coverage on the RTL only.
VLIB      ?= vlib
VMAP      ?= vmap
VLOG      ?= vlog
VOPT      ?= vopt
VSIM      ?= vsim
QUESTA_UVM_HOME ?= /eda/Siemens/2024-25/RHELx86/QUESTA-CORE-PRIME_2024.3/questasim/verilog_src/uvm-1.2/src
CODE_COV  ?= bcesf
UVM_VERBOSITY ?= UVM_LOW
SIM_COV_DIR := $(BUILD)/cov
DIRECTED  := jtag_reset_test jtag_idcode_test jtag_bypass_test jtag_unused_opcode_test \
             jtag_dft_test jtag_pause_test

FORMAL_F    := formal/formal.f
FORMAL_SRCS := $(shell grep -v '^+' $(FORMAL_F)) formal/jtag_fsm_arcs.svh formal/jtag_checker_defaults.svh

export MODELSIM := $(CURDIR)/$(BUILD)/modelsim.ini

.PHONY: lint lint-verilator lint-slang smoke gen gen-check props-sim formal uvm sim-build sim sim-directed clean

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
	mkdir -p $(BUILD)
	$(QVERIFY) -c -do formal/run_formal.tcl

# UVM under Verilator: rebuilt only when a source changes (the UVM library
# takes about a minute to compile). UVM_NO_DPI: no C side needed.
# Verilator is 2-state: --x-initial unique + rand reset start every flop at a
# random value, the closest stand-in for X, so code that depends on
# uninitialised state fails here instead of first on Questa.
$(BUILD)/uvm/Vtb_top: $(RTL_SRCS) $(TB_SRCS) $(TB_F)
	mkdir -p $(BUILD)
	$(VERILATOR) --binary --timing --timescale 1ns/1ps -j 0 -Wno-fatal -Wno-lint -Wno-style \
	    -Wno-SYMRSVDWORD --x-initial unique +define+UVM_NO_DPI +incdir+$(UVM_HOME) \
	    --top-module tb_top -Mdir $(BUILD)/uvm $(UVM_HOME)/uvm_pkg.sv -f $(RTL_F) -f $(TB_F) \
	    > $(BUILD)/uvm_build.log 2>&1 || (tail -30 $(BUILD)/uvm_build.log; exit 1)

uvm: $(BUILD)/uvm/Vtb_top
	$(BUILD)/uvm/Vtb_top +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED) +verilator+rand+reset+2 | tee $(BUILD)/uvm_$(TEST)_$(SEED).log
	@grep -qE "UVM_ERROR :\s+0" $(BUILD)/uvm_$(TEST)_$(SEED).log && grep -qE "UVM_FATAL :\s+0" $(BUILD)/uvm_$(TEST)_$(SEED).log \
	    || (echo "TEST FAILED: $(TEST) seed $(SEED)"; exit 1)

# UVM under QuestaSim. Three vlog calls: the UVM library, the RTL with +cover
# (so code coverage is collected on the DUT only), then the testbench.
sim-build:
	mkdir -p $(BUILD)
	$(VLIB) $(BUILD)/questa_work
	$(VMAP) work $(BUILD)/questa_work
	$(VLOG) -sv -timescale 1ns/1ps +incdir+$(QUESTA_UVM_HOME) +define+UVM_NO_DPI \
	    $(QUESTA_UVM_HOME)/uvm_pkg.sv
	$(VLOG) -sv -timescale 1ns/1ps +cover=$(CODE_COV) -f $(RTL_F)
	$(VLOG) -sv -timescale 1ns/1ps +incdir+$(QUESTA_UVM_HOME) +define+UVM_NO_DPI -f $(TB_F)
	$(VOPT) +acc tb_top -o tb_top_opt

# One run: -onfinish stop returns to the do script after run_test's $finish,
# so the coverage of the run is saved to build/cov/<test>_<seed>.ucdb.
# Pass/fail from the UVM report summary.
SIM_RUN = mkdir -p $(SIM_COV_DIR); \
	$(VSIM) -c -coverage tb_top_opt +UVM_TESTNAME=$$t -sv_seed $$s +UVM_VERBOSITY=$(UVM_VERBOSITY) \
	    -onfinish stop -l $(BUILD)/sim_$${t}_$$s.log \
	    -do "run -all; coverage save $(SIM_COV_DIR)/$${t}_$$s.ucdb; quit -f" > /dev/null 2>&1; \
	if grep -qE "UVM_ERROR :\s+0" $(BUILD)/sim_$${t}_$$s.log && grep -qE "UVM_FATAL :\s+0" $(BUILD)/sim_$${t}_$$s.log; \
	then echo "PASS: $$t seed $$s"; \
	else echo "FAIL: $$t seed $$s (see $(BUILD)/sim_$${t}_$$s.log)"; fail=1; fi

sim: sim-build
	@fail=0; t=$(TEST); s=$(SEED); $(SIM_RUN); exit $$fail

sim-directed: sim-build
	@fail=0; s=$(SEED); for t in $(DIRECTED); do $(SIM_RUN); done; exit $$fail

clean:
	rm -rf $(BUILD) obj_dir
