// ============================================================================
// jtag_base_seq.sv -- helper tasks for directed sequences.
// ============================================================================
class jtag_base_seq extends uvm_sequence #(jtag_seq_item);

  `uvm_object_utils(jtag_base_seq)

  function new(string name = "jtag_base_seq");
    super.new(name);
  endfunction

  protected task send(jtag_seq_item it);
    start_item(it);
    finish_item(it);
  endtask

  task do_reset_trst(bit short_pulse = 1'b0);
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    it.kind       = jtag_seq_item::RESET_TRST;
    it.trst_short = short_pulse;
    send(it);
  endtask

  // Raw TMS steps from Run-Test/Idle; must be followed by a reset
  task tms_path(bit tms_q[$]);
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    it.kind  = jtag_seq_item::TMS_PATH;
    it.tms_q = tms_q;
    send(it);
  endtask

  // IR or DR scan with a pause after bit pause_at
  task scan_with_pause(bit is_ir, bit q[$], int unsigned pause_at, int unsigned pause_cycles);
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    it.kind         = is_ir ? jtag_seq_item::IR_SCAN : jtag_seq_item::DR_SCAN;
    it.tdi_q        = q;
    it.use_pause    = 1'b1;
    it.pause_at     = pause_at;
    it.pause_cycles = pause_cycles;
    send(it);
  endtask

  task do_reset_tms();
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    it.kind = jtag_seq_item::RESET_TMS;
    send(it);
  endtask

  task do_idle(int unsigned cycles);
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    it.kind        = jtag_seq_item::IDLE;
    it.idle_cycles = cycles;
    send(it);
  endtask

  // Load an instruction (IR_W bits, LSB first)
  task ir_scan(logic [IR_W-1:0] op);
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    it.kind = jtag_seq_item::IR_SCAN;
    for (int i = 0; i < IR_W; i++) it.tdi_q.push_back(op[i]);
    send(it);
  endtask

  // DR scan of n bits, data LSB first (n <= 64)
  task dr_scan(int unsigned n, logic [63:0] data = '0);
    bit q[$];
    for (int i = 0; i < n; i++) q.push_back(data[i]);
    dr_scan_q(q);
  endtask

  // DR scan of any length
  task dr_scan_q(bit q[$]);
    jtag_seq_item it = jtag_seq_item::type_id::create("it");
    it.kind  = jtag_seq_item::DR_SCAN;
    it.tdi_q = q;
    send(it);
  endtask

  // DR scan of n random bits
  task dr_scan_rand(int unsigned n);
    bit q[$];
    repeat (n) q.push_back(1'($urandom));
    dr_scan_q(q);
  endtask

endclass
