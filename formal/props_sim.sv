// ============================================================================
// props_sim.sv -- runs the formal harness in simulation with random inputs
// (Verilator --assert). Not a proof: a quick local check that the properties
// compile, hold on the RTL and fire on a bug, before the Questa run.
// ============================================================================
`timescale 1ns/1ps

module props_sim;

  localparam int CYCLES = 200000;

  logic tck = 1'b0;
  int   hold0 = 0;
  logic tms, tdi, trst_n, mbist_fail_i;
  logic tdo, tdo_en, test_mode, scan_en, mbist_start, mbist_done, mbist_pass;

  formal_top u_top (.*);

  always #5 tck = ~tck;

  // Behaviour signature: a hash of every DUT output and internal register,
  // taken 1 ns after each TCK edge. The mutation flow compares it with the
  // clean design's to tell a changed mutant from an equivalent one (run
  // without --assert, so a failing property cannot stop the run early).
  // 2-state: on a 4-state simulator (QuestaSim) one X would otherwise turn
  // the whole hash to X for good; X and Z count as 0.
  bit [63:0] signature = 64'h0;
  always @(tck) begin
    #1;
    signature = {signature[62:0], signature[63]} ^ 64'({
      u_top.dut.state, u_top.dut.ir, u_top.dut.ir_sr,
      u_top.dut.u_dr.bypass_sr, u_top.dut.u_dr.idcode_sr, u_top.dut.u_dr.dft_sr,
      u_top.dut.u_mbist.cnt, tdo, tdo_en, test_mode, scan_en, mbist_start, mbist_done, mbist_pass});
  end

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
      // TMS biased towards 0, plus occasional runs of TMS = 0 up to 80 cycles
      // so that full-length scans (32-bit IDCODE and beyond) happen too.
      if (hold0 == 0 && $urandom_range(49) == 0) hold0 = $urandom_range(80, 1);
      if (hold0 != 0) begin
        tms   = 1'b0;
        hold0 = hold0 - 1;
      end else begin
        tms = ($urandom_range(99) < 35);
      end
      tdi          = 1'($urandom);
      mbist_fail_i = ($urandom_range(9) == 0);
      // Rare full-cycle trst_n resets
      trst_n       = ($urandom_range(999) != 0);
      // Short trst_n pulses that start and end between two rising edges: one in
      // the low phase (1-3 ns after this falling edge), one in the high phase
      // (1-3 ns after the next rising edge, which comes 5 ns from now).
      if (trst_n && $urandom_range(299) == 0)
        fork begin #1 trst_n = 1'b0; #2 trst_n = 1'b1; end join_none
      if (trst_n && $urandom_range(299) == 0)
        fork begin #6 trst_n = 1'b0; #2 trst_n = 1'b1; end join_none
    end
    $display("PROPS SIM SIGNATURE: %016h", signature);
    $display("PROPS SIM DONE: %0d cycles", CYCLES);
    $finish;
  end

endmodule
