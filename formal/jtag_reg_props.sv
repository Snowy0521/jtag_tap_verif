// ============================================================================
// jtag_reg_props.sv -- IR, decode and TDO checks, plus an end-to-end scan
// model (R5-R13, R17, R18). Bound into jtag_tap_top by formal_top.sv.
//
// The scan model is written from the spec: at each Capture-xR it records the
// register length and the value the spec says is captured, then checks every
// shifted TDO bit against it. Two symbolic indices keep this cheap for formal:
//   k: one captured bit,        tdo at shift k     == captured[k]   (k < length)
//   j: one bit shifted in,      tdo at shift j+len == tdi at shift j
// Because k and j can take any value, one proof covers every bit position.
// ============================================================================
module jtag_reg_props
  import jtag_pkg::*;
(
  input logic            tck,
  input logic            trst_n,
  input logic            tdi,
  input logic            tdo,
  input logic            tdo_en,
  input tap_state_e      state,
  input logic [IR_W-1:0] ir_sr,
  input logic [IR_W-1:0] ir,
  input dr_sel_e         dr_sel,
  // captured into DFT_CTRL (R17)
  input logic            test_mode,
  input logic            scan_en,
  input logic            mbist_start,
  input logic            mbist_done,
  input logic            mbist_pass
);

  `include "jtag_checker_defaults.svh"

  wire shifting = (state == SHIFT_IR) || (state == SHIFT_DR);

  // Expected values copied from the spec, not taken from jtag_pkg: if the RTL's
  // package constant were wrong, a shared constant would hide it.
  localparam logic [IR_W-1:0] SPEC_IR_CAPTURE = 4'b0001;        // R7
  localparam logic [31:0]     SPEC_IDCODE     = 32'h1114_9FFF;  // R13

  // ---------------------------------------------------------------- IR rules
  // R7: Capture-IR loads 0001
  a_capture_ir_01: assert property (state == CAPTURE_IR |=> ir_sr == SPEC_IR_CAPTURE);

  // R9: the instruction changes only in Update-IR or Test-Logic-Reset (sampled at
  // the rising edge after the falling-edge update, so no $past on the state)
  a_ir_stable: assert property ($changed(ir) |-> state inside {UPDATE_IR, TEST_LOGIC_RESET});
  a_ir_update: assert property (state == UPDATE_IR |-> ir == ir_sr);
  a_reset_idcode: assert property (state == TEST_LOGIC_RESET |-> ir == OP_IDCODE);

  // R10: decode, written independently of jtag_pkg::decode_ir
  a_decode_idcode:    assert property (ir == OP_IDCODE   |-> dr_sel == DR_IDCODE);
  a_decode_dft:       assert property (ir == OP_DFT_CTRL |-> dr_sel == DR_DFT_CTRL);
  a_unused_is_bypass: assert property (!(ir inside {OP_IDCODE, OP_DFT_CTRL}) |-> dr_sel == DR_BYPASS);

  // ---------------------------------------------------------------- TDO rules
  // R5/R6: tdo and tdo_en are set at the falling edge from the state entered at
  // the previous rising edge, i.e. the state sampled at the next rising edge
  a_tdo_en:        assert property (tdo_en == shifting);
  a_tdo_idle_zero: assert property (!shifting |-> !tdo);

  // R9 (c), R18: asynchronous reset
  `ASSERT_TRST(a_trst_ir,  ir == OP_IDCODE)
  `ASSERT_TRST(a_trst_tdo, !tdo && !tdo_en)

  // ---------------------------------------------------------------- scan model
  // Symbolic indices: constant, any value (free initial value in formal)
  logic [4:0] k;
  logic [5:0] j;
`ifdef QUESTA_FORMAL
  always_ff @(posedge tck) begin
    k <= k;
    j <= j;
  end
