// ============================================================================
// jtag_coverage.sv -- functional coverage (plan §3.4), from the monitors only.
//
// Every event is first classified into small enums; each bin is one enum value
// or combination, so the bins are defined in one place. Two views of the same
// classification:
//   - covergroups: the sign-off numbers (QuestaSim UCDB, merged by vcover);
//   - TB counters: the same combinations counted here and reported with their
//     holes. They work in every simulator (Verilator parses covergroups but
//     does not count them) and can be summed across runs by the regression.
// ============================================================================
`uvm_analysis_imp_decl(_edge)

class jtag_coverage extends uvm_component;

  `uvm_component_utils(jtag_coverage)

  uvm_analysis_imp_jtag #(jtag_scan_txn, jtag_coverage) jtag_imp;
  uvm_analysis_imp_dft  #(dft_txn,       jtag_coverage) dft_imp;
  uvm_analysis_imp_edge #(jtag_edge_txn, jtag_coverage) edge_imp;

  // ---------------------------------------------------------------- classes
  typedef enum {I_IDCODE, I_BYPASS, I_DFT_CTRL, I_UNUSED}      instr_e;
  typedef enum {R_BYPASS, R_IDCODE, R_DFT_CTRL}                reg_e;
  typedef enum {L_ZERO, L_SHORT, L_EXACT, L_LONG}              len_e;    // vs. the register length
  typedef enum {S_IR, S_DR}                                    scan_e;
  typedef enum {P_NONE, P_ONE, P_MULTI}                        pause_e;  // pauses in one scan
  typedef enum {MB_PASS, MB_FAIL, MB_RESTART, MB_REDUNDANT_START} mbist_e;
  typedef enum {RST_TMS, RST_TRST}                             rst_e;

  // ---------------------------------------------------------------- sampled values
  tap_state_e  arc_state;   bit arc_tms;
  instr_e      instr_loaded;
  reg_e        dr_reg;      len_e dr_len;
  scan_e       scan_kind;   pause_e scan_pauses;
  bit          tm, se, ms;
  mbist_e      mbist_evt;
  rst_e        rst_kind;    tap_state_e rst_from;
  scan_e       aborted_kind;

  // ---------------------------------------------------------------- covergroups
  covergroup cg_arc;                    // all 32 transitions of the TAP state machine
    // Helper coverpoints only build the cross; weight 0 keeps their own bins out
    // of the percentage, so it means the same bins as the TB counters
    cp_state: coverpoint arc_state { option.weight = 0; }
    cp_tms:   coverpoint arc_tms   { option.weight = 0; }
    x_arc:    cross cp_state, cp_tms;
  endgroup

  covergroup cg_instr;                  // instruction loaded by a completed IR scan
    cp_instr: coverpoint instr_loaded;
  endgroup

  covergroup cg_dr_len;                 // DR scan length vs. the selected register
    cp_reg: coverpoint dr_reg { option.weight = 0; }
    cp_len: coverpoint dr_len { option.weight = 0; }
    x_reg_len: cross cp_reg, cp_len {
      ignore_bins bypass_short = binsof(cp_reg) intersect {R_BYPASS} && binsof(cp_len) intersect {L_SHORT};
    }
  endgroup

  covergroup cg_pause;                  // pauses inside IR and DR scans
    cp_scan:  coverpoint scan_kind   { option.weight = 0; }
    cp_pause: coverpoint scan_pauses { option.weight = 0; }
    x_scan_pause: cross cp_scan, cp_pause;
  endgroup

  covergroup cg_dft;                    // DFT output combinations
    cp_tm: coverpoint tm { option.weight = 0; }
    cp_se: coverpoint se { option.weight = 0; }
    cp_ms: coverpoint ms { option.weight = 0; }
    // scan_en without test_mode is a check (a_scan_en_safe, scoreboard), not a goal
    x_dft: cross cp_tm, cp_se, cp_ms {
      illegal_bins se_without_tm = binsof(cp_se) intersect {1} && binsof(cp_tm) intersect {0};
    }
  endgroup

  covergroup cg_mbist;
    cp_evt: coverpoint mbist_evt;
  endgroup

  covergroup cg_reset;                  // reset kind, and the state trst_n hit
    cp_kind: coverpoint rst_kind;                           // a goal: TMS and trst_n resets
    cp_from: coverpoint rst_from { option.weight = 0; }
    x_trst_from: cross cp_kind, cp_from {
      ignore_bins tms = binsof(cp_kind) intersect {RST_TMS};  // via TMS it always comes from Select-IR-Scan
    }
  endgroup

  covergroup cg_abort;                  // scans aborted by trst_n
    cp_kind: coverpoint aborted_kind;
  endgroup

  // ---------------------------------------------------------------- TB counters
  int unsigned hits[string];            // "group:bin" -> count
  string       bins_expected[$];        // every bin that should be hit

  // ---------------------------------------------------------------- tracking
  bit [IR_W-1:0] instr = OP_IDCODE;     // active instruction, from the monitors
  dft_txn        samples[int unsigned];
  int unsigned   pending_redundant[$];  // scan cycles still to check for a redundant start
  bit            run_completed;         // an MBIST run finished since the last reset
  dft_txn        prev;
  bit            synced;                // a reset has been seen: before it the pins are X / random

  function new(string name, uvm_component parent);
    super.new(name, parent);
    jtag_imp = new("jtag_imp", this);
    dft_imp  = new("dft_imp",  this);
    edge_imp = new("edge_imp", this);
    cg_arc   = new();
    cg_instr = new();
    cg_dr_len = new();
    cg_pause = new();
    cg_dft   = new();
    cg_mbist = new();
    cg_reset = new();
    cg_abort = new();
    expect_bins();
  endfunction

  // The same bins as the covergroups above (incl. their ignore / illegal bins)
  function void expect_bins();
    tap_state_e s = s.first();
    do begin
      bins_expected.push_back({"arc:", s.name(), "/tms0"});
      bins_expected.push_back({"arc:", s.name(), "/tms1"});
      bins_expected.push_back({"trst_from:", s.name()});
      s = s.next();
    end while (s != s.first());
    for (instr_e i = i.first(); 1; i = i.next()) begin
      bins_expected.push_back({"instr:", i.name()});
      if (i == i.last()) break;
    end
    for (reg_e r = r.first(); 1; r = r.next()) begin
      for (len_e l = l.first(); 1; l = l.next()) begin
        if (!(r == R_BYPASS && l == L_SHORT)) bins_expected.push_back({"dr_len:", r.name(), "/", l.name()});
        if (l == l.last()) break;
      end
      if (r == r.last()) break;
    end
    for (scan_e k = k.first(); 1; k = k.next()) begin
      for (pause_e p = p.first(); 1; p = p.next()) begin
        bins_expected.push_back({"pause:", k.name(), "/", p.name()});
        if (p == p.last()) break;
      end
      bins_expected.push_back({"abort:", k.name()});
      if (k == k.last()) break;
    end
    for (int v = 0; v < 8; v++)
      if (!(v[1] && !v[2])) bins_expected.push_back($sformatf("dft:tm%0d_se%0d_ms%0d", v[2], v[1], v[0]));
    for (mbist_e m = m.first(); 1; m = m.next()) begin
      bins_expected.push_back({"mbist:", m.name()});
      if (m == m.last()) break;
    end
    bins_expected.push_back("reset:RST_TMS");
    bins_expected.push_back("reset:RST_TRST");
  endfunction

  function void hit(string b);
    if (!hits.exists(b)) hits[b] = 0;
    hits[b]++;
  endfunction

  // ---------------------------------------------------------------- edges
  function void write_edge(jtag_edge_txn e);
    arc_state = e.state;
    arc_tms   = e.tms;
    cg_arc.sample();
    hit($sformatf("arc:%s/tms%0d", e.state.name(), e.tms));
  endfunction

  // ---------------------------------------------------------------- scans, resets
  function void write_jtag(jtag_scan_txn t);
    if (t.scan == jtag_scan_txn::RESET) begin
      synced   = 1'b1;
      rst_kind = t.trst ? RST_TRST : RST_TMS;
      rst_from = t.from_state;
      cg_reset.sample();
      hit({"reset:", rst_kind.name()});
      if (t.trst) hit({"trst_from:", t.from_state.name()});
      instr         = OP_IDCODE;
      run_completed = 1'b0;
      return;
    end

    scan_kind   = (t.scan == jtag_scan_txn::IR) ? S_IR : S_DR;
    scan_pauses = count_pauses(t);
    cg_pause.sample();
    hit({"pause:", scan_kind.name(), "/", scan_pauses.name()});

    if (t.aborted) begin
      aborted_kind = scan_kind;
      cg_abort.sample();
      hit({"abort:", aborted_kind.name()});
      return;
    end

    if (t.scan == jtag_scan_txn::IR) begin
      instr        = ir_after(t);
      instr_loaded = classify(instr);
      cg_instr.sample();
      hit({"instr:", instr_loaded.name()});
    end else begin
      dr_reg = (instr == OP_IDCODE) ? R_IDCODE : (instr == OP_DFT_CTRL) ? R_DFT_CTRL : R_BYPASS;
      dr_len = len_class(t.tdi_q.size(), (dr_reg == R_IDCODE) ? 32 : (dr_reg == R_DFT_CTRL) ? 8 : 1);
      cg_dr_len.sample();
      hit({"dr_len:", dr_reg.name(), "/", dr_len.name()});
      // A DFT_CTRL write while mbist_start stays 1: checked once the samples
      // around its update have arrived
      if (dr_reg == R_DFT_CTRL) pending_redundant.push_back(t.cycle);
    end
  endfunction

  function pause_e count_pauses(jtag_scan_txn t);
    int n = 0;
    foreach (t.path[i])
      if ((t.path[i] == PAUSE_DR || t.path[i] == PAUSE_IR) &&
          (i == 0 || t.path[i-1] != t.path[i])) n++;
    return (n == 0) ? P_NONE : (n == 1) ? P_ONE : P_MULTI;
  endfunction

  // Instruction loaded at Update-IR: the IR shift register starting from 0001
  function bit [IR_W-1:0] ir_after(jtag_scan_txn t);
    bit sr[$] = '{1'b1, 1'b0, 1'b0, 1'b0};    // 0001, LSB first
    bit [IR_W-1:0] v;
    foreach (t.tdi_q[i]) begin
      void'(sr.pop_front());
      sr.push_back(t.tdi_q[i]);
    end
    foreach (sr[i]) v[i] = sr[i];
    return v;
  endfunction

  function instr_e classify(bit [IR_W-1:0] op);
    case (op)
      OP_IDCODE:   return I_IDCODE;
      OP_BYPASS:   return I_BYPASS;
      OP_DFT_CTRL: return I_DFT_CTRL;
      default:     return I_UNUSED;
    endcase
  endfunction

  function len_e len_class(int n, int reg_len);
    if (n == 0)       return L_ZERO;
    if (n < reg_len)  return L_SHORT;
    if (n == reg_len) return L_EXACT;
    return L_LONG;
  endfunction

  // ---------------------------------------------------------------- DFT pins
  function void write_dft(dft_txn s);
    if (!synced) return;
    samples[s.cycle] = s;
    if (prev != null) begin
      if ({s.test_mode, s.scan_en, s.mbist_start} != {prev.test_mode, prev.scan_en, prev.mbist_start}) begin
        tm = s.test_mode;
        se = s.scan_en;
        ms = s.mbist_start;
        // Every change is sampled: scan_en without test_mode hits the illegal bin,
        // which the simulator reports as an error (Questa). The TB counters do
        // the same for simulators that do not count covergroups.
        cg_dft.sample();
        if (se && !tm)
          `uvm_error("COV", $sformatf("illegal DFT combination at cycle %0d: scan_en without test_mode", s.cycle))
        else
          hit($sformatf("dft:tm%0d_se%0d_ms%0d", tm, se, ms));
      end
      if (s.mbist_done && !prev.mbist_done) begin
        mbist(s.mbist_pass ? MB_PASS : MB_FAIL);
        run_completed = 1'b1;
      end
      if (s.mbist_start && !prev.mbist_start && run_completed) mbist(MB_RESTART);
    end
    prev = s;
    // Redundant start: mbist_start 1 before and after a DFT_CTRL update
    while (pending_redundant.size() != 0 && samples.exists(pending_redundant[0])) begin
      int unsigned c = pending_redundant.pop_front();
      if (samples.exists(c - 1) && samples[c - 1].mbist_start && samples[c].mbist_start)
        mbist(MB_REDUNDANT_START);
    end
    if (s.cycle > 64) samples.delete(s.cycle - 64);
  endfunction

  function void mbist(mbist_e m);
    mbist_evt = m;
    cg_mbist.sample();
    hit({"mbist:", m.name()});
  endfunction

  // ---------------------------------------------------------------- report
  // With +cov_dump: one line per bin ("COV <bin> <count>"), so the regression
  // can add up runs. Then the summary and the holes.
  function void report_phase(uvm_phase phase);
    string holes = "";
    int    n_hit = 0;
    bit    dump  = $test$plusargs("cov_dump");
    foreach (bins_expected[i]) begin
      int unsigned n = hits.exists(bins_expected[i]) ? hits[bins_expected[i]] : 0;
      if (dump) $display("COV %s %0d", bins_expected[i], n);
      if (n != 0) n_hit++;
      else        holes = {holes, "\n  ", bins_expected[i]};
    end
    `uvm_info("COV", $sformatf("functional coverage (TB counters): %0d / %0d bins hit (%0.1f %%)%s",
              n_hit, bins_expected.size(), 100.0 * n_hit / bins_expected.size(),
              holes == "" ? "" : {", holes:", holes}), UVM_LOW)
  endfunction

endclass
