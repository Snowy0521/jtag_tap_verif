// ============================================================================
// jtag_pause_test.sv -- IR and DR scans interrupted by Pause-xR / Exit2-xR:
// the shift continues where it stopped (R1, R8, R11).
// ============================================================================
class jtag_pause_seq extends jtag_base_seq;
  `uvm_object_utils(jtag_pause_seq)
  function new(string name = "jtag_pause_seq");
    super.new(name);
  endfunction

  function automatic void bits(output bit q[$], input int unsigned n, input logic [63:0] v = '0, input bit rnd = 1'b0);
    q.delete();
    for (int i = 0; i < n; i++) q.push_back(rnd ? 1'($urandom) : v[i]);
  endfunction

  task body();
    bit q[$];
    do_reset_trst();
    bits(q, 32);
    scan_with_pause(1'b0, q, 15, 3);               // IDCODE read, paused after bit 15
    bits(q, 4, OP_BYPASS);
    scan_with_pause(1'b1, q, 1, 0);                // IR scan paused (zero extra Pause cycles)
    bits(q, 100, 0, 1'b1);
    scan_with_pause(1'b0, q, 50, 5);               // long BYPASS stream with a pause
    bits(q, 4, OP_DFT_CTRL);
    scan_with_pause(1'b1, q, 2, 2);
    bits(q, 8, 8'b0000_0011);
    scan_with_pause(1'b0, q, 3, 1);                // DFT write with a pause: test_mode + scan_en
    bits(q, 8, 8'b0000_0000);
    for (int at = 0; at < 7; at++) scan_with_pause(1'b0, q, at, 1);   // pause at every position
  endtask
endclass

class jtag_pause_test extends jtag_base_test;
  `uvm_component_utils(jtag_pause_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  task run_stimulus();
    jtag_pause_seq seq = jtag_pause_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
  endtask
endclass
