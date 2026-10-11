# Verification plan

How the design in [design_spec.md](design_spec.md) is verified. Overview, how to run and results: [README.md](../README.md).

---

## 1. Sampling conventions

The clock edge of every register is in spec §2. This section fixes how the checkers and monitors sample them.

**What a `@(posedge tck)` assertion sees.** SVA samples in the preponed region, i.e. the values just *before* the rising edge. Example: a DFT write in Update-DR.

![Waveform of a DFT write in Update-DR: test_mode changes at the falling edge, and the rising edge that follows still samples state == UPDATE_DR](img/dft_write_timing.svg)

So the update rule is written **without `$past` on the state**:
`$changed(test_mode) |-> (state == UPDATE_DR && ir == OP_DFT_CTRL) || state == TEST_LOGIC_RESET`.
The same holds for the IR update register (Update-IR) and for the Test-Logic-Reset clear: at the first rising edge *after* entering Test-Logic-Reset, the sampled state is TLR and the update registers are already cleared, so `state == TEST_LOGIC_RESET |-> ir == OP_IDCODE` holds with no delay.

TDO: in the first Shift-xR cycle, the falling edge drives `tdo = shift[0]`; the next rising edge (still in Shift-xR) is where the tester samples it and where the DUT shifts. So at the *n*-th rising edge in Shift-xR, sampled `tdo` is bit *n−1* of the captured value. The formal checkers sample TDO at the rising edge (chosen over a `negedge tck` clock, so all data properties share one clock), and the edge-only properties in 2.2 check separately that TDO never changes on a rising edge.

---

## 2. Formal verification

Aim for the same sign-off as the AXI4-Lite project: **every assertion a full proof, every cover reached, no assumptions.** TMS, TDI, `trst_n` and `mbist_fail_i` are all free inputs (every input sequence is legal JTAG); the only constraint is qverify's reset init sequence. Symbolic variables need no constraint either (see the IDCODE check in 2.2).

