// ============================================================================
// props_sim.sv -- runs the formal harness in simulation with random inputs
// (Verilator --assert). Not a proof: a quick local check that the properties
// compile, hold on the RTL and fire on a bug, before the Questa run.
// ============================================================================
`timescale 1ns/1ps

module props_sim;

  localparam int CYCLES = 200000;

  logic tck = 1'b0;
  logic tms, tdi, trst_n, mbist_fail_i;
  logic tdo, tdo_en, test_mode, scan_en, mbist_start, mbist_done, mbist_pass;

  formal_top u_top (.*);

  always #5 tck = ~tck;

  initial begin
    tms = 1'b1; tdi = 1'b0; mbist_fail_i = 1'b0;
    // A real falling edge on trst_n: an initial value of 0 at time 0 is not
    // an edge, so the async reset would never run and the flops stay X.
    trst_n = 1'b1;
    #1 trst_n = 1'b0;
    repeat (2) @(negedge tck);
    trst_n = 1'b1;
    for (int i = 0; i < CYCLES; i++) begin
      @(negedge tck);
      // TMS biased towards 0 so long scans happen; rare full-cycle trst_n resets
      tms          = ($urandom_range(99) < 35);
      tdi          = 1'($urandom);
      mbist_fail_i = ($urandom_range(9) == 0);
      trst_n       = ($urandom_range(999) != 0);
      // Short trst_n pulses that start and end between two rising edges: one in
      // the low phase (1-3 ns after this falling edge), one in the high phase
      // (1-3 ns after the next rising edge, which comes 5 ns from now).
      if (trst_n && $urandom_range(299) == 0)
        fork begin #1 trst_n = 1'b0; #2 trst_n = 1'b1; end join_none
      if (trst_n && $urandom_range(299) == 0)
        fork begin #6 trst_n = 1'b0; #2 trst_n = 1'b1; end join_none
    end
    $display("PROPS SIM DONE: %0d cycles", CYCLES);
    $finish;
  end

endmodule
