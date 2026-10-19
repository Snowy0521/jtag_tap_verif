// ============================================================================
// dft_if.sv -- DFT outputs (observed only) and the MBIST stub result input.
// mon_cb samples just before each rising edge of TCK (see jtag_if).
// ============================================================================
interface dft_if (input logic tck);
  logic test_mode;
  logic scan_en;
  logic mbist_start;
  logic mbist_done;
  logic mbist_pass;
  logic mbist_fail_i;     // driven by the test

  clocking mon_cb @(posedge tck);
    default input #1step;
    input test_mode, scan_en, mbist_start, mbist_done, mbist_pass, mbist_fail_i;
  endclocking
endinterface
