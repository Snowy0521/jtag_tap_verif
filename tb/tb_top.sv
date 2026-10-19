// ============================================================================
// tb_top.sv -- UVM top: TCK generation, DUT, interfaces, run_test.
// ============================================================================
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import jtag_tb_pkg::*;

  localparam int unsigned MBIST_CYCLES = 16;

  jtag_if jif ();
  dft_if  dif (jif.tck);

  // Free-running TCK, gated by tck_en. A disabled clock is forced low, so
  // stopping and restarting it never makes a short pulse.
  initial begin
    jif.tck    = 1'b0;
    jif.tck_en = 1'b1;
  end
  always #(TCK_PERIOD_NS / 2.0) jif.tck = jif.tck_en ? ~jif.tck : 1'b0;

  jtag_tap_top #(.MBIST_CYCLES(MBIST_CYCLES)) dut (
    .tck          (jif.tck),
    .tms          (jif.tms),
    .tdi          (jif.tdi),
    .trst_n       (jif.trst_n),
    .tdo          (jif.tdo),
    .tdo_en       (jif.tdo_en),
    .mbist_fail_i (dif.mbist_fail_i),
    .test_mode    (dif.test_mode),
    .scan_en      (dif.scan_en),
    .mbist_start  (dif.mbist_start),
    .mbist_done   (dif.mbist_done),
    .mbist_pass   (dif.mbist_pass)
  );

  initial begin
    string test = "jtag_idcode_test";
    dif.mbist_fail_i = 1'b0;
    uvm_config_db #(virtual jtag_if)::set(null, "*", "jtag_vif", jif);
    uvm_config_db #(virtual dft_if)::set(null, "*", "dft_vif", dif);
    uvm_config_db #(int unsigned)::set(null, "*", "mbist_cycles", MBIST_CYCLES);
    // Read the test name ourselves: works in every simulator, with or without DPI
    void'($value$plusargs("UVM_TESTNAME=%s", test));
    run_test(test);
  end

endmodule
