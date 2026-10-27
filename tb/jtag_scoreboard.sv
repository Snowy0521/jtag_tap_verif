// ============================================================================
// jtag_scoreboard.sv -- checks the DUT against the reference model, using the
// two monitors only:
//   - every TDO bit of every scan                         (jtag_monitor)
//   - the DFT outputs at every rising edge, MBIST timing   (dft_monitor)
// Both monitors stamp their messages with the same TCK edge count, so the
// checks reason in cycles, not in arrival order (both fire on the same edge).
// ============================================================================
`uvm_analysis_imp_decl(_jtag)
`uvm_analysis_imp_decl(_dft)

class jtag_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(jtag_scoreboard)

  uvm_analysis_imp_jtag #(jtag_scan_txn, jtag_scoreboard) jtag_imp;
  uvm_analysis_imp_dft  #(dft_txn,       jtag_scoreboard) dft_imp;
  jtag_ref_model model;
  int unsigned   mbist_cycles = 16;

  // Predicted DFT outputs, from the cycle at which each prediction takes effect
  typedef struct {int unsigned cycle; bit test_mode, scan_en, mbist_start, trst;} pred_t;
  pred_t       preds[$];
  dft_txn      samples[int unsigned];   // by cycle
  dft_txn      pending;                 // checked when the next sample arrives
  bit          synced;                  // a reset has been seen
  int unsigned sync_cycle;

  // MBIST expectation, derived from the samples themselves
  int unsigned ms_run;                  // consecutive earlier samples with mbist_start = 1
  bit          done_exp_prev, pass_latched;

  int unsigned n_scans, n_bits, n_unknown, n_errors, n_dft_checked;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    jtag_imp = new("jtag_imp", this);
    dft_imp  = new("dft_imp", this);
    model    = jtag_ref_model::type_id::create("model");
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db #(int unsigned)::get(this, "", "mbist_cycles", mbist_cycles));
  endfunction

  function void error(string msg);
    n_errors++;
    `uvm_error("SB", msg)
  endfunction

  // ---------------------------------------------------------------- JTAG side
  function void write_jtag(jtag_scan_txn t);
    bit              exp[$], exp_known[$];
    bit   [IR_W-1:0] instr;               // instruction during this scan
    if (t.scan == jtag_scan_txn::RESET) begin
      model.reset();
      push_pred(t.cycle, t.trst);
      if (!synced) begin
        synced     = 1'b1;
        sync_cycle = t.cycle;
      end
      return;
    end
    instr = model.instr;
    // MBIST status at the capture edge
    model.st_known = samples.exists(t.cap_cycle);
    if (model.st_known) begin
      model.st_done = samples[t.cap_cycle].mbist_done;
      model.st_pass = samples[t.cap_cycle].mbist_pass;
    end
    model.predict(t, exp, exp_known);
    foreach (exp[i]) begin
      if (!exp_known[i]) begin
        n_unknown++;
      end else if (t.tdo_q[i] !== exp[i]) begin
        error($sformatf("%s scan (instr 0x%0h), TDO bit %0d: got %b, expected %b -- %s",
              t.scan.name(), instr, i, t.tdo_q[i], exp[i], t.convert2string()));
      end else begin
        n_bits++;
      end
    end
    n_scans++;
    if (t.scan == jtag_scan_txn::DR && instr == OP_DFT_CTRL && !t.aborted)
      push_pred(t.cycle, 1'b0);
    prune_samples(t.cap_cycle);
  endfunction

  // Scans don't overlap, so no later scan captures before this one did: older
  // samples are no longer needed (the pending DFT check uses newer ones)
  function void prune_samples(int unsigned oldest);
    int unsigned c;
    while (samples.first(c) && c < oldest) samples.delete(c);
  endfunction

  function void push_pred(int unsigned cycle, bit trst);
    pred_t p;
    // With the MBIST status supplied, the predicted outputs are always known;
    // an unknown here must not turn into a silent wrong prediction
    if (!model.test_mode_k || !model.scan_en_k || !model.mbist_start_k)
      error($sformatf("predicted DFT outputs not known at cycle %0d (known bits %b%b%b)", cycle,
            model.test_mode_k, model.scan_en_k, model.mbist_start_k));
    p.cycle       = cycle;
    p.test_mode   = model.test_mode;
    p.scan_en     = model.scan_en;
    p.mbist_start = model.mbist_start;
    p.trst        = trst;
    preds.push_back(p);
  endfunction

  // ---------------------------------------------------------------- DFT side
  // Sample k is checked when sample k+1 arrives: by then every JTAG message
  // stamped k or earlier has arrived (they were published at earlier edges).
  function void write_dft(dft_txn t);
    samples[t.cycle] = t;
    if (pending != null) check_sample(pending);
    pending = t;
  endfunction

  function void check_sample(dft_txn s);
    pred_t p;
    bit    found, done_exp, pass_exp;
    if (!synced || s.cycle < sync_cycle) return;

    // Latest prediction in effect at this cycle; a trst_n reset at this cycle
    // also clears the MBIST stub asynchronously
    foreach (preds[i]) begin
      if (preds[i].cycle > s.cycle) break;
      p = preds[i];
      found = 1'b1;
      if (preds[i].cycle == s.cycle && preds[i].trst) begin
        ms_run        = 0;
        done_exp_prev = 1'b0;
        pass_latched  = 1'b0;
      end
    end
    while (preds.size() > 1 && preds[1].cycle <= s.cycle) void'(preds.pop_front());

    // R14, R15: DFT outputs as predicted; R16: safety
    if (found && {s.test_mode, s.scan_en, s.mbist_start} !== {p.test_mode, p.scan_en, p.mbist_start})
      error($sformatf("DFT outputs at cycle %0d: got test_mode/scan_en/mbist_start = %b%b%b, expected %b%b%b",
            s.cycle, s.test_mode, s.scan_en, s.mbist_start, p.test_mode, p.scan_en, p.mbist_start));
    if (s.scan_en && !s.test_mode)
      error($sformatf("scan_en without test_mode at cycle %0d", s.cycle));

    // R19-R21: done exactly mbist_cycles samples after mbist_start rose;
    // pass = !mbist_fail_i at the edge that set done; both clear after start drops
    done_exp = (ms_run >= mbist_cycles);
    if (done_exp && !done_exp_prev)
      pass_latched = samples.exists(s.cycle - 1) ? !samples[s.cycle - 1].mbist_fail_i : 1'b0;
    pass_exp = done_exp && pass_latched;
    if (s.mbist_done !== done_exp || s.mbist_pass !== pass_exp)
      error($sformatf("MBIST at cycle %0d: got done/pass = %b%b, expected %b%b (mbist_start high for %0d earlier samples)",
            s.cycle, s.mbist_done, s.mbist_pass, done_exp, pass_exp, ms_run));
    ms_run        = s.mbist_start ? ((ms_run < mbist_cycles) ? ms_run + 1 : ms_run) : 0;
    done_exp_prev = done_exp;
    n_dft_checked++;
  endfunction

  function void check_phase(uvm_phase phase);
    if (pending != null) check_sample(pending);
    if (n_scans == 0)       error("no scan was checked");
    if (n_dft_checked == 0) error("no DFT sample was checked");
    // Every bit is predictable now that the DFT monitor supplies the MBIST status
    if (n_unknown != 0)     error($sformatf("%0d TDO bits could not be predicted", n_unknown));
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("%0d scans, %0d TDO bits matched, %0d not predictable, %0d DFT samples checked, %0d errors",
              n_scans, n_bits, n_unknown, n_dft_checked, n_errors), UVM_LOW)
  endfunction

endclass
