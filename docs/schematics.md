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
