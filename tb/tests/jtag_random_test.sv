// ============================================================================
// jtag_random_test.sv -- a weighted random mix of every legal activity: IR and
// DR scans (with and without pauses), DFT writes, idle, TCK stops, TMS and
// trst_n resets, and random TMS walks into any state followed by a reset
// (mid-scan resets, every arc). mbist_fail_i toggles in the background.
// Everything is checked by the scoreboard and the monitors.
//   make uvm TEST=jtag_random_test SEED=<n>     (+n_items=<n> to change the length)
// ============================================================================
class jtag_random_seq extends jtag_base_seq;
  `uvm_object_utils(jtag_random_seq)

  int unsigned n_items      = 400;
  int unsigned mbist_cycles = 16;

  function new(string name = "jtag_random_seq");
    super.new(name);
  endfunction

  task body();
    do_reset_trst();
    repeat (n_items) begin
      int unsigned pick = $urandom_range(99);
      if      (pick < 25) random_ir();
      else if (pick < 60) random_dr();
      else if (pick < 67) dft_write();
      else if (pick < 75) do_idle($urandom_range(1, mbist_cycles + 4));
      else if (pick < 80) tck_stop();
      else if (pick < 85) do_reset_tms();
      else if (pick < 90) do_reset_trst($urandom_range(1));
      else                walk_then_reset();
    end
  endtask

  // IR scan: mostly the defined instructions, sometimes an unused opcode.
  // Mostly IR_W bits; sometimes longer (random bits first: they pass through to
  // TDO, R8, and the last IR_W bits are still op), shorter or empty (part of the
  // capture value 0001 stays in the IR, R7).
  task random_ir();
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    logic [IR_W-1:0] op;
    int unsigned     n;
    case ($urandom_range(9))
      0, 1, 2: op = OP_DFT_CTRL;
      3, 4:    op = OP_IDCODE;
      5, 6:    op = OP_BYPASS;
      default: op = IR_W'($urandom);              // any opcode, incl. unused ones
    endcase
    case ($urandom_range(9))
      0:       n = $urandom_range(IR_W - 1);       // short or empty
      1, 2:    n = IR_W + $urandom_range(1, 64);   // long: covers every j of a_scan_delay
      default: n = IR_W;
    endcase
    repeat (n > IR_W ? n - IR_W : 0) it.tdi_q.push_back(1'($urandom));
    for (int i = 0; i < IR_W && i < n; i++) it.tdi_q.push_back(op[i]);
    start_item(it);
    // The length is n even when n == 0 (an empty tdi_q otherwise means "random")
    it.len_fixed = 1'b1;
    if (!it.randomize() with { kind == jtag_seq_item::IR_SCAN; })
      `uvm_fatal("RAND", "IR item randomization failed")
    finish_item(it);
  endtask

  // DR scan: random length 0..80, random data, sometimes a pause
  task random_dr();
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    start_item(it);
    if (!it.randomize() with { kind == jtag_seq_item::DR_SCAN; })
      `uvm_fatal("RAND", "DR item randomization failed")
    finish_item(it);
  endtask

  // Select DFT_CTRL and write 8 random bits (test mode, scan, MBIST start)
  task dft_write();
    ir_scan(OP_DFT_CTRL);
    dr_scan(8, 64'($urandom_range(255)));
  endtask

  task tck_stop();
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    start_item(it);
    if (!it.randomize() with { kind == jtag_seq_item::TCK_STOP; })
      `uvm_fatal("RAND", "TCK_STOP item randomization failed")
    finish_item(it);
  endtask

  // Random TMS steps into any state, then a reset of a random kind
  task walk_then_reset();
    bit q[$];
    repeat ($urandom_range(1, 12)) q.push_back(1'($urandom));
    tms_path(q);
    case ($urandom_range(3))
      0, 1: do_reset_tms();
      2:    do_reset_trst();
      3:    do_reset_trst(1'b1);
    endcase
  endtask
endclass

class jtag_random_test extends jtag_base_test;
  `uvm_component_utils(jtag_random_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_stimulus();
    jtag_random_seq seq = jtag_random_seq::type_id::create("seq");
    int n;
    seq.mbist_cycles = env.sb.mbist_cycles;
    if ($value$plusargs("n_items=%d", n)) seq.n_items = n;
    dvif.mbist_fail_i = 1'b0;
    fork
      seq.start(env.agent.sqr);
      // MBIST result input: toggles at random falling edges
      forever begin
        repeat ($urandom_range(5, 60)) @(negedge dvif.tck);
        dvif.mbist_fail_i = ~dvif.mbist_fail_i;
      end
    join_any
    disable fork;
  endtask
endclass
