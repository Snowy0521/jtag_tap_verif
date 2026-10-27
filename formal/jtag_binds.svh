// ============================================================================
// jtag_binds.svh -- binds every checker into jtag_tap_top. Included inside the
// top module of both the formal harness (formal_top.sv) and the UVM bench
// (tb_top.sv), so formal and simulation always check the same properties.
// ============================================================================

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
