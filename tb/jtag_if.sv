// ============================================================================
// jtag_if.sv -- JTAG pins. tck is generated in tb_top from a free-running
// clock gated by tck_en, so the driver can stop TCK (legal in JTAG).
// Monitors sample through mon_cb: #1step input skew gives the values just
// before the rising edge in every simulator, even for outputs that change in
// the same time step as the edge.
// ============================================================================
interface jtag_if;
  logic tck;
  logic tck_en;
  logic tms;
  logic tdi;
  logic trst_n;
  logic tdo;
  logic tdo_en;

  clocking mon_cb @(posedge tck);
    default input #1step;
    input tms, tdi, trst_n, tdo, tdo_en;
  endclocking
endinterface
