# Design specification

One numbered rule per behaviour. Every RTL module, formal property, UVM check and mutation refers to these IDs.
Clause numbers refer to IEEE Std 1149.1-2013 and are marked *(verify)* until checked against the standard text.

Parameters and constants live in `rtl/jtag_pkg.sv`.

---

## 1. Interface

| Port | Dir | Width | Description |
|---|---|---|---|
| `tck` | in | 1 | Test clock |
| `tms` | in | 1 | Test mode select, sampled on the rising edge |
| `tdi` | in | 1 | Test data in, sampled on the rising edge |
| `trst_n` | in | 1 | Asynchronous test reset, active low |
| `tdo` | out | 1 | Test data out, changes on the falling edge |
| `tdo_en` | out | 1 | TDO output enable (TDO is high-Z when 0; the pad is outside this design) |
| `mbist_fail_i` | in | 1 | MBIST stub result input: 1 = the run fails (testbench / formal free input) |
| `test_mode` | out | 1 | DFT_CTRL bit 0 |
| `scan_en` | out | 1 | DFT_CTRL bit 1 |
| `mbist_start` | out | 1 | DFT_CTRL bit 2 |
| `mbist_done` | out | 1 | MBIST stub status (also captured into DFT_CTRL bit 3) |
| `mbist_pass` | out | 1 | MBIST stub status (also captured into DFT_CTRL bit 4) |

Parameter: `MBIST_CYCLES` (default 16, minimum 1).

## 2. Clocking

| Edge | Updates |
|---|---|
| TCK rising | TAP state; IR and DR shift registers (capture, shift); MBIST stub |
| TCK falling | `tdo`, `tdo_en`; IR update register; DFT_CTRL update registers |
| `trst_n` falling (async) | R3, R9, R14, R18, R19; the shift registers are also reset, for determinism only (no rule depends on it) |

All storage is clocked by TCK or cleared by `trst_n`. There are no other clocks and no latches.

---

## 3. Rules

### TAP controller

| ID | Rule | Source |
|---|---|---|
| **R1** | The state changes on every TCK rising edge according to the state table below. | Clause 6 *(verify)* |
| **R2** | From any state, five consecutive rising edges with TMS = 1 reach Test-Logic-Reset. | Clause 6 *(verify)* |
| **R3** | `trst_n` low forces the state to Test-Logic-Reset asynchronously and holds it there while low. | Clause 6 *(verify)* |
| **R4** | State encoding uses the 1149.1 example encoding (`jtag_pkg::tap_state_e`). All 16 codes of the 4-bit register are legal states. | Project choice |

State table for R1 (`scripts/gen_fsm_props.py` reads this table to generate the per-arc checks):

| State | Code | TMS = 0 | TMS = 1 |
|---|---|---|---|
| TEST_LOGIC_RESET | `F` | RUN_TEST_IDLE | TEST_LOGIC_RESET |
| RUN_TEST_IDLE | `C` | RUN_TEST_IDLE | SELECT_DR_SCAN |
| SELECT_DR_SCAN | `7` | CAPTURE_DR | SELECT_IR_SCAN |
| CAPTURE_DR | `6` | SHIFT_DR | EXIT1_DR |
| SHIFT_DR | `2` | SHIFT_DR | EXIT1_DR |
| EXIT1_DR | `1` | PAUSE_DR | UPDATE_DR |
| PAUSE_DR | `3` | PAUSE_DR | EXIT2_DR |
| EXIT2_DR | `0` | SHIFT_DR | UPDATE_DR |
| UPDATE_DR | `5` | RUN_TEST_IDLE | SELECT_DR_SCAN |
| SELECT_IR_SCAN | `4` | CAPTURE_IR | TEST_LOGIC_RESET |
| CAPTURE_IR | `E` | SHIFT_IR | EXIT1_IR |
| SHIFT_IR | `A` | SHIFT_IR | EXIT1_IR |
| EXIT1_IR | `9` | PAUSE_IR | UPDATE_IR |
| PAUSE_IR | `B` | PAUSE_IR | EXIT2_IR |
| EXIT2_IR | `8` | SHIFT_IR | UPDATE_IR |
| UPDATE_IR | `D` | RUN_TEST_IDLE | SELECT_DR_SCAN |

### TDO

