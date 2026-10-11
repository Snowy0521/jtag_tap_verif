// ============================================================================
// jtag_pkg.sv -- shared types and constants for the JTAG TAP (IEEE 1149.1).
// Rule IDs (Rn) refer to docs/design_spec.md.
// ============================================================================
package jtag_pkg;

  // R4: 1149.1 example state encoding. All 16 codes are legal states.
  typedef enum logic [3:0] {
    TEST_LOGIC_RESET = 4'hF,
    RUN_TEST_IDLE    = 4'hC,
    SELECT_DR_SCAN   = 4'h7,
    CAPTURE_DR       = 4'h6,
    SHIFT_DR         = 4'h2,
    EXIT1_DR         = 4'h1,
    PAUSE_DR         = 4'h3,
    EXIT2_DR         = 4'h0,
    UPDATE_DR        = 4'h5,
    SELECT_IR_SCAN   = 4'h4,
    CAPTURE_IR       = 4'hE,
    SHIFT_IR         = 4'hA,
    EXIT1_IR         = 4'h9,
    PAUSE_IR         = 4'hB,
    EXIT2_IR         = 4'h8,
    UPDATE_IR        = 4'hD
  } tap_state_e;

  // Instruction register (R7-R10)
  localparam int IR_W = 4;

  // Not all opcodes are referenced by the RTL (unused ones decode as BYPASS),
  // but formal / UVM use them by name.
  /* verilator lint_off UNUSEDPARAM */
  localparam logic [IR_W-1:0] OP_EXTEST   = 4'b0000;  // stretch goal, decodes as BYPASS (R10)
  localparam logic [IR_W-1:0] OP_IDCODE   = 4'b0001;
  localparam logic [IR_W-1:0] OP_SAMPLE   = 4'b0010;  // stretch goal, decodes as BYPASS (R10)
  localparam logic [IR_W-1:0] OP_DFT_CTRL = 4'b1000;
  localparam logic [IR_W-1:0] OP_BYPASS   = 4'b1111;
  /* verilator lint_on UNUSEDPARAM */

  localparam logic [IR_W-1:0] IR_CAPTURE  = 4'b0001;  // R7: bits [1:0] = 01, upper bits 0

  // R13: IDCODE = version 1, part 16'h1149, manufacturer 11'h7FF (placeholder:
  // 0x7F is the JEP106 continuation code, never an assigned vendor ID), bit 0 = 1
  localparam int          IDCODE_W   = 32;
  localparam logic [31:0] IDCODE_VAL = {4'h1, 16'h1149, 11'h7FF, 1'b1};

  // DFT control register (R14-R17)
  localparam int DFT_W = 8;

  // Selected data register (R10)
  typedef enum logic [1:0] {
    DR_BYPASS,
    DR_IDCODE,
    DR_DFT_CTRL
  } dr_sel_e;

  function automatic dr_sel_e decode_ir(logic [IR_W-1:0] ir);
    case (ir)
      OP_IDCODE:   return DR_IDCODE;
      OP_DFT_CTRL: return DR_DFT_CTRL;
      default:     return DR_BYPASS;      // BYPASS and every unused opcode (R10)
    endcase
  endfunction

endpackage
