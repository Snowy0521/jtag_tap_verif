// ============================================================================
// jtag_seq_item.sv -- driver stimulus. Only what to drive, never results:
// the monitor reports what really happened (jtag_scan_txn).
// ============================================================================
class jtag_seq_item extends uvm_sequence_item;

  typedef enum {IR_SCAN, DR_SCAN, RESET_TMS, RESET_TRST, IDLE, TCK_STOP, TMS_PATH} kind_e;

  rand kind_e       kind;
  rand int unsigned len;           // random length; after randomize, len == tdi_q.size()
  bit               tdi_q[$];      // bits to shift in, LSB first: what the driver uses
  rand bit          use_pause;     // go through Pause-xR in the middle of the shift
  rand int unsigned pause_at;      // pause after this bit
  rand int unsigned pause_cycles;  // extra cycles in Pause-xR
  rand int unsigned idle_cycles;   // IDLE: cycles in Run-Test/Idle; TCK_STOP: stopped cycles
  int unsigned      fixed_len;     // not rand: size of a pre-filled tdi_q (0: none)
  bit               tms_q[$];      // TMS_PATH: raw TMS values from Run-Test/Idle; must be followed by a reset
  bit               trst_short;    // RESET_TRST: pulse that starts and ends between two TCK edges

  // The solver must see the real length, or it picks pause_at for a random len
  constraint c_len    { len inside {[0:80]}; fixed_len != 0 -> len == fixed_len; }
  constraint c_pause  { use_pause -> (len >= 2 && pause_at < len - 1); pause_cycles inside {[0:5]}; }
  constraint c_idle   { idle_cycles inside {[1:20]}; }

  `uvm_object_utils(jtag_seq_item)

  function new(string name = "jtag_seq_item");
    super.new(name);
  endfunction

  function void pre_randomize();
    fixed_len = tdi_q.size();
  endfunction

  // tdi_q is not a rand field: random queue sizes are poorly supported by some
  // simulators, so `len` is randomized and the data drawn here. If a sequence
  // pre-filled tdi_q, its size wins (pre_randomize / c_len); the fatal below is
  // the safety net.
  function void post_randomize();
    if (tdi_q.size() == 0)
      repeat (len) tdi_q.push_back(1'($urandom));
    else
      len = tdi_q.size();
    if (use_pause && !(len >= 2 && pause_at < len - 1))
      `uvm_fatal("ITEM", $sformatf("pause_at=%0d does not fit a %0d-bit scan", pause_at, len))
  endfunction

  function string convert2string();
    case (kind)
      IR_SCAN, DR_SCAN: begin
        string p = "";
        if (use_pause) p = $sformatf(" pause@%0d", pause_at);
        return $sformatf("%s len=%0d%s", kind.name(), tdi_q.size(), p);
      end
      IDLE, TCK_STOP:   return $sformatf("%s %0d cycles", kind.name(), idle_cycles);
      TMS_PATH:         return $sformatf("TMS_PATH %0d steps", tms_q.size());
      default:          return kind.name();
    endcase
  endfunction

endclass
