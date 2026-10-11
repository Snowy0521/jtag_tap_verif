// ============================================================================
// jtag_dr.sv -- data registers: BYPASS, IDCODE, DFT_CTRL (R11-R17).
// Shift registers on the rising edge, DFT_CTRL update registers on the
// falling edge. Only the selected register captures and shifts (R11).
// ============================================================================
module jtag_dr
  import jtag_pkg::*;
(
  input  logic        tck,
  input  logic        trst_n,
  input  tap_state_e  state,
  input  dr_sel_e     dr_sel,
  input  logic        tdi,
  output logic        dr_tdo,         // bit 0 of the selected shift register
  // DFT_CTRL update registers (outputs come straight from the flops)
  output logic        test_mode,
  output logic        scan_en,
  output logic        mbist_start,
  // MBIST stub status, captured in Capture-DR (R17)
  input  logic        mbist_done,
  input  logic        mbist_pass
);

  logic                bypass_sr;
  logic [IDCODE_W-1:0] idcode_sr;
  logic [DFT_W-1:0]    dft_sr;

  wire capture = (state == CAPTURE_DR);
  wire shift   = (state == SHIFT_DR);

  // ---------------- shift registers (rising edge) ----------------
  // R12: BYPASS captures 0
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)                                bypass_sr <= 1'b0;
    else if (dr_sel == DR_BYPASS && capture)    bypass_sr <= 1'b0;
    else if (dr_sel == DR_BYPASS && shift)      bypass_sr <= tdi;
  end

  // R13: IDCODE captures the fixed value, LSB out first
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)                                idcode_sr <= IDCODE_VAL;
    else if (dr_sel == DR_IDCODE && capture)    idcode_sr <= IDCODE_VAL;
    else if (dr_sel == DR_IDCODE && shift)      idcode_sr <= {tdi, idcode_sr[IDCODE_W-1:1]};
  end

  // R17: capture update registers (2:0), MBIST status (4:3), reserved 0 (7:5)
  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n)
      dft_sr <= '0;
    else if (dr_sel == DR_DFT_CTRL && capture)
      dft_sr <= {3'b000, mbist_pass, mbist_done, mbist_start, scan_en, test_mode};
    else if (dr_sel == DR_DFT_CTRL && shift)
      dft_sr <= {tdi, dft_sr[DFT_W-1:1]};
  end

  assign dr_tdo = (dr_sel == DR_IDCODE)   ? idcode_sr[0] :
                  (dr_sel == DR_DFT_CTRL) ? dft_sr[0]    : bypass_sr;

  // ---------------- DFT_CTRL update registers (falling edge) ----------------
  // R14: change only in Update-DR with DFT_CTRL active; cleared on the falling
  //      edge in Test-Logic-Reset and asynchronously by trst_n.
  // R15/R16: scan_en gated by test_mode at write time.
  always_ff @(negedge tck or negedge trst_n) begin
    if (!trst_n) begin
      test_mode   <= 1'b0;
      scan_en     <= 1'b0;
      mbist_start <= 1'b0;
    end else if (state == TEST_LOGIC_RESET) begin
      test_mode   <= 1'b0;
      scan_en     <= 1'b0;
      mbist_start <= 1'b0;
    end else if (state == UPDATE_DR && dr_sel == DR_DFT_CTRL) begin
      test_mode   <= dft_sr[0];
      scan_en     <= dft_sr[1] & dft_sr[0];
      mbist_start <= dft_sr[2];
    end
  end

endmodule
