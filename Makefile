# ============================================================================
# Makefile -- run every target from the repo root (docs/plan.md §4.5): the .f file
# lists hold repo-root-relative paths, and all outputs go to build/.
#
#   make lint     verilator --lint-only + slang over rtl/rtl.f
#   make smoke    iverilog directed smoke test (tb/tb_smoke.sv)
#   make clean
#
# Questa targets (sim / regress / formal / mutate / cov) come with the UVM and
# formal code. Each will start with `mkdir -p build`, and run_formal.tcl will
# stop if MODELSIM is not set (i.e. when started outside make).
# ============================================================================

BUILD    := build
RTL_F    := rtl/rtl.f
RTL_SRCS := $(shell cat $(RTL_F))

VERILATOR ?= verilator
SLANG     ?= slang
IVERILOG  ?= iverilog
VVP       ?= vvp

export MODELSIM := $(CURDIR)/$(BUILD)/modelsim.ini

.PHONY: lint lint-verilator lint-slang smoke clean

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

clean:
	rm -rf $(BUILD) obj_dir
