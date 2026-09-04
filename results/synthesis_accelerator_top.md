# Synthesis Results — `accelerator_top` on PYNQ-Z2

DSP-MAC design with the optional ReLU activation, post-route, 2026-09-04.
Prior entries (DSP MAC without ReLU, mirrorless LUT, output FIFO / PR #16,
streaming input / PR #15) are kept below for comparison.

## 1. Setup

| Item             | Value                                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------------------------- |
| Design           | `accelerator_top` (N=3, 32×32 image, 8-bit unsigned pixels, 8-bit signed coefficients, 16-bit signed outputs) |
| MAC taps         | **9 × `dsp_mult_r4`** — DSP48E1 inference (`use_dsp` attribute); each product register is pipeline stage 1 |
| Activation       | Optional ReLU: `relu_en_i` (host-set per frame) clamps negative sums to zero in `sat_round_unit` before rounding |
| Input interface  | Streaming: `pixel_in_i[7:0]` + `pixel_valid_i` (deasserted valid = stall; counters/window hold), `ready_o` |
| Output interface | FWFT output FIFO only: `result_o` / `result_valid_o` / `result_tlast_o` + `result_ready_i` back-pressure  |
| Output buffering | 16 × 17-bit FWFT sync FIFO (`output_fifo`, 12 LUTRAMs); a full FIFO stalls the accept via `output_stall`  |
| Result storage   | none — results exist only in the stream (the `res_mem` mirror was removed)                               |
| Pipeline         | `PIPE_STAGES = 2` — stage 1 is the DSP P register, stage 2 the adder-tree sum register                   |
| Device           | XC7Z020-CLG400-1 (PYNQ-Z2), speed grade -1                                                               |
| Tool             | Vivado 2025.2, batch flow (`scripts/run_synth.tcl`)                                                      |
| Flow             | synthesis → opt_design → place → route (reports post-route)                                              |
| Constraints      | `src/constraints/pynq_z2.xdc` — 125 MHz clock on `clk_i` (pin H16), reset on `rst_n_i` (pin M19)          |
| Date             | 2026-09-04 (DSP MAC taps + optional ReLU)                                                                |

## 2. Utilization (post-route)

| Resource                               | Used | Available   | Utilization |
| -------------------------------------- | ---- | ----------- | ----------- |
| LUTs (total)                           | **196** | 53 200 | 0.4 %       |
| — as logic                             | 168  | —           | —           |
| — as LUTRAM (output FIFO)              | 12   | 17 400      | 0.1 %       |
| — as shift registers (line buffers)    | 16   | 17 400      | 0.1 %       |
| FFs                                    | 212  | 106 400     | 0.2 %       |
| Block RAM (RAMB18)                     | 0    | 280 (18 Kb) | 0 %         |
| DSPs                                   | **9**| 220         | 4.1 %       |

The ReLU mux (a 22-bit sign compare + select before rounding) costs **+17
LUTs** over the plain DSP design (179 → 196); FFs, DSPs, and BRAMs are
unchanged. `kernel_reg_bank` is 1 LUT + 72 FFs and `window_array` 0 LUTs + 72
FFs (their registers feed the DSP A/B inputs directly); `adder_tree` 80 LUTs;
the output FIFO is the 12 LUTRAMs.

Resource penalty = 196 + 50·9 + 100·0 = **646** (was 629 without ReLU, +2.7 %;
vs the mirrorless LUT design's 1218: −47 %).

## 3. Timing (post-route, 8.0 ns / 125 MHz constraint)

| Metric        | Value                                                |
| ------------- | ---------------------------------------------------- |
| WNS           | **+1.044 ns (MET)**                                  |
| WHS           | **+0.089 ns (hold met)**                             |
| Critical path | ≈ 6.96 ns                                            |
| **Fmax**      | **≥ 125 MHz** (constraint met; ≈ 144 MHz achievable) |

The ReLU logic sits after the `sum_p1` register (off the critical path, which
is the DSP → adder-tree → `sum_p1` chain), so it adds no timing penalty. The
WNS difference vs the no-ReLU run (+0.746 ns) is placement variance for a
~200-LUT design, not an improvement from the added logic — treat the timing
headline as "125 MHz met with margin".

## 4. Power (post-route, SAIF-annotated from `tb_accelerator_top`)

| Metric              | Value       |
| ------------------- | ----------- |
| Total on-chip power | **0.110 W** |
| Dynamic             | 0.006 W     |
| Device static       | 0.104 W     |
| Confidence          | **Medium**  |

The SAIF comes from `scripts/run_power_sim.tcl` over the ReLU-exercising
testbench (frames alternate `relu_en_i`). The ~0.002 W dynamic delta vs the
no-ReLU run is within SAIF/estimator run-to-run variance — power is effectively
unchanged and dominated by device static (0.104 W).

## 5. Figure of Merit

```
FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))
```

- Resource penalty = 196 + 50·9 + 0 = **646**
- **Streaming valid (the bonus): 958 valid pulses over 958 COMPUTE cycles =
  1.0 output/cycle sustained** — `result_valid_o` stays high every cycle in
  COMPUTE after the pipeline fill; the N−1 border windows per row produce
  deterministic boundary values the host discards. Verified by a dedicated TB
  checker (no two-cycle deassertions while the input is continuously valid).
- With the output FIFO, the bonus holds for any consumer that can keep up at
  one word/cycle; a slower consumer back-pressures through `result_ready_i`
  and the pipeline freezes (including the DSP product register clock enable)
  without losing or reordering words.
- Real output rate (in-image results in the stream): 900 / 1037 cycles ×
  125 MHz ≈ **108.5 Mpix/s**
- Peak throughput = 125 Mpix/s (consumer keeps up)
- MAC rate ≈ 0.98 GMAC/s (real outputs, average; 9 DSP MACs/cycle peak)

| Power basis             | FoM            |
| ----------------------- | -------------- |
| Total power (0.110 W)   | **1.53 × 10⁶** |
| Dynamic power (0.006 W) | **2.80 × 10⁷** |

Essentially flat vs the no-ReLU DSP design (1.54 × 10⁶ total-power basis): the
ReLU activation costs ~2.7 % more resources and nothing measurable in power or
timing, so the FoM is unchanged while the design gains the optional activation
bonus. vs the mirrorless LUT-MAC design (6.75 × 10⁵): ≈ 2.3× higher.

**Throughput reporting (organizer requirement):** peak and average are both
reported above. The one-output-per-cycle bonus is implemented and verified;
the output stream carries the 958 words per frame with a single `tlast` on the
final word. Initial latency (FILL + pipeline fill) and pauses between frames
are not counted, per the rules.

---

## Prior entry — DSP MAC without ReLU, 2026-09-04

Identical design before the optional ReLU was added. Post-route:

| Metric        | Value                                            |
| ------------- | ------------------------------------------------ |
| LUTs          | 179 (logic 151, LUTRAM 12, SRL 16)               |
| FFs           | 212                                              |
| DSPs / RAMB18 | 9 / 0                                            |
| WNS           | +0.746 ns (MET, ≈ 138 MHz achievable)            |
| Total power   | 0.112 W (dynamic 0.008 W, static 0.104 W)        |
| FoM (total)   | **1.54 × 10⁶**                                   |
| FoM (dynamic) | **2.16 × 10⁷**                                   |

## Prior entry — mirrorless LUT MAC, 2026-09-04

Same stream-only architecture but with 9 LUT radix-4 Booth taps
(`USE_DSP = 0`, 1044 LUTs) and an explicit `products_p1` pipeline stage.
Post-route:

| Metric        | Value                                            |
| ------------- | ------------------------------------------------ |
| LUTs          | 1218 (logic 1190, LUTRAM 12, SRL 16)             |
| FFs           | 374                                              |
| DSPs / RAMB18 | 0 / 0                                            |
| WNS           | +0.641 ns (MET, ≈ 136 MHz achievable)            |
| Total power   | 0.132 W (dynamic 0.027 W, static 0.105 W)        |
| FoM (total)   | **6.75 × 10⁵**                                   |
| FoM (dynamic) | **3.30 × 10⁶**                                   |

## Prior entry — output FIFO (PR #16), 2026-09-03

Same as the mirrorless design but with the `res_mem` output mirror (900-word
RAMB18) and the `col_valid` gating retained alongside the FIFO stream, and LUT
MAC taps. Post-route:

| Metric        | Value                                            |
| ------------- | ------------------------------------------------ |
| LUTs          | 1230 (logic 1202, LUTRAM 12, SRL 16)             |
| FFs           | 387                                              |
| RAMB18        | 1 (`res_mem`)                                    |
| WNS           | +0.455 ns (MET, ≈ 132 MHz achievable)            |
| Total power   | 0.119 W (dynamic 0.014 W, static 0.105 W)        |
| FoM (total)   | **6.86 × 10⁵**                                   |
| FoM (dynamic) | **5.83 × 10⁶**                                   |

## Prior entry — streaming input (PR #15), 2026-08-29

Streaming input, no output FIFO, direct pipeline-aligned `result_o` /
`result_valid_o`, `res_mem` readback retained, LUT MAC taps. Post-route:

| Metric        | Value                                            |
| ------------- | ------------------------------------------------ |
| LUTs          | 1205 (logic 1189, SRL 16)                        |
| FFs           | 375                                              |
| RAMB18        | 1                                                |
| WNS           | +0.764 ns (MET, ≈ 138 MHz achievable)            |
| Total power   | 0.119 W (dynamic 0.014 W, static 0.105 W)        |
| FoM (total)   | **7.05 × 10⁵**                                   |
| FoM (dynamic) | **5.94 × 10⁶**                                   |
