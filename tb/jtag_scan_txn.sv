// ============================================================================
// jtag_scan_txn.sv -- what the monitor observed on the pins: one scan, or a
// reset (trst_n, or Test-Logic-Reset reached via TMS). Built only from pin
// activity, never from the driver's item.
// ============================================================================
class jtag_scan_txn extends uvm_sequence_item;

  typedef enum {IR, DR, RESET} scan_e;

  scan_e      scan;
  tap_state_e path[$];   // states sampled during the scan, Capture-xR to Update-xR
  bit         tdi_q[$];  // bits shifted in, LSB first
  bit         tdo_q[$];  // bits shifted out, LSB first
  bit         aborted;   // ended by trst_n before Update-xR
  bit         trst;      // RESET: caused by trst_n (not by TMS)
  // Cycle stamps (rising edges of TCK, same count as dft_monitor):
  int unsigned cap_cycle; // edge that captured (the DFT sample with this number holds the captured status)
  int unsigned cycle;     // first DFT sample that shows the effect of this scan's Update / of this reset

  `uvm_object_utils(jtag_scan_txn)

  function new(string name = "jtag_scan_txn");
    super.new(name);
  endfunction

  // Bits [n-1:0] of a queue as a number (n <= 64)
  static function logic [63:0] bits(const ref bit q[$], input int n);
    logic [63:0] v = '0;
    for (int i = 0; i < n && i < q.size(); i++) v[i] = q[i];
    return v;
  endfunction

  function string convert2string();
    string ab = "";
    if (scan == RESET) return "RESET";
    if (aborted) ab = " (aborted)";
    return $sformatf("%s scan, %0d bits%s, tdi=0x%0h tdo=0x%0h", scan.name(), tdi_q.size(),
                     ab, bits(tdi_q, 64), bits(tdo_q, 64));
  endfunction

endclass
