// ============================================================================
// jtag_driver.sv -- turns items into TMS / TDI / trst_n / tck_en activity.
// Drives on the falling edge of TCK, so values are stable at the rising edge
// where the DUT samples them. Every item starts and ends in Run-Test/Idle
// (after a reset item, the driver moves to Run-Test/Idle itself). The one
// exception is TMS_PATH, which leaves the TAP anywhere: it must be followed
// by a reset.
// ============================================================================
class jtag_driver extends uvm_driver #(jtag_seq_item);

  `uvm_component_utils(jtag_driver)

  virtual jtag_if vif;
  int unsigned    n_scans;     // IR / DR scans driven: the env compares this with the monitor
  int unsigned    n_tms_paths; // raw TMS paths: each may add one scan the driver did not plan
  bit             at_rti;      // the TAP is known to be in Run-Test/Idle

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual jtag_if)::get(this, "", "jtag_vif", vif))
      `uvm_fatal("NOVIF", "jtag_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    vif.tms    <= 1'b1;
    vif.tdi    <= 1'b0;
    vif.trst_n <= 1'b1;
    vif.tck_en <= 1'b1;
    forever begin
      seq_item_port.get_next_item(req);
      `uvm_info("DRV", req.convert2string(), UVM_HIGH)
      if (!at_rti && !(req.kind inside {jtag_seq_item::RESET_TRST, jtag_seq_item::RESET_TMS}))
        `uvm_fatal("DRV", $sformatf("%s needs Run-Test/Idle, but the TAP state is unknown (send a reset first)",
                   req.kind.name()))
      case (req.kind)
        jtag_seq_item::RESET_TRST: reset_trst(req.trst_short);
        jtag_seq_item::TMS_PATH:   tms_path(req.tms_q);
        jtag_seq_item::RESET_TMS:  reset_tms();
        jtag_seq_item::IDLE:       repeat (req.idle_cycles) tick(1'b0);
        jtag_seq_item::TCK_STOP:   tck_stop(req.idle_cycles);
        jtag_seq_item::IR_SCAN:    begin scan(1'b1, req); n_scans++; end
        jtag_seq_item::DR_SCAN:    begin scan(1'b0, req); n_scans++; end
      endcase
      seq_item_port.item_done();
    end
  endtask

  // One TCK cycle: set TMS / TDI at the falling edge; the DUT uses them at the
  // next rising edge.
  task tick(bit tms, bit tdi = 1'b0);
    @(negedge vif.tck);
    vif.tms <= tms;
    vif.tdi <= tdi;
  endtask

  task reset_trst(bit short_pulse);
    @(negedge vif.tck);
    if (short_pulse) begin
      // Starts and ends inside the low phase: no rising edge sees trst_n = 0.
      // TMS = 0, so the next rising edge leaves Test-Logic-Reset at once and no
      // falling edge happens in it: only the asynchronous trst_n reset (R3, R9 c,
      // R14 c) can have reset the instruction and the DFT outputs.
      vif.tms <= 1'b0;
      #(TCK_PERIOD_NS * 0.1 * 1ns) vif.trst_n <= 1'b0;
      #(TCK_PERIOD_NS * 0.2 * 1ns) vif.trst_n <= 1'b1;
    end else begin
      vif.tms    <= 1'b1;
      vif.trst_n <= 1'b0;
      repeat (2) @(negedge vif.tck);
      vif.trst_n <= 1'b1;
    end
    tick(1'b0);                                   // Test-Logic-Reset -> Run-Test/Idle
    at_rti = 1'b1;
  endtask

  task reset_tms();
    repeat (5) tick(1'b1);                        // R2: five TMS = 1 from any state
    tick(1'b0);                                   // Test-Logic-Reset -> Run-Test/Idle
    at_rti = 1'b1;
  endtask

  // Raw TMS steps from Run-Test/Idle (TDI = 0); the end state is up to the caller
  task tms_path(const ref bit tms_q[$]);
    foreach (tms_q[i]) tick(tms_q[i]);
    at_rti = 1'b0;
    n_tms_paths++;
  endtask

  // Stop TCK while it is low (glitch-free), then restart it. The gate drops
  // 1 ns after the falling edge, so "stopped" never shares a time step with the
  // DUT's falling-edge updates (the monitors flag any change while stopped).
  task tck_stop(int unsigned cycles);
    @(negedge vif.tck);
    #(1ns);
    vif.tck_en <= 1'b0;
    #(cycles * TCK_PERIOD_NS * 1ns);
    vif.tck_en <= 1'b1;
  endtask

  // IR or DR scan from Run-Test/Idle, back to Run-Test/Idle
  task scan(bit is_ir, jtag_seq_item it);
    int n = it.tdi_q.size();
    // Directed items skip randomize(), so check here too: a pause that cannot
    // happen would silently test nothing
    if (it.use_pause && !(n >= 2 && it.pause_at < n - 1))
      `uvm_fatal("DRV", $sformatf("pause_at=%0d does not fit a %0d-bit scan", it.pause_at, n))
    tick(1'b1);                                   // -> Select-DR-Scan
    if (is_ir) tick(1'b1);                        // -> Select-IR-Scan
    tick(1'b0);                                   // -> Capture-xR
    if (n == 0) begin
      tick(1'b1);                                 // Capture -> Exit1 (no shift)
    end else begin
      tick(1'b0);                                 // -> Shift-xR
      for (int i = 0; i < n; i++) begin
        if (i == n - 1) begin
          tick(1'b1, it.tdi_q[i]);                // last bit, -> Exit1
        end else if (it.use_pause && i == it.pause_at) begin
          tick(1'b1, it.tdi_q[i]);                // -> Exit1
          tick(1'b0);                             // -> Pause
          repeat (it.pause_cycles) tick(1'b0);    // stay in Pause
          tick(1'b1);                             // -> Exit2
          tick(1'b0);                             // -> Shift
        end else begin
          tick(1'b0, it.tdi_q[i]);                // stay in Shift
        end
      end
    end
    tick(1'b1);                                   // Exit1 -> Update
    tick(1'b0);                                   // Update -> Run-Test/Idle
  endtask

endclass
