// ============================================================================
// jtag_checker_defaults.svh -- clock and reset defaults for every checker.
// Include at the top of each checker module body; the module must have tck
// and trst_n ports.
// ============================================================================

// trst_seen: 1 from any trst_n assertion until the next rising edge, so a reset
// pulse that starts and ends between two rising edges still disables the
// property attempts it interrupts (no edge ever samples trst_n = 0 for them).
logic trst_seen;
always_ff @(posedge tck or negedge trst_n) begin
  if (!trst_n) trst_seen <= 1'b1;
  else         trst_seen <= 1'b0;
end

// Every concurrent property: sampled on the rising edge, off during reset
default clocking cb @(posedge tck); endclocking
default disable iff (!trst_n || trst_seen);

// ASSERT_TRST(name, cond): cond must hold whenever trst_n is low (async reset).
// Not under disable iff: a deferred immediate assertion, checked whenever its
// inputs change, so it also sees resets between clock edges and with TCK stopped.
// In Verilator, `assert final` acts like a plain immediate assertion and fires
// before the reset flops update, so the local simulation checks 1 ps later.
`ifndef JTAG_ASSERT_TRST
`define JTAG_ASSERT_TRST
`ifdef VERILATOR
`define ASSERT_TRST(name, cond) \
  always @(trst_n or (cond)) begin #1ps; name: assert (trst_n || (cond)); end
`else
`define ASSERT_TRST(name, cond) \
  always_comb begin name: assert final (trst_n || (cond)); end
`endif
`endif
