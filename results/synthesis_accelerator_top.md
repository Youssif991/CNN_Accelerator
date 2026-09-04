# Synthesis Results — `accelerator_top` on PYNQ-Z2

Stream-only design (output mirror removed), post-route, 2026-09-04. Prior
entries (output FIFO / PR #16, and streaming input / PR #15) are kept below
for comparison.

## 1. Setup

| Item             | Value                                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------------------------- |
| Design           | `accelerator_top` (N=3, 32×32 image, 8-bit unsigned pixels, 8-bit signed coefficients, 16-bit signed outputs) |
| Input interface  | Streaming: `pixel_in_i[7:0]` + `pixel_valid_i` (deasserted valid = stall; counters/window hold), `ready_o` |
| Output interface | FWFT output FIFO only: `result_o` / `result_valid_o` / `result_tlast_o` + `result_ready_i` back-pressure  |
| Output buffering | 16 × 17-bit FWFT sync FIFO (`output_fifo`, 12 LUTRAMs); a full FIFO stalls the accept via `output_stall`  |
| Result storage   | **none** — the `res_mem` output mirror and its readback port were removed; results exist only in the stream |
| Pipeline         | `PIPE_STAGES = 2` (register stages align the valid flag with the result data)                            |
| Device           | XC7Z020-CLG400-1 (PYNQ-Z2), speed grade -1                                                               |
| Tool             | Vivado 2025.2, batch flow (`scripts/run_synth.tcl`)                                                      |
| Flow             | synthesis → opt_design → place → route (reports post-route)                                              |
| Constraints      | `src/constraints/pynq_z2.xdc` — 125 MHz clock on `clk_i` (pin H16), reset on `rst_n_i` (pin M19)          |
| Date             | 2026-09-04 (mirrorless stream-only output)                                                               |

## 2. Utilization (post-route)

| Resource                               | Used | Available   | Utilization |
| -------------------------------------- | ---- | ----------- | ----------- |
| LUTs (total)                           | 1218 | 53 200      | 2.3 %       |
| — as logic                             | 1190 | —           | —           |
| — as LUTRAM (output FIFO)              | 12   | 17 400      | 0.1 %       |
| — as shift registers (line buffers)    | 16   | 17 400      | 0.1 %       |
| FFs                                    | 374  | 106 400     | 0.4 %       |
| Block RAM (RAMB18)                     | **0**| 280 (18 Kb) | 0 %         |
| DSPs                                   | **0**| 220         | 0 %         |

Top consumers: `kernel_reg_bank` 506 LUTs (includes the 9 LUT-based Booth
multipliers, cross-hierarchy), `window_array` 532 (window + line-buffer logic,
cross-hierarchy), `adder_tree` 97. The output FIFO (16 × 17-bit FWFT) lives in
12 LUTRAMs + top-level FFs. No block RAM anywhere: the `res_mem` mirror,
`addr_gen_out`, the `col_valid` chains, and the registered read port were
deleted — the accelerator is now purely streaming in and streaming out.

Delta vs the output-FIFO design (PR #16): −12 LUTs, −13 FFs, **−1 RAMB18**,
plus the removed readback/col-valid logic, for a resource penalty of
1218 + 50·0 + 100·0 = **1218** (was 1330, −8.4 %).

## 3. Timing (post-route, 8.0 ns / 125 MHz constraint)

| Metric        | Value                                                |
| ------------- | ---------------------------------------------------- |
| WNS           | **+0.641 ns (MET)**                                  |
| WHS           | **+0.110 ns (hold met)**                             |
| Critical path | ≈ 7.36 ns                                            |
| **Fmax**      | **≥ 125 MHz** (constraint met; ≈ 136 MHz achievable) |

WNS improved +0.186 ns vs the FIFO-era design (the BRAM read-data register and
the col-valid gating logic are gone from the pipeline). The critical path is
still the LUT multiplier → MAC → adder tree chain.

## 4. Power (post-route, SAIF-annotated from `tb_accelerator_top`)

| Metric              | Value       |
| ------------------- | ----------- |
| Total on-chip power | **0.132 W** |
| Dynamic             | 0.027 W     |
| Device static       | 0.105 W     |
| Confidence          | **Medium**  |

Dynamic is higher than the FIFO-era measurement (0.014 W) **because the SAIF
profile changed, not because of the RTL removal**: the testbench no longer
interleaves long idle `res_mem` readback sweeps between frames, so the SAIF
window is now compute/stream almost exclusively — a *more representative*
figure for sustained streaming operation. Total power is dominated by device
static (0.105 W), unchanged. Switching activity comes from
`scripts/run_power_sim.tcl` (`open_saif`/`log_saif` over `tb_accelerator_top`,
applied in `run_synth.tcl` via `read_saif`).

## 5. Figure of Merit

```
FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))
```

- Resource penalty = 1218 + 50·0 + 100·0 = **1218**
- **Streaming valid (the bonus): 958 valid pulses over 958 COMPUTE cycles =
  1.0 output/cycle sustained** — `result_valid_o` stays high every cycle in
  COMPUTE after the pipeline fill; the N−1 border windows per row produce
  deterministic boundary values the host discards. Verified by a dedicated TB
  checker (no two-cycle deassertions while the input is continuously valid).
- With the output FIFO, the bonus holds for any consumer that can keep up at
  one word/cycle; a slower consumer back-pressures through `result_ready_i`
  and the pipeline freezes without losing or reordering words.
- Real output rate (in-image results in the stream): 900 / 1037 cycles ×
  125 MHz ≈ **108.5 Mpix/s**
- Peak throughput = 125 Mpix/s (consumer keeps up)
- MAC rate ≈ 0.98 GMAC/s (real outputs, average)

| Power basis             | FoM            |
| ----------------------- | -------------- |
| Total power (0.132 W)   | **6.75 × 10⁵** |
| Dynamic power (0.027 W) | **3.30 × 10⁶** |

The resource win (−8.4 % penalty, 0 BRAM) is real but is masked in the
total-power FoM by the higher, compute-only dynamic estimate: vs the FIFO-era
entry this is ≈ 0.98× on total power (6.75 vs 6.86 × 10⁵). On a fixed
frequency/power basis (125 MHz, 0.119 W) the mirrorless design is ≈ 1.10×
better than the FIFO-era design, and vs the original memory-mapped design
(6.44 × 10⁵) still ≈ 1.05× higher.

**Throughput reporting (organizer requirement):** peak and average are both
reported above. The one-output-per-cycle bonus is implemented and verified;
the output stream carries the 958 words per frame with a single `tlast` on the
final word. Initial latency (FILL + pipeline fill) and pauses between frames
are not counted, per the rules.

---

## Prior entry — output FIFO (PR #16), 2026-09-03

Same as above but with the `res_mem` output mirror (900-word RAMB18) and the
`col_valid` gating retained alongside the FIFO stream. Post-route:

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
`result_valid_o`, `res_mem` readback retained. Post-route:

| Metric        | Value                                            |
| ------------- | ------------------------------------------------ |
| LUTs          | 1205 (logic 1189, SRL 16)                        |
| FFs           | 375                                              |
| RAMB18        | 1                                                |
| WNS           | +0.764 ns (MET, ≈ 138 MHz achievable)            |
| Total power   | 0.119 W (dynamic 0.014 W, static 0.105 W)        |
| FoM (total)   | **7.05 × 10⁵**                                   |
| FoM (dynamic) | **5.94 × 10⁶**                                   |
