// ============================================================================
// jtag_covers.sv -- scenario covers: each one shows that a whole use case is
// reachable, so the assertions that depend on it are not vacuous.
// State and arc covers are generated (jtag_fsm_arcs.svh).
// ============================================================================
module jtag_covers
  import jtag_pkg::*;
(
  input logic            tck,
  input logic            trst_n,
  input tap_state_e      state,
  input logic [IR_W-1:0] ir,
  input logic            test_mode,
  input logic            scan_en,
  input logic            mbist_start,
  input logic            mbist_done,
  input logic            mbist_pass
);

  `include "jtag_checker_defaults.svh"

  // An IR scan that loads IDCODE, then a full 32-bit IDCODE read
  c_ir_scan_then_idcode_read: cover property (
    state == UPDATE_IR ##0 ir == OP_IDCODE ##[1:$] state == CAPTURE_DR && ir == OP_IDCODE
    ##1 state == SHIFT_DR [*32] ##1 state == EXIT1_DR);

  // A DR scan that pauses and goes back to shifting
  c_pause_dr: cover property (
    state == SHIFT_DR ##1 state == EXIT1_DR ##1 state == PAUSE_DR [*1:$]
    ##1 state == EXIT2_DR ##1 state == SHIFT_DR);

  // The same for an IR scan
  c_pause_ir: cover property (
    state == SHIFT_IR ##1 state == EXIT1_IR ##1 state == PAUSE_IR [*1:$]
    ##1 state == EXIT2_IR ##1 state == SHIFT_IR);

  // Test mode with scan enabled
  c_scan_mode: cover property (test_mode && scan_en);

  // DFT sequence: enter test mode and start MBIST, run to a pass, read it back
  c_mbist_pass_readback: cover property (
    $rose(mbist_start) && test_mode ##[1:$] mbist_done && mbist_pass
    ##[1:$] state == CAPTURE_DR && ir == OP_DFT_CTRL && mbist_done && mbist_pass);

  // MBIST failing run
  c_mbist_fail: cover property ($rose(mbist_done) && !mbist_pass);

  // MBIST restart: done, start dropped, started again
  c_mbist_restart: cover property (
    mbist_done ##[1:$] !mbist_start ##[1:$] $rose(mbist_start));

  // Reset back to functional mode from test mode via TMS (the clear happens on
  // the falling edge, so test_mode is already 0 at the first sample in TLR)
  c_tms_reset_from_test_mode: cover property (
    test_mode ##1 state == TEST_LOGIC_RESET && !test_mode);

  // trst_n in the middle of a DR scan. The default disable iff would switch
  // this cover off exactly when it happens, so it opts out.
  c_trst_mid_scan: cover property (disable iff (1'b0)
    state == SHIFT_DR ##1 !trst_n);

endmodule
