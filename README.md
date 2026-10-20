# JTAG TAP Controller: RTL, Formal Proof and UVM Verification

An IEEE 1149.1 test access port (TAP) with a private DFT control register, written in SystemVerilog and verified three ways:

1. **Formal (Questa PropCheck), done:** full (unbounded) proofs of the TAP state machine, the IR / DR protocol, the DFT register and the MBIST timing, with covers for every state and transition. No assumptions: every input is free, and `trst_n` can assert at any cycle. 63/63 assertions proven, 67/67 covers reached.
2. **UVM (QuestaSim), planned:** a JTAG agent whose monitor rebuilds the TAP state from the pins on its own and feeds a reference-model scoreboard, so a driver bug cannot hide a DUT bug. Directed tests plus a random test with TCK stops and mid-scan `trst_n`, to be signed off on merged coverage over 20 seeds.
3. **Mutation testing, planned:** 21 injected bugs, each to be recorded as caught by formal, by simulation, or both.

The full plan is in [docs/plan.md](docs/plan.md), the design rules in [docs/design_spec.md](docs/design_spec.md).

Same toolchain and flow as [axi4lite_uvm_questa](https://github.com/Snowy0521/axi4lite_uvm_questa).

## Status

Work in progress.

| Part | State |
|---|---|
| Design specification ([docs/design_spec.md](docs/design_spec.md), rules R1–R23) | done |
| RTL (`rtl/`) | done |
| Lint (verilator `-Wall`, slang) | clean |
| Directed smoke test (iverilog) | passing |
| Formal properties and proofs (`formal/`) | done |
| UVM environment and regression (`tb/`) | in progress |
| Mutation testing (`mutations/`) | planned |

## Design

![Block diagram of the JTAG TAP: state machine, instruction register, data registers, DFT control register, MBIST stub and TDO stage](docs/img/jtag_tap_block.svg)

**How a scan moves through the blocks** (blue registers change on the rising edge of TCK, orange ones on the falling edge):

1. **`jtag_tap_fsm`** steps through the 16 TAP states on every rising edge, driven only by TMS. Its `state` output tells every other block what to do in this cycle.
2. **IR scan (`jtag_ir`):** in Capture-IR the IR shift register loads `0001`; in Shift-IR it shifts TDI in and its bit 0 goes out on TDO. In Update-IR, on the falling edge, the shifted value becomes the active **instruction**. `decode` turns the instruction into `dr_sel`, which picks one data register; unknown opcodes pick BYPASS.
3. **DR scan (`jtag_dr`):** only the selected shift register captures and shifts. BYPASS captures 0, IDCODE captures the 32-bit ID, DFT_CTRL captures the current DFT outputs plus the MBIST status. The mux sends bit 0 of the selected register to the TDO stage.
4. **DFT write:** in Update-DR with DFT_CTRL selected, the falling edge copies the DFT_CTRL shift register into the **DFT update registers**, which drive `test_mode`, `scan_en` and `mbist_start` directly. `scan_en` is stored as `sr[1] & sr[0]`, so it can never be 1 without `test_mode`.
5. **`mbist_stub`:** while `mbist_start` is 1 it counts TCK cycles; after `MBIST_CYCLES` it sets `mbist_done`, with `mbist_pass = !mbist_fail_i`. The next DFT_CTRL capture reads both back.
6. **TDO stage:** on each falling edge, `tdo` takes bit 0 of the IR (in Shift-IR) or of the selected DR (in Shift-DR), and `tdo_en` is 1 only in those two states. The tester samples TDO on the next rising edge.
7. **Reset:** `trst_n` clears everything asynchronously. Reaching Test-Logic-Reset with TMS (five cycles of TMS = 1 from any state) has the same effect on the next falling edge: instruction = IDCODE, DFT outputs = 0, so the chip is back in functional mode.

Instructions: BYPASS (`1111`), IDCODE (`0001`, default after reset) and the private DFT_CTRL (`1000`); every other opcode behaves as BYPASS. EXTEST and SAMPLE/PRELOAD are mandatory in IEEE 1149.1 but not implemented yet (boundary scan is a planned extension), so the design does not claim full 1149.1 compliance. Register maps and all rules: [docs/design_spec.md](docs/design_spec.md).

## How to run

All targets run from the repository root; outputs go to `build/`.

| Command | Tools | What it does |
|---|---|---|
| `make lint` | Verilator, slang | Lint the RTL (`rtl/rtl.f`) |
| `make smoke` | Icarus Verilog | Directed smoke test `tb/tb_smoke.sv`: reset, IDCODE, BYPASS, unused opcode, DFT writes, MBIST pass / fail / restart, TMS reset, mid-scan `trst_n` |
| `make gen` | Python | Regenerate the per-arc state-machine checks from the spec's state table |
| `make props-sim` | Verilator | Run the formal properties in a random simulation (local sanity check, not a proof) |
| `make formal` | Questa Formal | Prove all properties (`formal/run_formal.tcl`) |
| `make uvm TEST=<test> SEED=<n>` | Verilator + UVM 1800.2 | Run a UVM test locally (development; sign-off runs on Questa) |
| `make clean` | | Remove `build/` |

Questa targets for UVM (`sim`, `regress`, `cov`) and mutations (`mutate`) will follow. The open-source tools cannot run the formal proofs, and Verilator's functional coverage support is limited, so coverage sign-off runs on Questa.

## Results

To be filled in as each flow is completed.

**Formal (Questa PropCheck)**

| Assertions proven | Covers reached | Proof depth | Run time |
|---|---|---|---|
| 63 / 63 | 67 / 67 | full proof (unbounded) | 595 s (4 engines, Questa 2024.3) |

**UVM regression (QuestaSim)**

| Seeds passed | Directed tests passed | Merged functional coverage | Code coverage (stmt / branch / FSM) |
|---|---|---|---|
| – | – | – | – |

**Mutation testing**

| Mutations | Caught by formal | Caught by simulation | Caught by both | Missed |
|---|---|---|---|---|
| 21 | – | – | – | – |

## Repository layout

```
jtag_tap_verif/
├── README.md
├── LICENSE                  MIT
├── Makefile                 lint / smoke (Questa targets to follow)
├── docs/
│   ├── design_spec.md       rules R1–R23, traceability to checks and mutations
│   ├── plan.md              verification plan
│   └── img/                 block diagram and timing diagram (SVG)
├── rtl/
│   ├── rtl.f                file list (repo-root-relative)
│   ├── jtag_pkg.sv          state encoding, opcodes, IDCODE, IR decode
│   ├── jtag_tap_fsm.sv      16-state TAP controller
│   ├── jtag_ir.sv           instruction register
│   ├── jtag_dr.sv           BYPASS, IDCODE, DFT_CTRL registers
│   ├── mbist_stub.sv        MBIST stand-in
│   └── jtag_tap_top.sv      top level, TDO stage
├── formal/                  formal harness, checkers, Questa run script
├── scripts/
│   └── gen_fsm_props.py     spec state table → per-arc checks
└── tb/                      UVM testbench (agent, monitor, sequences, tests), tb_smoke.sv directed smoke test
```

Planned: `mutations/`, named in [docs/plan.md](docs/plan.md) where it is introduced.

## References

- IEEE Std 1149.1-2013, *Standard for Test Access Port and Boundary-Scan Architecture*.
- IEEE Std 1500-2005 (embedded core test) and IEEE Std 1687-2014 (IJTAG): background.
- [axi4lite_uvm_questa](https://github.com/Snowy0521/axi4lite_uvm_questa): the Questa formal / UVM flow this project reuses.

## License

[MIT](LICENSE)
