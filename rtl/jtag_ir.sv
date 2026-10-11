// ============================================================================
// jtag_ir.sv -- instruction register: shift register (rising edge) and
// update register = active instruction (falling edge) (R7-R9).
// ============================================================================
module jtag_ir
  import jtag_pkg::*;
(
  input  logic            tck,
  input  logic            trst_n,
  input  tap_state_e      state,
  input  logic            tdi,
  output logic [IR_W-1:0] ir_sr,      // shift register, ir_sr[0] is the next TDO bit
  output logic [IR_W-1:0] ir          // active instruction
);

  // R7 capture, R8 shift (LSB out first). Reset value only for determinism.
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)                 ir_sr <= IR_CAPTURE;
    else if (state == CAPTURE_IR) ir_sr <= IR_CAPTURE;
    else if (state == SHIFT_IR)   ir_sr <= {tdi, ir_sr[IR_W-1:1]};
  end

  // R9: update on the falling edge in Update-IR; synchronous clear on the
  // falling edge in Test-Logic-Reset; asynchronous clear only via trst_n.
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n)                       ir <= OP_IDCODE;
    else if (state == TEST_LOGIC_RESET) ir <= OP_IDCODE;
    else if (state == UPDATE_IR)        ir <= ir_sr;
  end

endmodule
