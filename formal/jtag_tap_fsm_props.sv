// ============================================================================
// jtag_tap_fsm_props.sv -- blackbox checks of the TAP state machine (R1-R4).
// Bound into jtag_tap_top by formal_top.sv. Uses only tck/trst_n/tms and the
// state register; the next-state model below is written from the spec, not
// copied from jtag_tap_fsm.sv.
// ============================================================================
module jtag_tap_fsm_props
  import jtag_pkg::*;
(
  input logic       tck,
  input logic       trst_n,
  input logic       tms,
  input tap_state_e state
);

  `include "jtag_checker_defaults.svh"

  // Reference model of R1, grouped by TMS value (the RTL groups by state).
  function automatic tap_state_e model_next(tap_state_e s, logic t);
    if (t) begin
      case (s)
        TEST_LOGIC_RESET, SELECT_IR_SCAN:                return TEST_LOGIC_RESET;
        RUN_TEST_IDLE, UPDATE_DR, UPDATE_IR:             return SELECT_DR_SCAN;
        SELECT_DR_SCAN:                                  return SELECT_IR_SCAN;
        CAPTURE_DR, SHIFT_DR:                            return EXIT1_DR;
        EXIT1_DR, EXIT2_DR:                              return UPDATE_DR;
        PAUSE_DR:                                        return EXIT2_DR;
        CAPTURE_IR, SHIFT_IR:                            return EXIT1_IR;
        EXIT1_IR, EXIT2_IR:                              return UPDATE_IR;
        default:                                         return EXIT2_IR;   // PAUSE_IR
      endcase
    end else begin
      case (s)
        TEST_LOGIC_RESET, RUN_TEST_IDLE, UPDATE_DR, UPDATE_IR: return RUN_TEST_IDLE;
        SELECT_DR_SCAN:                                  return CAPTURE_DR;
        CAPTURE_DR, SHIFT_DR, EXIT2_DR:                  return SHIFT_DR;
        EXIT1_DR, PAUSE_DR:                              return PAUSE_DR;
        SELECT_IR_SCAN:                                  return CAPTURE_IR;
        CAPTURE_IR, SHIFT_IR, EXIT2_IR:                  return SHIFT_IR;
        default:                                         return PAUSE_IR;   // EXIT1_IR, PAUSE_IR
      endcase
    end
  endfunction

  // R1: one property for the whole table
  a_next_state: assert property (1'b1 |=> state == model_next($past(state), $past(tms)));

  // R1: the same table, one property per arc (generated)
  `include "jtag_fsm_arcs.svh"

  // R2: five rising edges with TMS = 1 reach Test-Logic-Reset from any state
  a_tms5_reset: assert property (tms [*5] |=> state == TEST_LOGIC_RESET);

  // R2 worst case: both start states are five TMS = 1 steps from Test-Logic-Reset
  c_tms5_from_shift_dr: cover property (
    (state == SHIFT_DR) ##0 tms [*5] ##1 (state == TEST_LOGIC_RESET));
  c_tms5_from_pause_ir: cover property (
    (state == PAUSE_IR) ##0 tms [*5] ##1 (state == TEST_LOGIC_RESET));

  // R3: asynchronous reset. Cannot sit under disable iff (!trst_n), so it is a
  // deferred immediate assertion, checked whenever its inputs change.
`ifdef VERILATOR
  // In Verilator, `assert final` acts like a plain immediate assertion, i.e. it fires
  // before the reset flops update, so the local simulation checks 1 ps later.
  always @(trst_n or state) begin
    #1ps;
    a_trst_state: assert (trst_n || state == TEST_LOGIC_RESET);
  end
`else
  always_comb begin
    a_trst_state: assert final (trst_n || state == TEST_LOGIC_RESET);
  end
`endif

  // R4: all 16 codes are states, so this cannot fail by construction. It
  // still catches X on the state register and a future encoding change.
  a_state_legal: assert property (
    state inside {TEST_LOGIC_RESET, RUN_TEST_IDLE, SELECT_DR_SCAN, CAPTURE_DR,
                  SHIFT_DR, EXIT1_DR, PAUSE_DR, EXIT2_DR, UPDATE_DR,
                  SELECT_IR_SCAN, CAPTURE_IR, SHIFT_IR, EXIT1_IR, PAUSE_IR,
                  EXIT2_IR, UPDATE_IR});

endmodule
