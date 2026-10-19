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

FORMAL_F    := formal/formal.f
FORMAL_SRCS := $(shell grep -v '^+' $(FORMAL_F)) formal/jtag_fsm_arcs.svh formal/jtag_checker_defaults.svh

export MODELSIM := $(CURDIR)/$(BUILD)/modelsim.ini

.PHONY: lint lint-verilator lint-slang smoke gen gen-check props-sim formal uvm clean

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

clean:
	rm -rf $(BUILD) obj_dir
