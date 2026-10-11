// ============================================================================
// mbist_stub.sv -- stand-in for an MBIST engine, TCK domain (R19-R21).
// mbist_start is a level: while it is 1 the stub counts rising edges and
// reports done/pass after MBIST_CYCLES of them; dropping it clears the stub.
// ============================================================================
module mbist_stub #(
  parameter int MBIST_CYCLES = 16       // >= 1
) (
  input  logic tck,
  input  logic trst_n,
  input  logic mbist_start,
  input  logic mbist_fail_i,          // 1 = this run fails
  output logic mbist_done,
  output logic mbist_pass
);

  localparam int CNT_W = (MBIST_CYCLES > 1) ? $clog2(MBIST_CYCLES) : 1;

  logic [CNT_W-1:0] cnt;

  always_ff @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      cnt        <= '0;
      mbist_done <= 1'b0;
      mbist_pass <= 1'b0;
    end else if (!mbist_start) begin
      // R19: idle and cleared while mbist_start is 0
      cnt        <= '0;
      mbist_done <= 1'b0;
      mbist_pass <= 1'b0;
    end else if (!mbist_done) begin
      // R20: done on the MBIST_CYCLES-th edge that samples mbist_start = 1.
      // R21: once done, nothing changes until mbist_start drops.
      if (cnt == CNT_W'(MBIST_CYCLES - 1)) begin
        mbist_done <= 1'b1;
        mbist_pass <= !mbist_fail_i;
      end else begin
        cnt <= cnt + 1'b1;
      end
    end
  end

endmodule
