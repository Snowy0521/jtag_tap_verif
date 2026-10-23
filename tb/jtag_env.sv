// ============================================================================
// jtag_env.sv -- JTAG agent, DFT monitor, scoreboard (with the reference model).
// ============================================================================
class jtag_env extends uvm_env;

  `uvm_component_utils(jtag_env)

  jtag_agent      agent;
  dft_monitor     dft_mon;
  jtag_scoreboard sb;
  jtag_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent   = jtag_agent::type_id::create("agent", this);
    dft_mon = dft_monitor::type_id::create("dft_mon", this);
    sb      = jtag_scoreboard::type_id::create("sb", this);
    cov     = jtag_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.mon.ap.connect(sb.jtag_imp);
    dft_mon.ap.connect(sb.dft_imp);
    agent.mon.ap.connect(cov.jtag_imp);
    agent.mon.edge_ap.connect(cov.edge_imp);
    dft_mon.ap.connect(cov.dft_imp);
  endfunction

  // Every scan the driver drove must have been observed (completed or aborted).
  // A raw TMS path followed by a reset can add at most one scan of its own (e.g.
  // five TMS = 1 from Capture-xR passes Update-xR), so the observed count may
  // exceed the driven count by up to the number of paths, never fall below it.
  // Only counts cross over from the driver; the data checked comes from the monitors.
  function void check_phase(uvm_phase phase);
    int unsigned driven, observed;
    if (agent.get_is_active() != UVM_ACTIVE) return;
    driven   = agent.drv.n_scans;
    observed = agent.mon.n_scans + agent.mon.n_aborted;
    if (observed < driven || observed > driven + agent.drv.n_tms_paths)
      `uvm_error("ENV", $sformatf("%0d scans driven (+ up to %0d from raw TMS paths), %0d observed (%0d completed + %0d aborted)",
                 driven, agent.drv.n_tms_paths, observed, agent.mon.n_scans, agent.mon.n_aborted))
  endfunction

endclass
