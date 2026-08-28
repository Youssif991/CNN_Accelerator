# Synthesis Results — `accelerator_top` on PYNQ-Z2

## 1. Setup

| Item | Value |
|---|---|
| Design | `accelerator_top` (N=3, 32×32 image, 8-bit pixels, 8-bit signed coefficients, 16-bit outputs) |
| Device | XC7Z020-CLG400-1 (PYNQ-Z2), speed grade -1 |
| Tool | Vivado 2025.2, batch flow (`scripts/run_synth.tcl`) |
| Flow | synthesis → opt_design → place → route (reports post-route) |
| Constraints | `src/constraints/pynq_z2.xdc` — 125 MHz clock on `clk_i` (pin H16), reset on `rst_n_i` (pin M19) |
| Date | 2026-08-27 (updated after datapath pipelining) |

## 2. Utilization (post-route)

| Resource | Used | Available | Utilization |
|---|---|---|---|
| LUTs (total) | 1216 | 53 200 | 2.3 % |
| — as logic | 1200 | — | — |
| — as shift registers (line buffers) | 16 | 17 400 | 0.1 % |
| FFs | 411 | 106 400 | 0.4 % |
| Block RAM (RAMB18: input image + output memory) | 2 | 280 (18 Kb) | 0.7 % |
| DSPs | **0** | 220 | 0 % |

Top consumers: `kernel_reg_bank` 505 LUTs, `line_buffer_bank` 383 (SRL-based),
`window_array` 177, `adder_tree` 97.

## 3. Timing (post-route, 8.0 ns / 125 MHz constraint)

| Metric | Value |
|---|---|
| WNS | **+0.367 ns (MET)** |
| TNS | 0.000 ns |
| WHS | +0.096 ns (hold met) |
| THS | 0.000 ns |
| Critical path | 7.54 ns (logic 2.57 ns / route 4.97 ns), 1 logic level |
| **Fmax** | **≥ 125 MHz** (constraint met) |

Achieved by pipelining the MAC → adder-tree → saturate/round chain:
`PIPE_STAGES` parameter (3 with the registered input read) in
`accelerator_top`/`conv_fsm`; the result-valid flag shifts with the data and
the FSM's COMPUTE-exit countdown covers the pipeline latency. Before the
pipeline: Fmax ≈ 62 MHz (WNS −8.18 ns).

## 4. Power (post-route, SAIF-annotated from `tb_accelerator_top`)

| Metric | Value |
|---|---|
| Total on-chip power | **0.119 W** |
| Dynamic | 0.014 W |
| Device static | 0.105 W |
| Confidence | **Medium** (19 % of nets annotated; I/O and clock activity High) |

Switching activity comes from `scripts/run_power_sim.tcl` (batch xsim with
`open_saif`/`log_saif` over the full end-to-end testbench →
`synth_out/activity.saif`), applied in `run_synth.tcl` via `read_saif`.
Without SAIF the estimate was vector-less (Low confidence, 0.154 W).

## 5. Figure of Merit

FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))

- Resource penalty = 1216 + 50·0 + 100·2 = **1416**
- Effective throughput = (900 outputs / 1037 cycles) × 125 MHz ≈ **108.5 Mpix/s**
- MAC rate ≈ 0.98 GMAC/s

| Power basis | FoM |
|---|---|
| Total power (0.119 W) | **6.44 × 10⁵** |
| Dynamic power (0.014 W) | **5.48 × 10⁶** |

vs. the unpipelined design (62 MHz, penalty 2082, 0.154 W): **≈ 3.8× higher
FoM**.

## 6. Verification status

- RTL verified end-to-end (`tb_accelerator_top`): golden convolution model,
  double buffering, host-paced kernel writes, all 900 outputs per frame.
- Post-synthesis gate-level check (`tb_netlist_check` + netlist sim in xsim):
  the flattened `write_verilog` netlist shows a 2-output startup discrepancy
  (out[0]/out[1]) that could not be reproduced at RTL and was traced to
  `write_verilog` name-collision artifacts (internal nets renamed to
  `state_o_OBUF` collide with the real state bus in the flattened text). The
  in-memory routed netlist connections were verified correct. Board-level
  bring-up remains the definitive check (optional bonus).

## 7. Next steps

- Board demo on PYNQ-Z2 (bonus)