`else
  // Simulation: a new random k / j at every capture (constant within a scan),
  // so one run checks many bit positions; pin with +scan_k=<n> / +scan_j=<n>
  int pin_k = -1, pin_j = -1;
  initial begin
    void'($value$plusargs("scan_k=%d", pin_k));
    void'($value$plusargs("scan_j=%d", pin_j));
    k = 5'(pin_k >= 0 ? pin_k : $urandom_range(31, 0));
    j = 6'(pin_j >= 0 ? pin_j : $urandom_range(63, 0));
  end
  always @(posedge tck)
    if (state == CAPTURE_IR || state == CAPTURE_DR) begin
      if (pin_k < 0) k <= 5'($urandom_range(31, 0));
      if (pin_j < 0) j <= 6'($urandom_range(63, 0));
    end
`endif

  function automatic logic [5:0] dr_len(logic [IR_W-1:0] op);
    case (op)
      OP_IDCODE:   return 6'd32;
      OP_DFT_CTRL: return 6'd8;
      default:     return 6'd1;
    endcase
  endfunction

  logic [5:0]  len;        // length of the register in the current scan (0: no scan yet)
  logic [31:0] cap;        // value the spec says it captured
  logic [6:0]  cnt;        // shifts since capture, saturating
  logic        tracked;    // tdi sampled at shift number j

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      len     <= '0;
      cap     <= '0;
      cnt     <= '0;
      tracked <= 1'b0;
    end else if (state == CAPTURE_IR) begin
      len <= 6'(IR_W);
      cap <= 32'(SPEC_IR_CAPTURE);                                  // R7
      cnt <= '0;
    end else if (state == CAPTURE_DR) begin
      len <= dr_len(ir);
      case (ir)
        OP_IDCODE:   cap <= SPEC_IDCODE;                            // R13
        OP_DFT_CTRL: cap <= 32'({3'b000, mbist_pass, mbist_done,    // R17
                                 mbist_start, scan_en, test_mode});
        default:     cap <= '0;                                     // R12
      endcase
      cnt <= '0;
    end else if (shifting) begin
      if (cnt == 7'(j)) tracked <= tdi;
      if (cnt != '1)    cnt <= cnt + 1'b1;
    end
  end

  // R8, R11-R13, R17: every captured bit leaves on TDO in order, LSB first
  a_scan_data: assert property (shifting && cnt == 7'(k) && 6'(k) < len |-> tdo == cap[k]);

  // R11-R13: after the register, TDO is TDI delayed by the register length
  // (BYPASS: one shift; IDCODE: 32 shifts; IR: 4 shifts)
  a_scan_delay: assert property (shifting && len != 0 && cnt == 7'(j) + 7'(len) |-> tdo == tracked);

  // Non-vacuity, one per register: the last captured bit leaves (a_scan_data)
  // and an over-length scan returns TDI (a_scan_delay). A wrong length in the
  // model would leave a register unchecked while both proofs still pass.
  c_scan_data_last_ir:     cover property (state == SHIFT_IR && cnt == 7'(k) && 6'(k) == len - 1 && len == 6'd4);
  c_scan_data_last_bypass: cover property (state == SHIFT_DR && cnt == 7'(k) && 6'(k) == len - 1 && len == 6'd1);
  c_scan_data_last_idcode: cover property (state == SHIFT_DR && cnt == 7'(k) && 6'(k) == len - 1 && len == 6'd32);
  c_scan_data_last_dft:    cover property (state == SHIFT_DR && cnt == 7'(k) && 6'(k) == len - 1 && len == 6'd8);
  c_scan_delay_ir:         cover property (state == SHIFT_IR && cnt == 7'(j) + 7'(len) && len == 6'd4);
  c_scan_delay_bypass:     cover property (state == SHIFT_DR && cnt == 7'(j) + 7'(len) && len == 6'd1);
  c_scan_delay_idcode:     cover property (state == SHIFT_DR && cnt == 7'(j) + 7'(len) && len == 6'd32);
  c_scan_delay_dft:        cover property (state == SHIFT_DR && cnt == 7'(j) + 7'(len) && len == 6'd8);

  // ---------------------------------------------------------------- edge checks
  // Falling-edge signals must not move between a rising and the next falling
  // edge. Shadows reset to the spec reset values (R9, R18).
  logic           tdo_at_rise, tdo_en_at_rise;
  logic [IR_W-1:0] ir_at_rise;
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo_at_rise    <= 1'b0;
      tdo_en_at_rise <= 1'b0;
      ir_at_rise     <= OP_IDCODE;
    end else begin
      tdo_at_rise    <= tdo;
      tdo_en_at_rise <= tdo_en;
      ir_at_rise     <= ir;
    end
  end

  a_tdo_no_rise_change:    assert property (@(negedge tck) tdo    == tdo_at_rise);
  a_tdo_en_no_rise_change: assert property (@(negedge tck) tdo_en == tdo_en_at_rise);
  a_ir_no_rise_change:     assert property (@(negedge tck) ir     == ir_at_rise);

endmodule