| ID | Rule | Source |
|---|---|---|
| **R5** | `tdo_en` is 1 exactly in the falling-edge-to-falling-edge intervals that start in Shift-IR or Shift-DR: at each falling edge, `tdo_en <= (state == SHIFT_IR \|\| state == SHIFT_DR)`. | Clause 4 *(verify)* |
| **R6** | At each falling edge, `tdo <=` bit 0 of the IR shift register in Shift-IR, bit 0 of the selected DR shift register in Shift-DR, else 0. `tdo` and `tdo_en` never change on a rising edge. | Clause 4 *(verify)* |
| **R18** | `trst_n` low clears `tdo` and `tdo_en` to 0 asynchronously. Via TMS no extra clear exists: Test-Logic-Reset is not a Shift state, so R5 / R6 already drive 0 at the next falling edge. | Project choice |

### Instruction register

| ID | Rule | Source |
|---|---|---|
| **R7** | In Capture-IR (rising edge) the IR shift register loads `4'b0001`: bits [1:0] = `01` mandatory, bits [3:2] = 0. | Clause 7 *(verify)* |
| **R8** | In Shift-IR (rising edge) the IR shift register shifts right: `ir_sr <= {tdi, ir_sr[3:1]}`. Bit 0 is the next TDO bit (LSB first). | Clause 7 *(verify)* |
| **R9** | The active instruction (IR update register) changes only: (a) on the falling edge in Update-IR, to the IR shift register value; (b) on the falling edge in Test-Logic-Reset, to IDCODE; (c) asynchronously on `trst_n` low, to IDCODE. Shifting never changes it. No reset is decoded from the state. | Clause 7 *(verify: falling-edge reset of the instruction in TLR, still to be checked against the standard text)* |
| **R10** | Instruction decode: `4'b1111` BYPASS, `4'b0001` IDCODE, `4'b1000` DFT_CTRL. Every other opcode, including `4'b0000` (EXTEST) and `4'b0010` (SAMPLE/PRELOAD) while boundary scan is not implemented, selects the BYPASS register. | Clause 8 *(verify)*; stretch goal noted |

### Data registers

| ID | Rule | Source |
|---|---|---|
| **R11** | Only the selected DR captures and shifts. Capture on the rising edge in Capture-DR, shift right on each rising edge in Shift-DR (`sr <= {tdi, sr[N-1:1]}`). | Clause 9 *(verify)* |
| **R12** | BYPASS: 1 bit, captures 0. In Shift-DR, the first TDO bit is 0 and each later bit is TDI from one shift earlier. | Clause 10 *(verify)* |
| **R13** | IDCODE: 32 bits, captures `IDCODE_VAL`, shifted out LSB first. `[31:28]` version, `[27:12]` part number, `[11:1]` manufacturer, `[0]` = 1. After 32 shifts, TDO outputs TDI delayed by 32 shifts. | Clause 12 *(verify)* |

`IDCODE_VAL = 32'h1114_9FFF`: version 1, part number `16'h1149`, manufacturer `11'h7FF`. The manufacturer field is a
placeholder: `0x7F` within a JEP106 bank is the continuation code, never an assigned ID, so this code cannot belong to
a real vendor *(verify before any real use)*.

### DFT control register

| Bit | Field | Write (Update-DR) | Read (Capture-DR) |
|---|---|---|---|
| 0 | `test_mode` | update register | update register |
| 1 | `scan_en` | update register, gated: `sr[1] & sr[0]` | update register |
| 2 | `mbist_start` | update register | update register |
| 3 | `mbist_done` | ignored | MBIST stub status |
| 4 | `mbist_pass` | ignored | MBIST stub status |
| 7:5 | reserved | ignored | 0 |

| ID | Rule | Source |
|---|---|---|
| **R14** | Update registers `test_mode`, `scan_en`, `mbist_start` change only: (a) on the falling edge in Update-DR **with DFT_CTRL active**; (b) to 0 on the falling edge in Test-Logic-Reset; (c) to 0 asynchronously on `trst_n` low. | Project choice |
| **R15** | Write in Update-DR: `test_mode <= sr[0]`, `scan_en <= sr[1] & sr[0]`, `mbist_start <= sr[2]`. Bits 7:3 of the shift register are ignored on write. | Project choice |
| **R16** | `scan_en` is never 1 while `test_mode` is 0. Guaranteed by R15 (gating at write time); the outputs come straight from the flops. | Project (safety) |
| **R17** | Capture-DR loads `{3'b000, mbist_pass, mbist_done, mbist_start, scan_en, test_mode}`: bits 2:0 read back the update registers, bits 4:3 the MBIST status, bits 7:5 are 0. | Project choice |

