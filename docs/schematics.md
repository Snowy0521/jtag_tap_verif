# Schematics

## Contents

- [RTL](#rtl)
  - [jtag_tap_top](#jtag_tap_top)
    - [jtag_tap_fsm](#jtag_tap_fsm) (`u_fsm`)
    - [jtag_ir](#jtag_ir) (`u_ir`)
    - [decode_ir()](#decode_ir) (function in `jtag_pkg`)
    - [jtag_dr](#jtag_dr) (`u_dr`)
    - [mbist_stub](#mbist_stub) (`u_mbist`)
    - [TDO stage](#tdo-stage) (logic in `jtag_tap_top`)
- [Formal](#formal)
  - [formal_top](#formal_top)
    - [jtag_checker_defaults.svh](#jtag_checker_defaultssvh) (included in every checker)
    - [jtag_tap_fsm_props](#jtag_tap_fsm_props) (`u_fsm_props`)
    - [jtag_reg_props](#jtag_reg_props) (`u_reg_props`)
    - [jtag_dft_props](#jtag_dft_props) (`u_dft_props`)
    - [jtag_covers](#jtag_covers) (`u_covers`)
- [TB](#tb)
  - [tb_top](#tb_top)
    - [jtag_if](#jtag_if) (`jif`)
    - [dft_if](#dft_if) (`dif`)
  - [jtag_env](#jtag_env) (`uvm_test_top.env`)
    - [jtag_agent](#jtag_agent) (`env.agent`)
      - [jtag_driver](#jtag_driver) (`agent.drv`)
      - [jtag_monitor](#jtag_monitor) (`agent.mon`)
    - [dft_monitor](#dft_monitor) (`env.dft_mon`)
    - [jtag_scoreboard](#jtag_scoreboard) (`env.sb`)
      - [jtag_ref_model](#jtag_ref_model) (`sb.model`)
    - [jtag_coverage](#jtag_coverage) (`env.cov`)
  - [Transactions](#transactions) (`jtag_seq_item`, `jtag_scan_txn`, `jtag_edge_txn`, `dft_txn`)
  - [jtag_base_seq](#jtag_base_seq)
  - [Tests](#tests) (`uvm_test_top`)
    - [Directed sequences](#directed-sequences) (idcode, bypass, unused_opcode, pause)
    - [jtag_reset_test](#jtag_reset_test)
    - [jtag_dft_test](#jtag_dft_test)
    - [jtag_random_test](#jtag_random_test)

---

## RTL

### jtag_tap_top

![Module view of jtag_tap_top](img/rtl/jtag_tap_top_modules.svg)

---

#### jtag_tap_fsm

![jtag_tap_fsm: next-state logic and state register, and the 16-state diagram with encodings and tms arcs](img/rtl/jtag_tap_fsm.svg)

---

#### jtag_ir

![jtag_ir: ir_sr shift register (posedge) with capture/shift muxes, and ir update register (negedge) with update/reset muxes](img/rtl/jtag_ir.svg)

---

#### decode_ir()

![decode_ir(): ir compared with OP_IDCODE and OP_DFT_CTRL, mux chain selects DR_IDCODE, DR_DFT_CTRL or default DR_BYPASS](img/rtl/decode_ir.svg)

---

#### jtag_dr

![jtag_dr: capture/shift decode; bypass_sr, dft_sr and idcode_sr shift registers (posedge) with shift and capture muxes; dr_tdo mux chain; DFT update registers (negedge) driving mbist_start, scan_en, test_mode](img/rtl/jtag_dr.svg)

---

#### mbist_stub

![mbist_stub: cnt, mbist_done and mbist_pass registers (posedge), each with a !mbist_start clear mux, a !mbist_done hold mux and a cnt == MBIST_CYCLES-1 mux](img/rtl/mbist_stub.svg)

---

#### TDO stage

![TDO stage: state compared with SHIFT_IR and SHIFT_DR; mux chain picks ir_sr[0], dr_tdo or 1'b0 into the tdo flop; OR of the two compares into the tdo_en flop; both flops on negedge tck](img/rtl/tdo_stage.svg)

---

## Formal

### formal_top

![formal_top: dut jtag_tap_top with MBIST_CYCLES = 4 and all inputs free; four checkers bound into jtag_tap_top, with a dot where each checker port connects to a signal; every checker includes jtag_checker_defaults.svh](img/formal/formal_top.svg)

---

#### jtag_checker_defaults.svh

![jtag_checker_defaults.svh: trst_seen flop; rst_seen as 1'b1 under QUESTA_FORMAL or a set-once flop with a final check otherwise; OR of three !== compares as the default disable iff; default clocking on posedge tck; ASSERT_TRST macro as an OR into an assert final](img/formal/jtag_checker_defaults.svg)

---

#### jtag_tap_fsm_props

![jtag_tap_fsm_props: included checker defaults (trst_seen, rst_seen, disable iff, default clocking); a_next_state from $past flops and model_next; generated per-arc asserts and covers; a_tms5_reset from a 5-deep $past(tms) chain; tms5 covers; a_trst_state deferred assertion; a_state_legal](img/formal/jtag_tap_fsm_props.svg)

---

#### jtag_reg_props

![jtag_reg_props 1/3: wire shifting and spec localparams; IR, decode and TDO assertions as A, B and !A || B; ASSERT_TRST checks for ir and tdo](img/formal/jtag_reg_props_rules.svg)

![jtag_reg_props 2/3: symbolic indices k and j; len, cap, cnt and tracked scan-model registers with their capture and shift muxes; a_scan_data and a_scan_delay; scan covers](img/formal/jtag_reg_props_scan.svg)

![jtag_reg_props 3/3: tdo, tdo_en and ir shadow flops on posedge tck compared at negedge tck](img/formal/jtag_reg_props_edge.svg)

---

#### jtag_dft_props

![jtag_dft_props 1/2: dft_sel; dsr model register with shift and capture muxes; a_dft_update_only, a_dft_write, a_dft_reset_functional, a_trst_dft, a_scan_en_safe; dft_at_rise edge check](img/formal/jtag_dft_props_ctrl.svg)

![jtag_dft_props 2/2: mcnt checker counter; a_mbist_done_exact, a_mbist_clear, a_mbist_hold, a_mbist_pass_value, a_mbist_pass_needs_done](img/formal/jtag_dft_props_mbist.svg)

---

#### jtag_covers

![jtag_covers: nine scenario covers, each drawn as a chain of condition boxes joined by ##0, ##1 or ##[1:$] arrows, with repetitions [*32] and [*1:$] inside the boxes](img/formal/jtag_covers.svg)

---

## TB

### tb_top

![tb_top: initial block with config_db sets and run_test; uvm_test_top reaching jif and dif through virtual interfaces; TCK generator gated by tck_en; jif and dif wired to dut jtag_tap_top, with the checkers bound under JTAG_SIM_CHECKERS](img/tb/tb_top.svg)

---

#### jtag_if

![jtag_if: tck, tck_en, tms, tdi, trst_n, tdo, tdo_en; clocking mon_cb at posedge tck with default input #1step samples tms, tdi, trst_n, tdo, tdo_en](img/tb/jtag_if.svg)

---

#### dft_if

![dft_if (input logic tck): test_mode, scan_en, mbist_start, mbist_done, mbist_pass, mbist_fail_i; clocking mon_cb at posedge tck with default input #1step samples all six](img/tb/dft_if.svg)

---

### jtag_env

![uvm_test_top (jtag_base_test) with its phases; env with agent (sqr and drv only when UVM_ACTIVE, mon), dft_mon, sb with the reference model, cov; analysis ports from mon and dft_mon to the scoreboard and coverage imps; check_phase scan count check](img/tb/jtag_env.svg)

---

#### jtag_agent

![jtag_agent: sqr and drv built only when UVM_ACTIVE, drv.seq_item_port connected to sqr.seq_item_export; mon always built, its ap and edge_ap seen from outside as mon.ap and mon.edge_ap](img/tb/jtag_agent.svg)

---

##### jtag_driver

![jtag_driver 1/2: class fields; run_phase loop with get_next_item, the at_rti check, case on req.kind to seven tasks, item_done; tick() drives tms and tdi at the falling edge and the DUT samples at the rising edge](img/tb/jtag_driver_loop.svg)

![jtag_driver 2/2: reset_trst long and short pulse, reset_tms, tms_path, tck_stop as chains of steps; scan as the TAP path it walks, with the tick call on every arrow](img/tb/jtag_driver_tasks.svg)

---

##### jtag_monitor

![jtag_monitor 1/2: class fields and the ap / edge_ap ports; run_phase forks three forever threads: negedge trst_n (abort_scan, publish_reset, state = TEST_LOGIC_RESET, synced), one mon_cb sample per rising edge (held in reset, sync on five TMS = 1, else sample()), and the tdo / tdo_en edge check; publish_reset, abort_scan, check_phase and report_phase](img/tb/jtag_monitor_threads.svg)

![jtag_monitor 2/2: sample() as a chain of if blocks: open a txn at Capture-xR, record the path, tdo_en check, collect tdi / tdo in Shift-xR, write the txn at Update-xR; then the edge txn on edge_ap, next_state() and publish_reset on entering Test-Logic-Reset; next_state() case table](img/tb/jtag_monitor_sample.svg)

---

#### dft_monitor

![dft_monitor: class fields and the ap port; run_phase forks three forever threads: one dft_txn per rising edge (cycle++, sample()), the test_mode / scan_en / mbist_start edge check (high or stopped TCK), and the mbist_done / mbist_pass check (stopped TCK only); sample() copies the six mon_cb pins into a dft_txn and writes it on ap](img/tb/dft_monitor.svg)

---

#### jtag_scoreboard

![jtag_scoreboard 1/2: class fields; write_jtag from jtag_imp: a RESET resets the model and pushes a prediction; a scan gets the MBIST status at its capture cycle, model.predict gives the expected TDO bits, each known bit is compared; a DFT_CTRL DR scan pushes a prediction; push_pred, prune_samples, error](img/tb/jtag_scoreboard_jtag.svg)

![jtag_scoreboard 2/2: write_dft from dft_imp stores the sample and checks the previous one; check_sample picks the latest prediction in effect, compares the DFT outputs, checks scan_en implies test_mode, and checks mbist_done / mbist_pass against the run of mbist_start samples; check_phase and report_phase](img/tb/jtag_scoreboard_dft.svg)

---

##### jtag_ref_model

![jtag_ref_model: class fields and reset(); predict loads the capture value (IR or capture_dr by instruction) into sr / sr_k queues, shifts tdi_q in at the top while exp / exp_known come out of sr[0], then applies the update to instr or to the DFT outputs unless the scan was aborted](img/tb/jtag_ref_model.svg)

---

#### jtag_coverage

![jtag_coverage 1/3: class with three imps and the enums; sampled values and the TB counters; each covergroup next to its bins drawn as a grid, with ignore and illegal cells and the counter key of each bin](img/tb/jtag_coverage_bins.svg)

![jtag_coverage 2/3: write_edge samples the arc; write_jtag samples the reset, pause, abort, instruction and DR length bins; count_pauses, ir_after, classify and len_class](img/tb/jtag_coverage_jtag.svg)

![jtag_coverage 3/3: write_dft samples each DFT output change and the MBIST events (pass / fail, restart, redundant start); tracking fields, mbist() and report_phase](img/tb/jtag_coverage_dft.svg)

---

### Transactions

![Transactions: who creates each one and who receives it (seq to sqr and drv by pull; mon and dft_mon to the scoreboard and coverage imps by push); jtag_seq_item fields, constraints, pre_randomize and post_randomize, with the randomize() order; jtag_scan_txn, jtag_edge_txn and dft_txn fields](img/tb/jtag_transactions.svg)

---

### jtag_base_seq

![jtag_base_seq: send() and its start_item / finish_item handshake with the sequencer and the driver; the helper tasks and the item fields each one sets](img/tb/jtag_base_seq.svg)

---

### Tests

![jtag_base_test: build_phase, run_phase with the objection and drain time; every test extends jtag_base_test and starts its sequence, every sequence extends jtag_base_seq](img/tb/jtag_tests.svg)

---

#### Directed sequences

![body() of jtag_idcode_seq, jtag_bypass_seq, jtag_unused_opcode_seq and jtag_pause_seq as chains of helper calls, with their loops; the bits() helper of jtag_pause_seq](img/tb/jtag_tests_directed.svg)

---

#### jtag_reset_test

![jtag_reset_seq: the 16 TMS paths from Run-Test/Idle into every state, and the loop over paths and the three reset kinds, each between a DFT_CTRL write and an IDCODE read](img/tb/jtag_reset_test.svg)

---

#### jtag_dft_test

![jtag_dft_test: DFT_CTRL data register capture and update bits; body() of jtag_dft_seq and jtag_dft_fail_seq; run_stimulus with mbist_fail_i around the two sequences](img/tb/jtag_dft_test.svg)

---

#### jtag_random_test

![jtag_random_seq: repeat n_items picks one action by a weighted range of a random number 0..99; the random_ir, walk_then_reset, random_dr, tck_stop and dft_write tasks; run_stimulus forks the sequence with a background mbist_fail_i toggle](img/tb/jtag_random_test.svg)
