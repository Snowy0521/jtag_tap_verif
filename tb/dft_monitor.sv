// ============================================================================
// dft_monitor.sv -- passive monitor on the DFT pins. Publishes one dft_txn per
// rising edge of TCK, and checks that the DFT update registers never change
// while TCK is high (they are falling-edge registers; trst_n clears excepted).
// ============================================================================
class dft_monitor extends uvm_monitor;

  `uvm_component_utils(dft_monitor)

  virtual dft_if  vif;
  virtual jtag_if jvif;                          // TCK and trst_n only
  uvm_analysis_port #(dft_txn) ap;

  int unsigned cycle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual dft_if)::get(this, "", "dft_vif", vif))
      `uvm_fatal("NOVIF", "dft_vif not set")
    if (!uvm_config_db #(virtual jtag_if)::get(this, "", "jtag_vif", jvif))
      `uvm_fatal("NOVIF", "jtag_vif not set")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      forever begin
        @(vif.mon_cb);
        cycle++;
        sample();
      end
      // test_mode / scan_en / mbist_start are falling-edge registers; R22:
      // nothing changes while TCK is stopped (trst_n clears excepted)
      forever begin
        @(vif.test_mode or vif.scan_en or vif.mbist_start);
        if ((jvif.tck === 1'b1 || jvif.tck_en === 1'b0) && jvif.trst_n === 1'b1)
          `uvm_error("DFT_EDGE", $sformatf("DFT output changed while TCK is %s: %s",
                     jvif.tck_en === 1'b0 ? "stopped" : "high", pins()))
      end
      // The MBIST status changes on rising edges, so only "stopped" is wrong
      forever begin
        @(vif.mbist_done or vif.mbist_pass);
        if (jvif.tck_en === 1'b0 && jvif.trst_n === 1'b1)
          `uvm_error("DFT_EDGE", $sformatf("MBIST status changed while TCK is stopped: %s", pins()))
      end
    join
  endtask

  function string pins();
    return $sformatf("test_mode=%b scan_en=%b mbist_start=%b done=%b pass=%b",
                     vif.test_mode, vif.scan_en, vif.mbist_start, vif.mbist_done, vif.mbist_pass);
  endfunction

  // Values just before the rising edge (clocking block, #1step)
  function void sample();
    dft_txn t = dft_txn::type_id::create("t");
    t.cycle        = cycle;
    t.test_mode    = vif.mon_cb.test_mode;
    t.scan_en      = vif.mon_cb.scan_en;
    t.mbist_start  = vif.mon_cb.mbist_start;
    t.mbist_done   = vif.mon_cb.mbist_done;
    t.mbist_pass   = vif.mon_cb.mbist_pass;
    t.mbist_fail_i = vif.mon_cb.mbist_fail_i;
    ap.write(t);
  endfunction

endclass
