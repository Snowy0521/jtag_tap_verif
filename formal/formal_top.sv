// ============================================================================
// formal_top.sv -- formal harness: the DUT with every input free, plus the
// checkers bound into it.
// No assumptions anywhere: every input sequence is legal JTAG.
// ============================================================================
module formal_top (
  input  logic tck,
  input  logic tms,
  input  logic tdi,
  input  logic trst_n,
  input  logic mbist_fail_i,
  output logic tdo,
  output logic tdo_en,
  output logic test_mode,
  output logic scan_en,
  output logic mbist_start,
  output logic mbist_done,
  output logic mbist_pass
);

  // Small MBIST_CYCLES keeps the MBIST covers shallow
  jtag_tap_top #(.MBIST_CYCLES(4)) dut (.*);

  // Checkers, bound into jtag_tap_top so they can see internal signals. The bind
  // sits inside the harness module to keep the harness in one compilation unit.
  bind jtag_tap_top jtag_tap_fsm_props u_fsm_props (
    .tck    (tck),
    .trst_n (trst_n),
    .tms    (tms),
    .state  (state)
  );

  bind jtag_tap_top jtag_reg_props u_reg_props (
    .tck         (tck),
    .trst_n      (trst_n),
    .tdi         (tdi),
    .tdo         (tdo),
    .tdo_en      (tdo_en),
    .state       (state),
    .ir_sr       (ir_sr),
    .ir          (ir),
    .dr_sel      (dr_sel),
    .test_mode   (test_mode),
    .scan_en     (scan_en),
    .mbist_start (mbist_start),
    .mbist_done  (mbist_done),
    .mbist_pass  (mbist_pass)
  );

  bind jtag_tap_top jtag_dft_props #(.MBIST_CYCLES(MBIST_CYCLES)) u_dft_props (
    .tck          (tck),
    .trst_n       (trst_n),
    .tdi          (tdi),
    .state        (state),
    .ir           (ir),
    .test_mode    (test_mode),
    .scan_en      (scan_en),
    .mbist_start  (mbist_start),
    .mbist_done   (mbist_done),
    .mbist_pass   (mbist_pass),
    .mbist_fail_i (mbist_fail_i)
  );

  bind jtag_tap_top jtag_covers u_covers (
    .tck         (tck),
    .trst_n      (trst_n),
    .state       (state),
    .ir          (ir),
    .test_mode   (test_mode),
    .scan_en     (scan_en),
    .mbist_start (mbist_start),
    .mbist_done  (mbist_done),
    .mbist_pass  (mbist_pass)
  );

endmodule
