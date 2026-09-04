# Synthesis Results — `accelerator_top` on PYNQ-Z2

DSP-MAC design (9 × DSP48E1), post-route, 2026-09-04. Prior entries
(mirrorless LUT, output FIFO / PR #16, streaming input / PR #15) are kept
below for comparison.

## 1. Setup

| Item             | Value                                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------------------------- |
| Design           | `accelerator_top` (N=3, 32×32 image, 8-bit unsigned pixels, 8-bit signed coefficients, 16-bit signed outputs) |
| MAC taps         | **9 × `dsp_mult_r4`** — DSP48E1 inference (`use_dsp` attribute); each product register is pipeline stage 1. The LUT radix-4 Booth multiplier and its sub-blocks were removed from the tree |
| Input interface  | Streaming: `pixel_in_i[7:0]` + `pixel_valid_i` (deasserted valid = stall; counters/window hold), `ready_o` |
| Output interface | FWFT output FIFO only: `result_o` / `result_valid_o` / `result_tlast_o` + `result_ready_i` back-pressure  |
| Output buffering | 16 × 17-bit FWFT sync FIFO (`output_fifo`, 12 LUTRAMs); a full FIFO stalls the accept via `output_stall`  |
| Result storage   | none — results exist only in the stream (the `res_mem` mirror was removed)                               |
| Pipeline         | `PIPE_STAGES = 2` — stage 1 is the DSP P register, stage 2 the adder-tree sum register                   |
| Device           | XC7Z020-CLG400-1 (PYNQ-Z2), speed grade -1                                                               |
| Tool             | Vivado 2025.2, batch flow (`scripts/run_synth.tcl`)                                                      |
| Flow             | synthesis → opt_design → place → route (reports post-route)                                              |
| Constraints      | `src/constraints/pynq_z2.xdc` — 125 MHz clock on `clk_i` (pin H16), reset on `rst_n_i` (pin M19)          |
| Date             | 2026-09-04 (DSP MAC taps)                                                                                |

## 2. Utilization (post-route)

| Resource                               | Used | Available   | Utilization |
| -------------------------------------- | ---- | ----------- | ----------- |
| LUTs (total)                           | **179** | 53 200  | 0.3 %       |
| — as logic                             | 151  | —           | —           |
| — as LUTRAM (output FIFO)              | 12   | 17 400      | 0.1 %       |
| — as shift registers (line buffers)    | 16   | 17 400      | 0.1 %       |
| FFs                                    | 212  | 106 400     | 0.2 %       |
| Block RAM (RAMB18)                     | 0    | 280 (18 Kb) | 0 %         |
| DSPs                                   | **9**| 220         | 4.1 %       |

Top consumers are gone: with the multipliers in DSPs, `kernel_reg_bank` is now
1 LUT + 72 FFs and `window_array` 0 LUTs + 72 FFs (their registers feed the DSP
A/B inputs directly); `adder_tree` 80 LUTs; the output FIFO is the 12 LUTRAMs.
The 9 Booth multipliers (1044 LUTs in the LUT design) became 9 DSP48E1s.

Resource penalty = 179 + 50·9 + 100·0 = **629** (was 1218 mirrorless LUT,
1330 FIFO-era): **−48 % vs the LUT-MAC design** for the same throughput.

## 3. Timing (post-route, 8.0 ns / 125 MHz constraint)

| Metric        | Value                                                |
| ------------- | ---------------------------------------------------- |
| WNS           | **+0.746 ns (MET)**                                  |
| WHS           | **+0.035 ns (hold met)**                             |
| Critical path | ≈ 7.25 ns                                            |
| **Fmax**      | **≥ 125 MHz** (constraint met; ≈ 138 MHz achievable) |

The DSP48E1 multiply (with its internal P register) is off the LUT critical
path entirely — the LUT Booth chain (encoder → selector → compressor → final
adder, the old ~7.4 ns path) is replaced by a register-to-register DSP hop.
WNS improves +0.105 ns over the mirrorless LUT design.

## 4. Power (post-route, SAIF-annotated from `tb_accelerator_top`)

| Metric              | Value       |
| ------------------- | ----------- |
| Total on-chip power | **0.112 W** |
| Dynamic             | 0.008 W     |
| Device static       | 0.104 W     |
| Confidence          | **Medium**  |

Dynamic power drops ~3.4× vs the mirrorless LUT design (0.027 W → 0.008 W):
the LUT multiplier chains (the largest toggling logic) are gone and the FF
count fell from 374 to 212, so the clock/FF activity is much lower. Total power
is dominated by device static (0.104 W). Switching activity comes from
`scripts/run_power_sim.tcl` (`open_saif`/`log_saif` over `tb_accelerator_top`,
applied in `run_synth.tcl` via `read_saif`).

## 5. Figure of Merit

```
FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))
```

- Resource penalty = 179 + 50·9 + 0 = **629**
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
| Total power (0.112 W)   | **1.54 × 10⁶** |
| Dynamic power (0.008 W) | **2.16 × 10⁷** |

vs the mirrorless LUT-MAC design (6.75 × 10⁵ total-power basis): **≈ 2.3×
higher FoM** — the DSP swap roughly halves the resource penalty (−48 %) and
cuts dynamic power ~3.4×, so the FoM nearly doubles-and-a-half. vs the original
memory-mapped design (6.44 × 10⁵): ≈ 2.4× higher.

**Throughput reporting (organizer requirement):** peak and average are both
reported above. The one-output-per-cycle bonus is implemented and verified;
the output stream carries the 958 words per frame with a single `tlast` on the
final word. Initial latency (FILL + pipeline fill) and pauses between frames
are not counted, per the rules.

---

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