**Checker conventions (apply to every file in `formal/`):**
- Every checker register (shadow registers, counters, reference state) has `trst_n` as its asynchronous reset and resets to the value the **spec** defines, never to whatever the RTL does.
- Every checker module starts with `` `include "jtag_checker_defaults.svh" ``: `default clocking cb @(posedge tck)` and `default disable iff (!trst_n || trst_seen)`, so no property can forget its reset. `trst_seen` stays 1 from any `trst_n` assertion until the next rising edge, so a reset pulse that starts and ends between two rising edges still disables the attempts it interrupts. A property on another edge names its clock explicitly (e.g. `@(negedge tck)`); the default `disable iff` still applies. The async-reset checks (2.1) are deferred immediate assertions, which the defaults do not affect.
- Checker counters are wide enough to saturate at their limit (e.g. `$clog2(MBIST_CYCLES + 1)` bits) and stop there.

These matter because the sign-off run leaves `trst_n` free (`-auto_constraint_off`, 2.5): a mid-scan or mid-MBIST reset clears the DUT, and a checker that kept its state would fail falsely.

### 2.1 Blackbox FSM checks

In `formal/jtag_tap_fsm_props.sv`, plus `formal/jtag_fsm_arcs.svh`, which `scripts/gen_fsm_props.py` generates from the state table in the spec.

- **Independent next-state model:** a function `next_state(state, tms)` written separately from the RTL (straight from the spec's state table), and
  `a_next_state: assert property (@(posedge tck) disable iff (!trst_n) 1 |=> state == next_state($past(state), $past(tms)));`
- **Per-arc assertions and covers:** `scripts/gen_fsm_props.py` reads the spec's state table and generates `jtag_fsm_arcs.svh` with one assertion and one cover per arc (32 + 32), e.g.
  `a_arc_shift_dr_0: assert property (@(posedge tck) disable iff (!trst_n) (state == SHIFT_DR && !tms) |=> state == SHIFT_DR);`
  The covers are required for sign-off. The per-arc assertions duplicate `a_next_state`, but they name the exact broken arc in the mutation table, and the generator makes them free.
- **Reset reachability:**
  `a_tms5_reset: assert property (@(posedge tck) disable iff (!trst_n) tms[*5] |=> state == TEST_LOGIC_RESET);`
- **Async reset:** cannot live under `disable iff (!trst_n)`. Give it its own property, e.g. a deferred immediate assertion `assert final (trst_n || state == TEST_LOGIC_RESET);` (same for `ir == OP_IDCODE` and DFT outputs = 0 while `trst_n` is low).
- **Legal encoding:** the state register always holds one of the 16 legal values.

### 2.2 Register protocol checks

In `formal/jtag_reg_props.sv`.

- `a_capture_ir_01`: after Capture-IR, `ir_sr[1:0] == 2'b01`.
- `a_ir_stable`: the active instruction changes only after Update-IR (falling edge) or in Test-Logic-Reset.
- `a_reset_idcode`: in Test-Logic-Reset, the active instruction is IDCODE.
- `a_tdo_en`: `tdo_en` is high only in Shift-IR / Shift-DR.
- `a_unused_is_bypass`: any opcode not in the table selects BYPASS.
- **End-to-end IDCODE check:** a small checker counts shift cycles since Capture-DR with IDCODE active and asserts `tdo == IDCODE_VAL[k]` at the shift where `cnt == k`. Use a **symbolic bit index** so one proof covers all 32 bits, with the same mechanism as the AXI project's `sym_idx` (free initial value in formal, constant by construction; random per seed in simulation):
  ```systemverilog
  logic [4:0] k;                                   // 5 bits: range is exactly 0..31, no k < 32 assumption
  `ifdef QUESTA_FORMAL
    always_ff @(posedge tck) k <= k;               // no reset: formal picks any initial value
  `else
    initial k = 5'($urandom_range(31, 0));
  `endif
  ```
  The `ifdef` is required: writing `k` from both `always_ff` and `initial` is a compile error.
- **End-to-end BYPASS check:** in Shift-DR with BYPASS active, the first bit out is 0 and each later bit equals TDI from the previous shift.

TDO is sampled at the rising edge (section 1). A rising-edge data check cannot see *when* within the cycle TDO changed, so the edges get their own properties:

- **Edge-only properties (shadow registers):** each falling-edge signal gets a checker shadow copy taken at the rising edge, and a falling-edge assertion checks that the signal has not moved since:
  ```systemverilog
  logic tdo_at_rise;
  always_ff @(posedge tck or negedge trst_n)
    if (!trst_n) tdo_at_rise <= 1'b0;                       // spec reset value of tdo (R18), not the RTL's
    else         tdo_at_rise <= tdo;                        // value held at the rising edge (changes only at the falling edge in correct RTL)
  a_tdo_no_rise_change: assert property (@(negedge tck) disable iff (!trst_n) tdo == tdo_at_rise);
  ```
  Correct RTL keeps the signal stable from rise to fall, so this holds; a signal that moves on the rising edge breaks it (M4, M17). The shadow resets to the value the **spec** defines (`tdo` and `tdo_en` → 0, IR → IDCODE, DFT → 0; spec R9, R14, R18), so a mutant with a wrong reset value is caught rather than copied. The shadow's own async reset is the `trst_n` escape term: an async clear between rise and fall clears DUT and shadow alike, so the free-reset run (`-auto_constraint_off`) gives no false fail. Each property uses a single clock, and nothing depends on `$global_clock` support.
  Applied to: `tdo`, `tdo_en`, the IR update register, and the DFT update registers `test_mode`, `scan_en`, `mbist_start`. **Not** to `mbist_done` / `mbist_pass`: the MBIST stub runs on the rising edge (spec §2), so these change on the rising edge in correct RTL.

### 2.3 DFT and MBIST checks

In `formal/jtag_dft_props.sv`.

- `a_dft_update_only`: `test_mode`, `scan_en`, `mbist_start` change only after Update-DR with DFT_CTRL active, or on reset.
- `a_dft_reset_functional`: Test-Logic-Reset → all DFT outputs are 0.
- `a_scan_en_safe`: `scan_en |-> test_mode`.
- `a_mbist_done_capture`: in Capture-DR with DFT_CTRL active, bits 3/4 of the shift register equal `mbist_done` / `mbist_pass`.
- `a_reserved_zero`: bits 7:5 always capture 0 and have no effect.
- **MBIST stub (R19–R21)**, with `MBIST_CYCLES = 4` set from `formal_top`:
  - `a_mbist_done_exact`: a checker counter (`$clog2(MBIST_CYCLES + 1)` bits, async reset on `trst_n`, per the checker conventions above) counts rising edges that sample `mbist_start = 1`, clears when `mbist_start = 0`, and saturates at `MBIST_CYCLES`; `mbist_done == (cnt >= MBIST_CYCLES)` at every rising edge. This pins the exact cycle count (catches M18).
  - `a_mbist_clear`: `!mbist_start |=> !mbist_done && !mbist_pass`.
  - `a_mbist_hold`: `mbist_done && mbist_start |=> $stable({mbist_done, mbist_pass})` (catches M19, M20).
  - `a_mbist_pass_value`: `$rose(mbist_done) |-> mbist_pass == !$past(mbist_fail_i)`.

### 2.4 Covers

In `formal/jtag_covers.sv`.

- Every one of the 16 states reached; every one of the 32 arcs taken (state and arc covers generated, see 2.1).
- A full IR scan followed by a full 32-bit IDCODE read.
- A scan that goes through Pause-DR and Exit2-DR back into Shift-DR.
- DFT sequence: write `test_mode=1, mbist_start=1`, wait for `mbist_done`, read back pass.

### 2.5 Questa Verify flow

`formal/formal_top.sv` instantiates the DUT and binds the checkers; `formal/formal.f` lists the files; `formal/run_formal.tcl` runs the flow.

Before each Questa run, `make props-sim` runs the same checkers in a random Verilator simulation (`formal/props_sim.sv`). It is not a proof, but it catches compile errors and wrong properties locally. Verilator treats `assert final` as a plain immediate assertion, so the async-reset checks have a simulation-only variant under `ifdef VERILATOR`.

Based on the known-working `axi4lite_uvm_questa/sim/formal_questa.do`, which uses no `netlist` commands:

```tcl
onerror {exit 1}
vlib build/formal_work                ;# own library, separate from the simulation flow (vlog-13233)
vmap work build/formal_work
vlog -sv -timescale 1ns/1ps +define+QUESTA_FORMAL -f rtl/rtl.f -f formal/formal.f   ;# run from the repo root, see below
formal compile -d formal_top
formal verify -auto_constraint_off    ;# see below
formal generate report build/formal_report.txt
exit
```

**Reset:** by default qverify pins the reset inactive after its init sequence, which makes every `!trst_n |-> ...` property vacuous and never exercises mid-scan `trst_n` (confirmed in the AXI project's script comments). `-auto_constraint_off` makes `trst_n` a free input after init, so reset can hit at any cycle. This is the single sign-off run; the `disable iff (!trst_n)` properties still prove, and the async-reset properties become non-vacuous. Check the vacuity / cover results for the reset properties in the report.

**No no-assumption run:** the AXI project needed `formal-verify-noassume` because its environment had `assume property` constraints on the master. This environment has none (see the sign-off rule above), so that run would be identical to the main one and is dropped.

**File lists and run directory:** with `vlog -f` (and `verilator -f`, `iverilog -c`), relative paths inside a `.f` file resolve against the **current directory**, not the `.f` file's location. So every `.f` entry is written relative to the **repo root** (e.g. `rtl/jtag_pkg.sv`), and every flow (Makefile targets, `run_formal.tcl`, `regress.py`, `run_mutations.py`) runs with the repo root as its working directory. Libraries (`build/formal_work`, `build/questa_work`) and reports (`build/formal_report.txt`) go to `build/`. The Makefile exports `MODELSIM=$(CURDIR)/build/modelsim.ini`, as the AXI Makefile does, so `vmap` writes `modelsim.ini` there too. Tool scratch files that Questa always writes to the working directory (`transcript`, `.qverify/`, `propcheck.db/`) stay in the repo root; all are git-ignored. This works the same for all three tools, unlike `-F`, which iverilog does not offer in the same form.

**Results table in README.md:** number of assertions proven / total, covers reached / total, max proof depth, run time.

---

## 3. UVM environment

### 3.1 Transactions

All UVM files live in `tb/`; `tb/tb.f` lists them.

Stimulus and observation are separate classes: the driver never fills in results, and the scoreboard never sees a driver object.

```systemverilog
// Driver stimulus (sequence item)
class jtag_seq_item extends uvm_sequence_item;
  typedef enum {IR_SCAN, DR_SCAN, RESET_TMS, RESET_TRST, IDLE, TCK_STOP} kind_e;
  rand kind_e        kind;
  rand bit           tdi_q[$];     // shifted in, LSB first; length = number of bits shifted (no 64-bit limit)
  rand bit           use_pause;    // go through Pause-xR mid-shift
  rand int unsigned  pause_at;     // shift index where the pause happens
  rand int unsigned  idle_cycles;  // also TCK-stopped cycles for TCK_STOP
  ...
