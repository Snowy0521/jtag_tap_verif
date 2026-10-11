// ============================================================================
// jtag_tap_fsm.sv -- 16-state TAP controller, nothing else (R1-R4).
// Kept separate so the formal next-state checks target it directly.
// ============================================================================
module jtag_tap_fsm
  import jtag_pkg::*;
(
  input  logic       tck,
  input  logic       trst_n,
  input  logic       tms,
  output tap_state_e state
);

  tap_state_e state_next;

  // One table row: next state for TMS = 1 / TMS = 0. Written with if/else, not
  // ?:, because iverilog drops the enum type through the conditional operator.
  function automatic tap_state_e arc(input logic t, input tap_state_e on1, input tap_state_e on0);
    if (t) return on1;
    else   return on0;
  endfunction

  // R1: state table in docs/design_spec.md
  always_comb begin
    unique case (state)
      TEST_LOGIC_RESET: state_next = arc(tms, TEST_LOGIC_RESET, RUN_TEST_IDLE);
      RUN_TEST_IDLE:    state_next = arc(tms, SELECT_DR_SCAN,   RUN_TEST_IDLE);
      SELECT_DR_SCAN:   state_next = arc(tms, SELECT_IR_SCAN,   CAPTURE_DR);
      CAPTURE_DR:       state_next = arc(tms, EXIT1_DR,         SHIFT_DR);
      SHIFT_DR:         state_next = arc(tms, EXIT1_DR,         SHIFT_DR);
      EXIT1_DR:         state_next = arc(tms, UPDATE_DR,        PAUSE_DR);
      PAUSE_DR:         state_next = arc(tms, EXIT2_DR,         PAUSE_DR);
      EXIT2_DR:         state_next = arc(tms, UPDATE_DR,        SHIFT_DR);
      UPDATE_DR:        state_next = arc(tms, SELECT_DR_SCAN,   RUN_TEST_IDLE);
      SELECT_IR_SCAN:   state_next = arc(tms, TEST_LOGIC_RESET, CAPTURE_IR);
      CAPTURE_IR:       state_next = arc(tms, EXIT1_IR,         SHIFT_IR);
      SHIFT_IR:         state_next = arc(tms, EXIT1_IR,         SHIFT_IR);
      EXIT1_IR:         state_next = arc(tms, UPDATE_IR,        PAUSE_IR);
      PAUSE_IR:         state_next = arc(tms, EXIT2_IR,         PAUSE_IR);
      EXIT2_IR:         state_next = arc(tms, UPDATE_IR,        SHIFT_IR);
      UPDATE_IR:        state_next = arc(tms, SELECT_DR_SCAN,   RUN_TEST_IDLE);
      // Unreachable: all 16 codes are states (R4). Excluded from code coverage.
      // coverage off
      default:          state_next = TEST_LOGIC_RESET;
      // coverage on
    endcase
  end

  // R3: asynchronous reset to Test-Logic-Reset
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) state <= TEST_LOGIC_RESET;
    else         state <= state_next;
  end

endmodule
