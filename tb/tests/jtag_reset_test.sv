// ============================================================================
// jtag_reset_test.sv -- reset from every TAP state, by five TMS = 1 (R2), by a
// full trst_n pulse and by a short trst_n pulse between two edges (R3), each
// time from test mode with a non-default instruction. The scoreboard checks
// that the DFT outputs return to 0 (R14, R23) and IDCODE is selected again (R9).
// ============================================================================
class jtag_reset_seq extends jtag_base_seq;
  `uvm_object_utils(jtag_reset_seq)
  function new(string name = "jtag_reset_seq");
    super.new(name);
  endfunction

  // TMS paths from Run-Test/Idle into each of the 16 states
  typedef struct {string name; bit tms[$];} path_t;
  path_t paths[$];

  function void add(string name, bit tms[$]);
    path_t p;
    p.name = name;
    p.tms  = tms;
    paths.push_back(p);
  endfunction

  task body();
    add("RUN_TEST_IDLE",    '{});
    add("SELECT_DR_SCAN",   '{1});
    add("CAPTURE_DR",       '{1, 0});
    add("SHIFT_DR",         '{1, 0, 0, 0, 0});
    add("EXIT1_DR",         '{1, 0, 0, 1});
    add("PAUSE_DR",         '{1, 0, 0, 1, 0});
    add("EXIT2_DR",         '{1, 0, 0, 1, 0, 1});
    add("UPDATE_DR",        '{1, 0, 0, 1, 1});
    add("SELECT_IR_SCAN",   '{1, 1});
    add("CAPTURE_IR",       '{1, 1, 0});
    add("SHIFT_IR",         '{1, 1, 0, 0, 0});
    add("EXIT1_IR",         '{1, 1, 0, 0, 1});
    add("PAUSE_IR",         '{1, 1, 0, 0, 1, 0});
    add("EXIT2_IR",         '{1, 1, 0, 0, 1, 0, 1});
    add("UPDATE_IR",        '{1, 1, 0, 0, 1, 1});
    add("TEST_LOGIC_RESET", '{1, 1, 1});

    do_reset_trst();
    foreach (paths[i]) begin
      for (int how = 0; how < 3; how++) begin    // 0: five TMS = 1, 1: trst_n, 2: short trst_n
        // Leave functional mode and the default instruction, so the reset has
        // something to undo
        ir_scan(OP_DFT_CTRL);
        dr_scan(8, 8'b0000_0111);                 // test_mode, scan_en, mbist_start
        `uvm_info("RST", $sformatf("reset from %s by %s", paths[i].name,
                  how == 0 ? "TMS" : how == 1 ? "trst_n" : "short trst_n"), UVM_MEDIUM)
        tms_path(paths[i].tms);
        case (how)
          0: do_reset_tms();
          1: do_reset_trst();
          2: do_reset_trst(1'b1);
        endcase
        dr_scan(32);                              // IDCODE must be selected again
      end
    end
  endtask
endclass

class jtag_reset_test extends jtag_base_test;
  `uvm_component_utils(jtag_reset_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  task run_stimulus();
    jtag_reset_seq seq = jtag_reset_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
  endtask
endclass