endclass

// Monitor result (analysis transaction), built only from pin activity
class jtag_scan_txn extends uvm_sequence_item;
  typedef enum {IR, DR} scan_e;
  scan_e        scan;
  tap_state_e   path[$];           // observed state sequence of the scan
  bit           tdi_q[$];
  bit           tdo_q[$];
  bit           aborted;           // ended by trst_n low before Update-xR
  ...
endclass
```

### 3.2 Components

- **TCK source:** a free-running clock in `tb_top`, gated by `tck_en` in `jtag_if`. The driver drops `tck_en` (only while TCK is low, so no glitch) for `TCK_STOP` items. A stopped TCK is legal JTAG; the monitor checks that the TAP state, `tdo` and the DFT outputs do not change while TCK is stopped, and the scoreboard checks that the next scan after the stop is still correct.
- **Driver:** tracks the TAP state itself and generates the TMS path for each item, e.g. IR_SCAN from Run-Test/Idle = `1,1,0,0` → shift `tdi_q.size()` bits (TMS = 1 on the last bit) → `1` (Update-IR) → `0` (Run-Test/Idle). Drive TMS/TDI on the falling edge so they are stable at the rising edge.
- **JTAG monitor:** reconstructs the TAP state **independently** from TMS (its own copy of the spec's state table, not the driver's), collects TDI/TDO bits during Shift states and publishes `jtag_scan_txn`s. Flag a protocol error if `tdo_en` is high outside Shift states, or if `tdo` / `tdo_en` change while `tck` is high (i.e. not at a falling edge; changes caused by `trst_n` are ignored). On `trst_n` low mid-scan, it publishes the partial scan with `aborted = 1` and resets its state. (Only `trst_n` can abort a scan: via TMS, every path out of Shift-xR / Pause-xR passes Exit → Update before Test-Logic-Reset, so the scan always completes first.)
- **DFT monitor:** a passive monitor on `dft_if` that publishes every change of `test_mode` / `scan_en` / `mbist_start` / `mbist_done` / `mbist_pass` with a timestamp. It flags an error if `test_mode` / `scan_en` / `mbist_start` change while `tck` is high (ignoring `trst_n` clears), the simulation counterpart of the formal edge-only properties.
- **Reference model:** predicts the active instruction, BYPASS / IDCODE / DFT_CTRL contents, TDO streams and DFT output changes, including the "unused opcode = BYPASS" and "reset = IDCODE" rules. It is fed **only by the monitors, never by the driver** (stated in the code comments too): this is why a driver bug cannot hide a DUT bug.
- **Scoreboard:** compares every observed TDO stream and every DFT output change against the model. In `check_phase`, report any scan that started but never completed; scans that ended with `aborted = 1` count as complete, so a mid-scan `trst_n` in `jtag_random_test` does not false-fail.
- **Timeouts:** fail fast if a sequence hangs, as in the AXI project.

### 3.3 Sequences and tests

| Test | What it checks |
|---|---|
| `jtag_reset_test` | `trst_n`, five-TMS reset, reset from every state |
| `jtag_idcode_test` | IDCODE after reset without loading an instruction, and after explicitly loading it |
| `jtag_bypass_test` | BYPASS with random-length streams; 1-cycle delay; first bit 0 |
| `jtag_unused_opcode_test` | every unused opcode behaves like BYPASS |
| `jtag_dft_test` | test mode entry, MBIST start, poll `mbist_done`, read pass/fail, reset back to functional mode |
| `jtag_pause_test` | IR and DR scans interrupted by Pause-xR / Exit2-xR loops |
| `jtag_random_test` | random mix of all items, random idle cycles, TCK stops, occasional mid-scan `trst_n` |

### 3.4 Functional coverage

- TAP state × TMS (= all 32 arcs), sampled in the monitor.
- Opcode loaded: each defined instruction + "unused" bin.
- DR scan length: `< length`, `== length`, `> length` for each selected register.
- Pause usage: no pause, pause in IR, pause in DR, multiple pauses.
- DFT: `test_mode` × `scan_en` × `mbist_start`. The `illegal_bins` for `scan_en && !test_mode` duplicates `a_scan_en_safe`: it is counted as a **check**, not as a coverage goal, and is excluded from the coverage percentage.
- MBIST: run completed with pass, with fail, restart (write 0 then 1), redundant write of 1 while running.
- Reset kind × state at reset time; mid-scan reset (aborted scans).

### 3.5 Regression

- `scripts/regress.py`: 20 seeds × `jtag_random_test`, plus every directed test once. Merge coverage with `vcover merge` and sign off on **merged** coverage (same rule as the AXI project).
- Check that the seed is really applied: merged coverage should differ from each per-seed result. The AXI project found that bug the hard way.
- Collect DUT code coverage (statements, branches, conditions, FSM states/transitions). Treat any gap as a hole in the verification plan, and close unreachable terms with formal covers. Known exclusion: the FSM `default` branch in `jtag_tap_fsm.sv` is unreachable by R4 (all 16 codes are states) and is wrapped in `// coverage off` / `// coverage on`; every exclusion is listed here with its reason.

