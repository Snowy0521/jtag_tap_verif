# ============================================================================
# run_formal.tcl -- Questa Formal (qverify) batch flow. Run via `make formal`
# from the repo root: file lists are repo-root-relative, and the Makefile sets
# MODELSIM so vmap writes modelsim.ini into build/ (see docs/plan.md §2.5).
# The Makefile also passes `-od build/formal`, so every qverify output (logs,
# .rpt files, propcheck.db, .qverify/, qverify_cmds.tcl) lands there.
# ============================================================================
onerror {exit 1}

if {![info exists ::env(MODELSIM)]} {
    puts "run_formal.tcl: MODELSIM is not set. Run 'make formal' from the repo root."
    exit 1
}

# Absolute library path in modelsim.ini, so it resolves from any directory
vlib build/formal_work
vmap work [pwd]/build/formal_work

vlog -sv -timescale 1ns/1ps +define+QUESTA_FORMAL -f rtl/rtl.f -f formal/formal.f

formal compile -d formal_top

# -auto_constraint_off: trst_n stays a free input after the init sequence, so
# reset can assert at any cycle (otherwise reset properties are vacuous).
formal verify -auto_constraint_off

formal generate report [pwd]/build/formal/formal_report.txt

exit
