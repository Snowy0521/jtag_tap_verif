# ============================================================================
# run_formal.tcl -- Questa Formal (qverify) batch flow. Run via `make formal`
# from the repo root: file lists are repo-root-relative, and the Makefile sets
# MODELSIM so vmap writes modelsim.ini into build/ (see docs/plan.md §2.5).
# ============================================================================
onerror {exit 1}

if {![info exists ::env(MODELSIM)]} {
    puts "run_formal.tcl: MODELSIM is not set. Run 'make formal' from the repo root."
    exit 1
}

vlib build/formal_work
vmap work build/formal_work

vlog -sv -timescale 1ns/1ps +define+QUESTA_FORMAL -f rtl/rtl.f -f formal/formal.f

formal compile -d formal_top

# -auto_constraint_off: trst_n stays a free input after the init sequence, so
# reset can assert at any cycle (otherwise reset properties are vacuous).
formal verify -auto_constraint_off

formal generate report build/formal_report.txt

exit
