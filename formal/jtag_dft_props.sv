// ============================================================================
// jtag_dft_props.sv -- DFT control register and MBIST stub checks (R14-R16,
// R19-R21). Bound into jtag_tap_top by formal_top.sv.
// The DFT shift register is modelled here from the spec, so the write checks
// do not depend on the RTL's shift register.
// ============================================================================
module jtag_dft_props
  import jtag_pkg::*;
#(
  parameter int MBIST_CYCLES = 16
) (
  input logic            tck,
  input logic            trst_n,
  input logic            tdi,
  input tap_state_e      state,
  input logic [IR_W-1:0] ir,
  input logic            test_mode,
  input logic            scan_en,
  input logic            mbist_start,
  input logic            mbist_done,
  input logic            mbist_pass,
  input logic            mbist_fail_i
);

  `include "jtag_checker_defaults.svh"

  wire dft_sel = (ir == OP_DFT_CTRL);

  // ---------------------------------------------------------------- DFT register
  // Model of the DFT_CTRL shift register (R11, R17)
  logic [DFT_W-1:0] dsr;
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)
      dsr <= '0;
    else if (state == CAPTURE_DR && dft_sel)
      dsr <= {3'b000, mbist_pass, mbist_done, mbist_start, scan_en, test_mode};
    else if (state == SHIFT_DR && dft_sel)
      dsr <= {tdi, dsr[DFT_W-1:1]};
  end

  // R14 (a)-(b): outputs change only on a DFT_CTRL Update-DR or in Test-Logic-Reset
  a_dft_update_only: assert property ($changed({test_mode, scan_en, mbist_start}) |->
    (state == UPDATE_DR && dft_sel) || state == TEST_LOGIC_RESET);

  // R15: the value written, with scan_en gated by test_mode
  a_dft_write: assert property (state == UPDATE_DR && dft_sel |->
    test_mode == dsr[0] && scan_en == (dsr[1] && dsr[0]) && mbist_start == dsr[2]);

  // R14 (b): Test-Logic-Reset returns the chip to functional mode
  a_dft_reset_functional: assert property (state == TEST_LOGIC_RESET |->
    !test_mode && !scan_en && !mbist_start);

  // R14 (c): asynchronous reset to functional mode
  `ASSERT_TRST(a_trst_dft, !test_mode && !scan_en && !mbist_start)

  // R16: safety
  a_scan_en_safe: assert property (scan_en |-> test_mode);

  // ---------------------------------------------------------------- MBIST stub
  // Checker counter: rising edges that sample mbist_start = 1, saturating
  localparam int MCNT_W = $clog2(MBIST_CYCLES + 1);
  logic [MCNT_W-1:0] mcnt;
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)                                  mcnt <= '0;
    else if (!mbist_start)                        mcnt <= '0;
    else if (mcnt != MCNT_W'(MBIST_CYCLES))       mcnt <= mcnt + 1'b1;
  end

  // R20: done exactly at the MBIST_CYCLES-th edge
  a_mbist_done_exact: assert property (mbist_done == (mcnt == MCNT_W'(MBIST_CYCLES)));
  // R19: dropping mbist_start clears the stub
  a_mbist_clear: assert property (!mbist_start |=> !mbist_done && !mbist_pass);
  // R20/R21: once done, done and pass hold while mbist_start stays 1
  a_mbist_hold: assert property (mbist_done && mbist_start |=> $stable({mbist_done, mbist_pass}));
  // R20: pass = !mbist_fail_i, sampled at the edge that sets done
  a_mbist_pass_value: assert property ($rose(mbist_done) |-> mbist_pass == !$past(mbist_fail_i));
  a_mbist_pass_needs_done: assert property (mbist_pass |-> mbist_done);

  // ---------------------------------------------------------------- edge checks
  // The DFT update registers must not move between a rising and the next falling
  // edge. Not applied to mbist_done / mbist_pass: the stub runs on the rising edge.
  logic [2:0] dft_at_rise;
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) dft_at_rise <= 3'b000;                  // R14 (c) reset value
    else         dft_at_rise <= $sampled({test_mode, scan_en, mbist_start});   // pre-edge value, see jtag_reg_props
  end

  a_dft_no_rise_change: assert property (@(negedge tck)
    {test_mode, scan_en, mbist_start} == dft_at_rise);

endmodule
