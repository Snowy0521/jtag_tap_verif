// ============================================================================
// jtag_agent.sv -- sequencer + driver + monitor for the JTAG port.
// ============================================================================
typedef uvm_sequencer #(jtag_seq_item) jtag_sequencer;

class jtag_agent extends uvm_agent;

  `uvm_component_utils(jtag_agent)

  jtag_sequencer sqr;
  jtag_driver    drv;
  jtag_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = jtag_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = jtag_sequencer::type_id::create("sqr", this);
      drv = jtag_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass
