// ============================================================================
// jtag_tb_pkg.sv -- all UVM classes of the testbench.
// Uses jtag_pkg for names and encodings only (tap_state_e, opcodes, IR_W);
// expected behaviour is modelled independently of the RTL.
// ============================================================================
package jtag_tb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import jtag_pkg::*;

  localparam int TCK_PERIOD_NS = 10;

  `include "jtag_seq_item.sv"
  `include "jtag_scan_txn.sv"
  `include "dft_txn.sv"
  `include "jtag_driver.sv"
  `include "jtag_monitor.sv"
  `include "jtag_agent.sv"
  `include "dft_monitor.sv"
  `include "jtag_ref_model.sv"
  `include "jtag_scoreboard.sv"
  `include "jtag_env.sv"
  `include "jtag_base_seq.sv"
  `include "jtag_base_test.sv"
  `include "jtag_idcode_test.sv"
  `include "jtag_bypass_test.sv"
  `include "jtag_unused_opcode_test.sv"
  `include "jtag_reset_test.sv"
  `include "jtag_dft_test.sv"
  `include "jtag_pause_test.sv"
  `include "jtag_random_test.sv"

endpackage
