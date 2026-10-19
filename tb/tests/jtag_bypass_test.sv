// ============================================================================
// jtag_bypass_test.sv -- BYPASS with random-length streams: first bit 0, then
// TDI delayed by one shift (R12), including scans longer than 64 bits.
// ============================================================================
class jtag_bypass_seq extends jtag_base_seq;
  `uvm_object_utils(jtag_bypass_seq)
  function new(string name = "jtag_bypass_seq");
    super.new(name);
  endfunction
  task body();
    do_reset_trst();
    ir_scan(OP_BYPASS);
    dr_scan(0);                             // zero-length scan
    dr_scan(1);
    repeat (10) dr_scan_rand($urandom_range(2, 100));
    dr_scan_rand(200);                      // well past any 64-bit limit
  endtask
endclass

class jtag_bypass_test extends jtag_base_test;
  `uvm_component_utils(jtag_bypass_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  task run_stimulus();
    jtag_bypass_seq seq = jtag_bypass_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
  endtask
endclass