---

## 4. Mutation testing

One patch per bug in `mutations/`. Run each against formal and UVM, then record which flow caught it:

| # | Mutation | Expected to be caught by |
|---|---|---|
| M1 | Exit2-DR with TMS = 0 goes to Update-DR instead of Shift-DR | FSM arc assertion; pause test |
| M2 | Select-IR-Scan with TMS = 1 goes to Run-Test/Idle instead of Test-Logic-Reset | `a_tms5_reset` |
| M3 | Capture-IR loads `2'b00` | `a_capture_ir_01`; scoreboard |
| M4 | TDO updated on the rising edge | `a_tdo_no_rise_change`; JTAG monitor edge check |
| M5 | IR updates during Shift-IR | `a_ir_stable`; scoreboard |
| M6 | Reset leaves BYPASS active instead of IDCODE | `a_reset_idcode`; idcode test |
| M7 | Unused opcode selects IDCODE | `a_unused_is_bypass`; unused opcode test |
| M8 | `scan_en` not gated by `test_mode` | `a_scan_en_safe` |
| M9 | DFT outputs not cleared in Test-Logic-Reset | `a_dft_reset_functional`; dft test |
| M10 | DR shift direction reversed (MSB first) | IDCODE end-to-end check; idcode test |
| M11 | BYPASS captures 1 | BYPASS end-to-end check; bypass test |
| M12 | One wrong IDCODE bit (e.g. bit 17) | symbolic-`k` IDCODE check; idcode test |
| M13 | DFT update fires with any instruction active | `a_dft_update_only`; DFT monitor + scoreboard |
| M14 | Reserved bits 7:5 writable (read back what was written) | `a_reserved_zero`; dft test |
| M15 | `tdo_en` also high in Exit1-xR | `a_tdo_en`; monitor protocol check |
| M16 | `trst_n` does not reset the IR (only the TLR falling-edge clear does) | async-reset property and IR shadow register (need `-auto_constraint_off`); simulation may miss it |
| M17 | Update registers clocked on the rising edge | edge-only properties (2.2); DFT monitor edge check |
| M18 | `mbist_done` one edge early (`MBIST_CYCLES - 2` in the compare) | `a_mbist_done_exact`; exact-count check in dft test / smoke |
| M19 | `mbist_done` is a pulse, not held while `mbist_start` = 1 | `a_mbist_hold`; dft test |
| M20 | `mbist_pass` re-sampled from `mbist_fail_i` after done | `a_mbist_hold`; dft test |

