// ============================================================================
// tb_smoke.sv -- directed smoke test for jtag_tap_top (no UVM, iverilog-compatible).
// Not the verification: a quick sanity run before formal / UVM.
// TMS/TDI are driven on the falling edge; TDO is sampled at the rising edge,
// as a JTAG tester does. Rule IDs refer to docs/design_spec.md.
// ============================================================================
`timescale 1ns/1ps

module tb_smoke;
  import jtag_pkg::*;

  localparam int MBIST_CYCLES = 4;

  logic tck = 1'b0;
  logic tms = 1'b1;
  logic tdi = 1'b0;
  logic trst_n = 1'b0;
  logic mbist_fail_i = 1'b0;
  logic tdo, tdo_en;
  logic test_mode, scan_en, mbist_start, mbist_done, mbist_pass;

  int errors = 0;

  jtag_tap_top #(.MBIST_CYCLES(MBIST_CYCLES)) dut (.*);

  always #5 tck = ~tck;

  // ---------------------------------------------------------------- helpers
  task automatic check(input string what, input logic [63:0] got, input logic [63:0] exp);
    if (got !== exp) begin
      $display("ERROR %0t: %s: got 0x%0h, expected 0x%0h", $time, what, got, exp);
      errors++;
    end else begin
      $display("ok    %0t: %s = 0x%0h", $time, what, got);
    end
  endtask

  // One TCK cycle: drive on the falling edge, return TDO sampled at the rising edge.
  task automatic tick(input logic tms_v, input logic tdi_v, output logic tdo_s, output logic en_s);
    @(negedge tck);
    tms = tms_v;
    tdi = tdi_v;
    @(posedge tck);
    tdo_s = tdo;
    en_s  = tdo_en;
    #1;                 // let the rising-edge NBAs settle before any check of DUT state
  endtask

  task automatic tms_seq(input int n, input logic tms_v);
    logic d0, d1;
    repeat (n) tick(tms_v, 1'b0, d0, d1);
  endtask

  // Scan len bits from Shift-xR; TMS = 1 on the last bit, then Update -> Run-Test/Idle.
  task automatic shift_bits(input int len, input logic [63:0] din, output logic [63:0] dout);
    logic en, bit_out;
    dout = '0;
    for (int i = 0; i < len; i++) begin
      tick(i == len - 1, din[i], bit_out, en);   // via a temporary: iverilog ignores a bit-select (dout[i]) as a task output argument
      dout[i] = bit_out;
      if (en !== 1'b1) begin
        $display("ERROR %0t: tdo_en low during shift bit %0d", $time, i);
        errors++;
      end
    end
    tms_seq(1, 1'b1);   // Exit1 -> Update
    tms_seq(1, 1'b0);   // Update -> Run-Test/Idle
  endtask

  // From Run-Test/Idle
  task automatic ir_scan(input logic [IR_W-1:0] op, output logic [IR_W-1:0] captured);
    logic [63:0] dout;
    tms_seq(2, 1'b1);   // Select-DR, Select-IR
    tms_seq(2, 1'b0);   // Capture-IR, Shift-IR
    shift_bits(IR_W, 64'(op), dout);
    captured = dout[IR_W-1:0];
  endtask

  task automatic dr_scan(input int len, input logic [63:0] din, output logic [63:0] dout);
    tms_seq(1, 1'b1);   // Select-DR
    tms_seq(2, 1'b0);   // Capture-DR, Shift-DR
    shift_bits(len, din, dout);
  endtask

  task automatic do_trst();
    @(negedge tck);
    trst_n = 1'b0;
    #3;
    check("trst: state", dut.state, TEST_LOGIC_RESET);
    check("trst: ir", dut.ir, OP_IDCODE);
    check("trst: dft outputs", {test_mode, scan_en, mbist_start}, 3'b000);
    check("trst: tdo/tdo_en", {tdo, tdo_en}, 2'b00);
    @(negedge tck);
    trst_n = 1'b1;
    tms_seq(1, 1'b0);   // Test-Logic-Reset -> Run-Test/Idle
  endtask

  // ---------------------------------------------------------------- test
  logic [63:0]     dout;
  logic [IR_W-1:0] ir_cap;

  initial begin
    $dumpfile("build/tb_smoke.vcd");
    $dumpvars(0, tb_smoke);

    // 1. IDCODE after reset, without loading an instruction (R9, R13)
    #12 trst_n = 1'b1;
    tms_seq(1, 1'b0);
    check("state after reset", dut.state, RUN_TEST_IDLE);
    dr_scan(32, 64'h0, dout);
    check("IDCODE after reset", dout[31:0], IDCODE_VAL);

    // 2. IR capture value; BYPASS: first bit 0, then TDI delayed by one (R7, R12)
    ir_scan(OP_BYPASS, ir_cap);
    check("IR capture value", ir_cap, IR_CAPTURE);
    check("active instruction", dut.ir, OP_BYPASS);
    dr_scan(16, 64'hA5C3, dout);
    check("BYPASS stream", dout[15:0], 16'({16'hA5C3, 1'b0}));   // = 16'h4B86

    // 3. Unused opcode behaves like BYPASS (R10)
    ir_scan(4'b0101, ir_cap);
    dr_scan(8, 64'h96, dout);
    check("unused opcode = BYPASS", dout[7:0], 8'({8'h96, 1'b0}));   // = 8'h2C

    // 4. Explicit IDCODE, over-length scan: TDI appears after 32 bits (R13)
    ir_scan(OP_IDCODE, ir_cap);
    dr_scan(40, 64'h5A, dout);
    check("IDCODE explicit", dout[31:0], IDCODE_VAL);
    check("IDCODE over-length: TDI delayed by 32", dout[39:32], 8'h5A);
    dr_scan(32, 64'h0, dout);
    check("IDCODE recaptured", dout[31:0], IDCODE_VAL);

    // 5. DFT_CTRL: scan_en gated at write time (R15, R16)
    ir_scan(OP_DFT_CTRL, ir_cap);
    dr_scan(8, 64'b0000_0010, dout);
    check("DFT read-back after reset", dout[7:0], 8'h00);
    check("scan_en w/o test_mode blocked", {test_mode, scan_en, mbist_start}, 3'b000);
    dr_scan(8, 64'b0000_0011, dout);
    check("test_mode + scan_en", {test_mode, scan_en, mbist_start}, 3'b110);

    // 6. MBIST run, pass (R19-R21); reserved bits written as 1 must read back 0 (R17)
    dr_scan(8, 64'b1110_0101, dout);
    check("read-back test_mode+scan_en", dout[7:0], 8'b0000_0011);
    check("test_mode + mbist_start", {test_mode, scan_en, mbist_start}, 3'b101);
    // R20 edge count: mbist_start rises on the falling edge in Update-DR, so the
    // rising edge leaving Update-DR (end of dr_scan) is edge 1. MBIST_CYCLES-2 more
    // edges = MBIST_CYCLES-1 in total (not done yet); one more = MBIST_CYCLES (done).
    // Needs MBIST_CYCLES >= 2 (with 1, done already rises at edge 1).
    tms_seq(MBIST_CYCLES - 2, 1'b0);
    check("mbist not done after MBIST_CYCLES-1 edges", {mbist_done, mbist_pass}, 2'b00);
    tms_seq(1, 1'b0);
    check("mbist done at the MBIST_CYCLES-th edge", {mbist_done, mbist_pass}, 2'b11);
    dr_scan(8, 64'b0000_0101, dout);
    check("read-back: done, pass, start, test_mode", dout[7:0], 8'b0001_1101);

    // 7. Redundant start does not restart; 0 then 1 restarts with a fail (R21)
    mbist_fail_i = 1'b1;
    dr_scan(8, 64'b0000_0101, dout);
    check("redundant start keeps result", {mbist_done, mbist_pass}, 2'b11);
    dr_scan(8, 64'b0000_0001, dout);
    tms_seq(1, 1'b0);
    check("start dropped clears stub", {mbist_done, mbist_pass}, 2'b00);
    dr_scan(8, 64'b0000_0101, dout);
    tms_seq(MBIST_CYCLES + 1, 1'b0);
    check("mbist fail run", {mbist_done, mbist_pass}, 2'b10);

    // 8. Five TMS = 1 reach Test-Logic-Reset; DFT cleared, instruction = IDCODE (R2, R14, R23)
    tms_seq(5, 1'b1);
    check("TMS reset: state", dut.state, TEST_LOGIC_RESET);
    @(posedge tck);
    check("TMS reset: dft outputs", {test_mode, scan_en, mbist_start}, 3'b000);
    check("TMS reset: ir", dut.ir, OP_IDCODE);
    tms_seq(1, 1'b0);
    dr_scan(32, 64'h0, dout);
    check("IDCODE after TMS reset", dout[31:0], IDCODE_VAL);

    // 9. trst_n in the middle of a DR scan (R3, R18)
    ir_scan(OP_DFT_CTRL, ir_cap);
    dr_scan(8, 64'b0000_0011, dout);
    tms_seq(1, 1'b1);
    tms_seq(2, 1'b0);
    tms_seq(3, 1'b0);   // in Shift-DR
    do_trst();
    dr_scan(32, 64'h0, dout);
    check("IDCODE after mid-scan trst_n", dout[31:0], IDCODE_VAL);

    if (errors == 0) $display("SMOKE TEST PASSED");
    else             $display("SMOKE TEST FAILED: %0d error(s)", errors);
    $finish;
  end

  initial begin
    #200000 $display("SMOKE TEST FAILED: timeout");
    $finish;
  end

endmodule
