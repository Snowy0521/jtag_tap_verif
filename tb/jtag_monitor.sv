// ============================================================================
// jtag_monitor.sv -- rebuilds the TAP state from the pins with its own copy
// of the state table (not the driver's, not the RTL's), collects TDI / TDO in
// Shift-xR and publishes one jtag_scan_txn per scan.
// Samples just before the rising edge of TCK (clocking block, #1step), like
// the DUT and a real JTAG tester. Also checks that tdo / tdo_en never change
// while TCK is high: a sampled check alone cannot see when a pin moved.
// ============================================================================
class jtag_monitor extends uvm_monitor;

  `uvm_component_utils(jtag_monitor)

  virtual jtag_if vif;
  uvm_analysis_port #(jtag_scan_txn) ap;

  // Before the first reset the TAP state is unknown (X in a 4-state simulator),
  // so the monitor only checks and reports once it is in sync: after trst_n, or
  // after five rising edges with TMS = 1 (R2: Test-Logic-Reset from any state).
  bit           synced;
  int unsigned  tms_ones;
  int unsigned  cycle;                            // rising edges of TCK so far
  tap_state_e   state = TEST_LOGIC_RESET;
  jtag_scan_txn txn;                              // scan in progress, null between scans
  int unsigned  n_scans, n_aborted;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual jtag_if)::get(this, "", "jtag_vif", vif))
      `uvm_fatal("NOVIF", "jtag_vif not set")
  endfunction

  // Spec state table, written per state (the formal model groups by TMS)
  function tap_state_e next_state(tap_state_e s, bit tms);
    case (s)
      TEST_LOGIC_RESET: return tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
      RUN_TEST_IDLE:    return tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
      SELECT_DR_SCAN:   return tms ? SELECT_IR_SCAN   : CAPTURE_DR;
      CAPTURE_DR:       return tms ? EXIT1_DR         : SHIFT_DR;
      SHIFT_DR:         return tms ? EXIT1_DR         : SHIFT_DR;
      EXIT1_DR:         return tms ? UPDATE_DR        : PAUSE_DR;
      PAUSE_DR:         return tms ? EXIT2_DR         : PAUSE_DR;
      EXIT2_DR:         return tms ? UPDATE_DR        : SHIFT_DR;
      UPDATE_DR:        return tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;
      SELECT_IR_SCAN:   return tms ? TEST_LOGIC_RESET : CAPTURE_IR;
      CAPTURE_IR:       return tms ? EXIT1_IR         : SHIFT_IR;
      SHIFT_IR:         return tms ? EXIT1_IR         : SHIFT_IR;
      EXIT1_IR:         return tms ? UPDATE_IR        : PAUSE_IR;
      PAUSE_IR:         return tms ? EXIT2_IR         : PAUSE_IR;
      EXIT2_IR:         return tms ? UPDATE_IR        : SHIFT_IR;
      default:          return tms ? SELECT_DR_SCAN   : RUN_TEST_IDLE;   // UPDATE_IR
    endcase
  endfunction

  task run_phase(uvm_phase phase);
    fork
      // trst_n is asynchronous: handled the moment it falls, between edges too
      forever begin
        @(negedge vif.trst_n);
        abort_scan();
        publish_reset(1'b1);
        state  = TEST_LOGIC_RESET;                // R3
        synced = 1'b1;
      end
      forever begin
        @(vif.mon_cb);
        cycle++;
        if (vif.mon_cb.trst_n !== 1'b1) begin
          state = TEST_LOGIC_RESET;               // held in reset
        end else if (!synced) begin
          tms_ones = (vif.mon_cb.tms === 1'b1) ? tms_ones + 1 : 0;
          if (tms_ones == 5) begin
            state  = TEST_LOGIC_RESET;
            synced = 1'b1;
            publish_reset(1'b0);
          end
        end else begin
          sample();
        end
      end
      // R5, R6: tdo / tdo_en are falling-edge outputs; R22: nothing changes
      // while TCK is stopped (trst_n clears excepted)
      forever begin
        @(vif.tdo or vif.tdo_en);
        if ((vif.tck === 1'b1 || vif.tck_en === 1'b0) && vif.trst_n === 1'b1)
          `uvm_error("MON_EDGE", $sformatf("tdo/tdo_en changed while TCK is %s: tdo=%b tdo_en=%b",
                     vif.tck_en === 1'b0 ? "stopped" : "high", vif.tdo, vif.tdo_en))
      end
    join
  endtask

  // One rising edge: `state` is the state the TAP was in before this edge
  function void sample();
    bit shifting = (state == SHIFT_IR) || (state == SHIFT_DR);

    if (state == CAPTURE_IR || state == CAPTURE_DR) begin
      txn = jtag_scan_txn::type_id::create("txn");
      txn.scan      = (state == CAPTURE_IR) ? jtag_scan_txn::IR : jtag_scan_txn::DR;
      txn.cap_cycle = cycle;
    end
    if (txn != null) txn.path.push_back(state);

    // Protocol: tdo_en exactly in Shift-xR (R5)
    if (vif.mon_cb.tdo_en !== shifting)
      `uvm_error("MON_TDOEN", $sformatf("tdo_en=%b in %s", vif.mon_cb.tdo_en, state.name()))

    if (shifting && txn != null) begin
      txn.tdi_q.push_back(vif.mon_cb.tdi);
      txn.tdo_q.push_back(vif.mon_cb.tdo);
    end

    if ((state == UPDATE_IR || state == UPDATE_DR) && txn != null) begin
      txn.cycle = cycle;                          // the update (falling edge) shows in this edge's sample
      `uvm_info("MON", txn.convert2string(), UVM_MEDIUM)
      ap.write(txn);
      n_scans++;
      txn = null;
    end

    begin
      tap_state_e prev = state;
      state = next_state(state, vif.mon_cb.tms);
      if (state == TEST_LOGIC_RESET && prev != TEST_LOGIC_RESET) publish_reset(1'b0);
    end
  endfunction

  // The TAP entered Test-Logic-Reset: the instruction and DFT outputs reset.
  // Via TMS they clear at the next falling edge, via trst_n at once; either way
  // the next rising edge's sample is the first to show it.
  function void publish_reset(bit by_trst);
    jtag_scan_txn r = jtag_scan_txn::type_id::create("reset");
    r.scan  = jtag_scan_txn::RESET;
    r.trst  = by_trst;
    r.cycle = cycle + 1;
    ap.write(r);
  endfunction

  // trst_n during a scan: publish the partial scan as aborted
  function void abort_scan();
    if (txn == null) return;
    txn.aborted = 1'b1;
    `uvm_info("MON", txn.convert2string(), UVM_MEDIUM)
    ap.write(txn);
    n_aborted++;
    txn = null;
  endfunction

  // Every scan must end in Update-xR or be aborted by trst_n
  function void check_phase(uvm_phase phase);
    if (txn != null)
      `uvm_error("MON_OPEN", $sformatf("scan started but never completed: %s", txn.convert2string()))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("MON", $sformatf("%0d scans observed, %0d aborted", n_scans, n_aborted), UVM_LOW)
    if (!synced) `uvm_error("MON_SYNC", "never in sync with the TAP: no trst_n and no five TMS = 1")
  endfunction

endclass
