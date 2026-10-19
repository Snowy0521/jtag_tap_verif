// ============================================================================
// jtag_idcode_test.sv -- IDCODE after reset without loading an instruction,
// after loading it explicitly (incl. an over-length scan) and after a TMS
// reset (R9, R13). Checked by the scoreboard.
// ============================================================================
class jtag_idcode_seq extends jtag_base_seq;
  `uvm_object_utils(jtag_idcode_seq)
  function new(string name = "jtag_idcode_seq");
    super.new(name);
  endfunction
  task body();
    do_reset_trst();
    dr_scan(32);                            // IDCODE is the instruction after reset
    ir_scan(OP_BYPASS);
    ir_scan(OP_IDCODE);                     // load it explicitly
    dr_scan(40, 64'hA5);                    // over-length: A5 returns after 32 shifts
    do_reset_tms();
    dr_scan(32);                            // IDCODE again after a TMS reset
  endtask
endclass

class jtag_idcode_test extends jtag_base_test;
  `uvm_component_utils(jtag_idcode_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  task run_stimulus();
    jtag_idcode_seq seq = jtag_idcode_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
  endtask
endclass