### MBIST stub

| ID | Rule | Source |
|---|---|---|
| **R19** | While `mbist_start` = 0 (sampled at a rising edge), `mbist_done` and `mbist_pass` are 0 and the counter is idle. They clear at the first rising edge after `mbist_start` returns to 0. `trst_n` low clears them asynchronously. | Project choice |
| **R20** | While `mbist_start` = 1, the stub counts rising edges. At the `MBIST_CYCLES`-th rising edge that samples `mbist_start` = 1, `mbist_done` becomes 1 and `mbist_pass` becomes `!mbist_fail_i` (sampled at that edge). Both then hold until R19 clears them. | Project choice |
| **R21** | Writing `mbist_start = 1` while it is already 1 has no effect. A new run needs a write of 0 and then a write of 1 (so `mbist_start` is 0 for at least one rising edge). | Project choice |

Consequence of R14 (b): Test-Logic-Reset clears `mbist_start`, which via R19 also clears the stub. The stub counts TCK edges, so TCK must keep running (e.g. in Run-Test/Idle) while a run is in progress, as with RUNBIST on real parts.

### General

| ID | Rule | Source |
|---|---|---|
| **R22** | While TCK is stopped (no edges) and `trst_n` = 1, no output and no state changes. | Clause 4 *(verify: TCK may be stopped in any stable state)* |
| **R23** | A Test-Logic-Reset reached via TMS leaves the TAP in the same register state as `trst_n` (state, active instruction, DFT outputs, `tdo_en`), at the latest one falling edge after entering Test-Logic-Reset. | Project choice |

---

## 4. Traceability

Filled in as the checks are written. Planned names from [plan.md](plan.md) §2–§4.

| Rule | Formal | UVM | Mutations |
|---|---|---|---|
| R1 | `a_next_state`, `a_arc_*`, `c_arc_*` | monitor state model, coverage state × TMS | M1 |
| R2 | `a_tms5_reset` | `jtag_reset_test` | M2 |
| R3 | async-reset `assert final` | `jtag_reset_test` | |
| R4 | legal encoding (cannot fail by construction; kept) | FSM `default` excluded from code coverage | |
| R5 | `a_tdo_en`, `tdo_en` shadow | monitor protocol + edge check | M15 |
| R6 | `tdo` shadow (`a_tdo_no_rise_change`), IDCODE / BYPASS end-to-end | monitor edge check, scoreboard | M4 |
| R7 | `a_capture_ir_01` | scoreboard (IR scan TDO) | M3 |
| R8 | IR scan end-to-end | scoreboard | |
| R9 | `a_ir_stable`, `a_reset_idcode`, IR shadow | `jtag_idcode_test` | M5, M6, M16 |
| R10 | `a_unused_is_bypass` | `jtag_unused_opcode_test` | M7 |
| R11 | IDCODE / BYPASS / DFT end-to-end | scoreboard | M10 |
| R12 | BYPASS end-to-end | `jtag_bypass_test` | M11 |
| R13 | symbolic-`k` IDCODE check | `jtag_idcode_test` | M12 |
| R14 | `a_dft_update_only`, `a_dft_reset_functional`, DFT shadows | DFT monitor + scoreboard, edge check | M9, M13, M17 |
| R15, R16 | `a_scan_en_safe` | coverage illegal bin (check) | M8 |
| R17 | `a_mbist_done_capture`, `a_reserved_zero` | `jtag_dft_test` | M14 |
| R18 | `tdo` / `tdo_en` shadow reset | `jtag_reset_test` | |
| R19–R21 | `a_mbist_done_exact`, `a_mbist_clear`, `a_mbist_hold`, `a_mbist_pass_value` | `jtag_dft_test`, MBIST coverage, smoke exact-count check | M18, M19, M20 |
| R22 | | `TCK_STOP` items | |
| R23 | `a_reset_idcode`, `a_dft_reset_functional` | `jtag_reset_test` | |
