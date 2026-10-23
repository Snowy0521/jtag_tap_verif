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

// rst_seen: trst_n has been asserted at least once. Before that, in a 4-state
// simulator, the DUT state is X, so nothing is checked yet. In formal it is the
// constant 1: the tool's reset init sequence plays that role, and the disable
// condition stays exactly the one that was proven.
logic rst_seen;
`ifdef QUESTA_FORMAL
assign rst_seen = 1'b1;
`else
// Explicitly 0 at start: "not yet reset" must not be carried by X, which a
// 2-state simulator turns into a random 0 / 1 (plain always + initial, since
// an always_ff variable may not be written by another process)
initial rst_seen = 1'b0;
always @(posedge tck or negedge trst_n) begin
  if (!trst_n) rst_seen <= 1'b1;
end
// The checkers must not stay switched off for a whole simulation
final begin
  if (rst_seen !== 1'b1)
    $error("%m: trst_n was never asserted, so the checkers checked nothing");
end
`endif

// Every concurrent property: sampled on the rising edge, off during reset.
// X-safe: an unknown trst_n / trst_seen / rst_seen keeps the properties off (an
// X disable condition would not disable them, and an X expression fails).
default clocking cb @(posedge tck); endclocking
default disable iff (trst_n !== 1'b1 || trst_seen !== 1'b0 || rst_seen !== 1'b1);

// ASSERT_TRST(name, cond): cond must hold whenever trst_n is low (async reset).
// Only while trst_n is really 0: before the first reset it is X in simulation.
// Not under disable iff: a deferred immediate assertion, checked whenever its
// inputs change, so it also sees resets between clock edges and with TCK stopped.
// In Verilator, `assert final` acts like a plain immediate assertion and fires
// before the reset flops update, so the local simulation checks 1 ps later.
`ifndef JTAG_ASSERT_TRST
`define JTAG_ASSERT_TRST
`ifdef VERILATOR
`define ASSERT_TRST(name, cond) \
  always @(trst_n or (cond)) begin #1ps; name: assert ((trst_n !== 1'b0) || (cond)); end
`else
`define ASSERT_TRST(name, cond) \
  always_comb begin name: assert final ((trst_n !== 1'b0) || (cond)); end
`endif
`endif
