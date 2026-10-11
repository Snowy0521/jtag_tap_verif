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

endmodule
