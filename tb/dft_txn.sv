// ============================================================================
// dft_txn.sv -- the DFT pins sampled at one rising edge of TCK (values just
// before the edge, as the DUT sees them), stamped with the edge number.
// ============================================================================
class dft_txn extends uvm_sequence_item;

  int unsigned cycle;          // rising edges of TCK so far (same count as jtag_monitor)
  bit          test_mode, scan_en, mbist_start, mbist_done, mbist_pass, mbist_fail_i;

  `uvm_object_utils(dft_txn)

  function new(string name = "dft_txn");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("cycle %0d: test_mode=%b scan_en=%b mbist_start=%b done=%b pass=%b fail_i=%b",
                     cycle, test_mode, scan_en, mbist_start, mbist_done, mbist_pass, mbist_fail_i);
  endfunction

endclass
