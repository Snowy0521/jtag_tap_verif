// ============================================================================
// jtag_unused_opcode_test.sv -- every opcode without its own register behaves
// like BYPASS (R10), including EXTEST and SAMPLE/PRELOAD while boundary scan is
// not implemented.
// ============================================================================
class jtag_unused_opcode_seq extends jtag_base_seq;
  `uvm_object_utils(jtag_unused_opcode_seq)
  function new(string name = "jtag_unused_opcode_seq");
    super.new(name);
  endfunction
  task body();
    do_reset_trst();
    for (int op = 0; op < 2**IR_W; op++) begin
      if (op inside {OP_IDCODE, OP_DFT_CTRL, OP_BYPASS}) continue;
      ir_scan(IR_W'(op));
      dr_scan_rand($urandom_range(2, 40));
    end
  endtask
endclass

class jtag_unused_opcode_test extends jtag_base_test;
  `uvm_component_utils(jtag_unused_opcode_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  task run_stimulus();
    jtag_unused_opcode_seq seq = jtag_unused_opcode_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
  endtask
endclass
