// ============================================================================
// jtag_ref_model.sv -- predicts TDO for every scan, from the spec only.
// Fed by the scoreboard with what the monitor observed (never by the driver):
// it tracks the active instruction and the DFT outputs, replays each scan
// through its own model of the selected shift register, and applies Update.
//
// "Not predictable" is an explicit known bit next to every value, never a
// 4-state X: a 2-state simulator (Verilator) turns X in class variables into
// 0, so X would silently become a wrong prediction.
// ============================================================================
class jtag_ref_model extends uvm_object;

  `uvm_object_utils(jtag_ref_model)

  // Values from the spec, not from jtag_pkg
  localparam logic [3:0]  SPEC_IR_CAPTURE = 4'b0001;        // R7
  localparam logic [31:0] SPEC_IDCODE     = 32'h1114_9FFF;  // R13

  bit [IR_W-1:0] instr;                                     // active instruction
  bit            test_mode,   scan_en,   mbist_start;       // DFT outputs ...
  bit            test_mode_k, scan_en_k, mbist_start_k;     // ... and whether each is known

  function new(string name = "jtag_ref_model");
    super.new(name);
    reset();
  endfunction

  // R9, R14: Test-Logic-Reset
  function void reset();
    instr = OP_IDCODE;
    {test_mode,   scan_en,   mbist_start}   = 3'b000;
    {test_mode_k, scan_en_k, mbist_start_k} = 3'b111;
  endfunction

  // MBIST status at the capture edge, supplied by the scoreboard from the DFT
  // monitor's sample (the scan-level model cannot know the cycle timing)
  bit st_done, st_pass, st_known;

  // Independent decode (R10): length, captured value and which bits are known
  function void capture_dr(output int len, output bit [31:0] cap, output bit [31:0] known);
    case (instr)
      OP_IDCODE: begin
        len   = 32;
        cap   = SPEC_IDCODE;                                       // R13
        known = '1;
      end
      OP_DFT_CTRL: begin
        len = 8;
        // R17. Bits 4:3: the MBIST status at the capture edge
        cap   = 32'({3'b000, st_pass,  st_done,  mbist_start,   scan_en,   test_mode});
        known = 32'({3'b111, st_known, st_known, mbist_start_k, scan_en_k, test_mode_k});
      end
      default: begin
        len   = 1;
        cap   = '0;                                                // R12: BYPASS
        known = '1;
      end
    endcase
  endfunction

  // Expected TDO bits (and which are known) for scan t, then apply its Update
  function void predict(jtag_scan_txn t, ref bit exp[$], ref bit exp_known[$]);
    bit          sr[$], sr_k[$];          // sr[0] leaves next on TDO
    int          len;
    bit [31:0]   cap, known;

    if (t.scan == jtag_scan_txn::IR) begin
      len   = IR_W;
      cap   = 32'(SPEC_IR_CAPTURE);
      known = '1;
    end else begin
      capture_dr(len, cap, known);
    end
    for (int i = 0; i < len; i++) begin
      sr.push_back(cap[i]);
      sr_k.push_back(known[i]);
    end

    // R8, R11: shift right, LSB out first, TDI (known) into the top
    exp.delete();
    exp_known.delete();
    foreach (t.tdi_q[i]) begin
      exp.push_back(sr.pop_front());
      exp_known.push_back(sr_k.pop_front());
      sr.push_back(t.tdi_q[i]);
      sr_k.push_back(1'b1);
    end

    if (t.aborted) return;                // trst_n: a RESET follows
    if (t.scan == jtag_scan_txn::IR) begin
      for (int i = 0; i < IR_W; i++) instr[i] = sr[i];              // R9 (IR bits are always known)
    end else if (instr == OP_DFT_CTRL) begin
      // R15. After a scan shorter than 3 bits, unknown captured status bits can
      // end up in sr[2:0]; scan_en is still known if either input is a known 0.
      test_mode     = sr[0];
      test_mode_k   = sr_k[0];
      scan_en       = sr[1] & sr[0];
      scan_en_k     = (sr_k[0] && sr_k[1]) || (sr_k[0] && !sr[0]) || (sr_k[1] && !sr[1]);
      mbist_start   = sr[2];
      mbist_start_k = sr_k[2];
    end
  endfunction

endclass
