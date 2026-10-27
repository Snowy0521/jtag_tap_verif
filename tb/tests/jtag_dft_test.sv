// ============================================================================
// jtag_dft_test.sv -- DFT control register (R14-R21): scan_en gating, write and
// read-back, reserved bits, short writes, MBIST pass / fail / restart /
// redundant start, writes with another instruction active, and return to
// functional mode on reset. The scoreboard checks every read-back bit, the DFT
// outputs at every edge and the MBIST timing.
// ============================================================================
class jtag_dft_seq extends jtag_base_seq;
  `uvm_object_utils(jtag_dft_seq)
  int unsigned mbist_cycles = 16;
  function new(string name = "jtag_dft_seq");
    super.new(name);
  endfunction
  task body();
    do_reset_trst();
    ir_scan(OP_DFT_CTRL);
    dr_scan(8, 8'b0000_0010);                     // scan_en without test_mode: blocked (R15/R16)
    dr_scan(8, 8'b0000_0011);                     // test_mode + scan_en
    dr_scan(8, 8'b1110_0001);                     // reserved bits written as 1: read back 0 (R17)
    dr_scan(2, 2'b11);                            // short write (2 bits)
    dr_scan(8, 8'b0000_0101);                     // test_mode + mbist_start
    do_idle(mbist_cycles + 4);                    // MBIST runs to done
    dr_scan(8, 8'b0000_0101);                     // read back done / pass; redundant start (R21)
    dr_scan(8, 8'b0000_0001);                     // drop mbist_start: stub clears
    dr_scan(8, 8'b0000_0101);                     // restart
    do_idle(mbist_cycles / 2);
    dr_scan(8, 8'b0000_0101);                     // read back while running
    ir_scan(OP_BYPASS);
    dr_scan(8, 8'b0000_0000);                     // DR scan with another instruction: no DFT change (R14)
    ir_scan(OP_DFT_CTRL);
    do_idle(mbist_cycles);
    dr_scan(8, 8'b0000_0101);
  endtask
endclass

class jtag_dft_fail_seq extends jtag_base_seq;
  `uvm_object_utils(jtag_dft_fail_seq)
  int unsigned mbist_cycles = 16;
  function new(string name = "jtag_dft_fail_seq");
    super.new(name);
  endfunction
  task body();
    dr_scan(8, 8'b0000_0001);                     // drop mbist_start
    dr_scan(8, 8'b0000_0101);                     // start a failing run
    do_idle(mbist_cycles + 4);
    dr_scan(8, 8'b0000_0101);                     // read back done = 1, pass = 0
    do_reset_tms();                               // back to functional mode (R14)
    dr_scan(32);                                  // IDCODE again
  endtask
endclass

class jtag_dft_test extends jtag_base_test;
  `uvm_component_utils(jtag_dft_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  task run_stimulus();
    jtag_dft_seq      seq  = jtag_dft_seq::type_id::create("seq");
    jtag_dft_fail_seq fseq = jtag_dft_fail_seq::type_id::create("fseq");
    seq.mbist_cycles  = env.sb.mbist_cycles;
    fseq.mbist_cycles = env.sb.mbist_cycles;
    dvif.mbist_fail_i = 1'b0;
    seq.start(env.agent.sqr);
    dvif.mbist_fail_i = 1'b1;                     // the next MBIST run fails
    fseq.start(env.agent.sqr);
    dvif.mbist_fail_i = 1'b0;
  endtask
endclass
