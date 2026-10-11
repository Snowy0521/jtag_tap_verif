// ============================================================================
// jtag_tap_top.sv -- IEEE 1149.1 TAP with a DFT control register.
// FSM + IR + DRs + MBIST stub, and the falling-edge TDO stage (R5, R6, R18).
// ============================================================================
module jtag_tap_top
  import jtag_pkg::*;
#(
  parameter int MBIST_CYCLES = 16
) (
  input  logic tck,
  input  logic tms,
  input  logic tdi,
  input  logic trst_n,
  output logic tdo,
  output logic tdo_en,
  input  logic mbist_fail_i,
  output logic test_mode,
  output logic scan_en,
  output logic mbist_start,
  output logic mbist_done,
  output logic mbist_pass
);

  tap_state_e      state;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [IR_W-1:0] ir_sr;             // only bit 0 feeds TDO; all bits are observed by formal binds
  /* verilator lint_on UNUSEDSIGNAL */
  logic [IR_W-1:0] ir;
  dr_sel_e         dr_sel;
  logic            dr_tdo;

  jtag_tap_fsm u_fsm (
    .tck    (tck),
    .trst_n (trst_n),
    .tms    (tms),
    .state  (state)
  );

  jtag_ir u_ir (
    .tck    (tck),
    .trst_n (trst_n),
    .state  (state),
    .tdi    (tdi),
    .ir_sr  (ir_sr),
    .ir     (ir)
  );

  assign dr_sel = decode_ir(ir);

  jtag_dr u_dr (
    .tck         (tck),
    .trst_n      (trst_n),
    .state       (state),
    .dr_sel      (dr_sel),
    .tdi         (tdi),
    .dr_tdo      (dr_tdo),
    .test_mode   (test_mode),
    .scan_en     (scan_en),
    .mbist_start (mbist_start),
    .mbist_done  (mbist_done),
    .mbist_pass  (mbist_pass)
  );

  mbist_stub #(.MBIST_CYCLES(MBIST_CYCLES)) u_mbist (
    .tck          (tck),
    .trst_n       (trst_n),
    .mbist_start  (mbist_start),
    .mbist_fail_i (mbist_fail_i),
    .mbist_done   (mbist_done),
    .mbist_pass   (mbist_pass)
  );

  // R5/R6: TDO stage on the falling edge; R18: async clear by trst_n.
  // Outside Shift-xR tdo is driven to 0 (the pad is high-Z via tdo_en).
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      tdo    <= 1'b0;
      tdo_en <= 1'b0;
    end else begin
      tdo_en <= (state == SHIFT_IR) || (state == SHIFT_DR);
      tdo    <= (state == SHIFT_IR) ? ir_sr[0] :
                (state == SHIFT_DR) ? dr_tdo   : 1'b0;
    end
  end

endmodule
