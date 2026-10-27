// ============================================================================
// jtag_base_test.sv -- builds the environment; tests extend it.
// ============================================================================
class jtag_base_test extends uvm_test;

  `uvm_component_utils(jtag_base_test)

  jtag_env       env;
  virtual dft_if dvif;          // tests drive mbist_fail_i through it

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = jtag_env::type_id::create("env", this);
    if (!uvm_config_db #(virtual dft_if)::get(this, "", "dft_vif", dvif))
      `uvm_fatal("NOVIF", "dft_vif not set")
    uvm_top.set_timeout(10ms, 0);                 // fail fast if a sequence hangs
  endfunction

  // Raises the objection, runs the test's stimulus, and keeps the phase alive
  // for a drain time afterwards: a sequence ends when the driver has driven
  // the last TMS value, but the monitor only sees the scan complete at the
  // following rising edges.
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    phase.get_objection().set_drain_time(this, 10 * TCK_PERIOD_NS * 1ns);
    run_stimulus();
    phase.drop_objection(this);
  endtask

  // Tests override this
  virtual task run_stimulus();
  endtask

endclass