M1–M9 are mostly control / FSM bugs; M10–M17 cover the data path and the edge timing; M18–M20 cover the MBIST stub. The goal is a table in README.md showing which flow caught each of the **20 mutations**. M16 is expected to be a formal-only catch, which is a result worth reporting, not a gap to hide. Any other miss points to a missing check, so add it.

**Mutant sanity check (`run_mutations.py`):** before scoring, confirm that each mutant applies cleanly, compiles, and actually changes behaviour (e.g. a short directed run whose trace differs from the clean RTL, or at least one formal assertion that differs). An equivalent mutant would otherwise show up as falsely "missed". Patches are applied and reverted with `git apply` / `git apply -R`.

---

## 5. Stretch goals

1. **Boundary scan:** an N = 4 pin boundary scan register with SAMPLE/PRELOAD and EXTEST, plus properties that EXTEST drives the pins from the update latches and that functional mode is unaffected otherwise.
2. **CDC version of the MBIST stub:** run the MBIST engine on a separate system clock, add a 2-flop synchronizer for `mbist_start` / `mbist_done`, and discuss what formal can and cannot say about it.
3. **Multi-TAP chain:** two TAP instances in series. The UVM test selects one device (the other in BYPASS) and checks the chain length.
4. **BSDL file:** a BSDL description of the device. This is how real JTAG tools learn the IR length, opcodes and IDCODE.
5. **IEEE 1687 (IJTAG) taster:** one segment insertion bit (SIB) in front of the DFT_CTRL register.

---

## 6. Phases and exit criteria

| Phase | Work | Done when |
|---|---|---|
| Phase 1 | Specification (`design_spec.md`), RTL, lint, directed smoke test | Lint clean, smoke test passing |
| Phase 2 | Formal: FSM, register, DFT and MBIST properties, covers, Questa flow | Every assertion proven, every cover reached |
| Phase 3 | UVM: agent, monitors, reference model, scoreboard, coverage, tests, regression | 20/20 seeds pass, 100 % merged functional coverage, code coverage reviewed |
| Phase 4 | Mutation testing, results tables in README.md | All 20 mutations scored per flow, README results complete |
