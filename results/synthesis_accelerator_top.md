# Synthesis Results — `accelerator_top` on PYNQ-Z2

Output-stream design (output FIFO + back-pressure + `tlast`), post-route,
2026-09-03. Prior entry (streaming input, PR #15) is kept below for comparison.

## 1. Setup

| Item             | Value                                                                                                                       |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Design           | `accelerator_top` (N=3, 32×32 image, 8-bit unsigned pixels, 8-bit signed coefficients, 16-bit signed outputs)               |
| Input interface  | Streaming: `pixel_in_i[7:0]` + `pixel_valid_i` (deasserted valid = stall; counters/window hold), `ready_o` = accepting       |
| Output interface | FWFT output FIFO: `result_o`/`result_valid_o`/`result_tlast_o` + `result_ready_i` back-pressure + RAM readback (`res_rd_addr_i`/`res_rd_data_o`) |
| Output buffering | 16 × 17-bit FWFT sync FIFO (`output_fifo`, 12 LUTRAMs) decouples the pipeline from the consumer; a full FIFO stalls the accept via `output_stall` |
| Pipeline         | `PIPE_STAGES = 2` (streaming input adds no registered read, so 2 register stages align the valid flag with the result data) |
| Device           | XC7Z020-CLG400-1 (PYNQ-Z2), speed grade -1                                                                                  |
| Tool             | Vivado 2025.2, batch flow (`scripts/run_synth.tcl`)                                                                         |
| Flow             | synthesis → opt_design → place → route (reports post-route)                                                                 |
| Constraints      | `src/constraints/pynq_z2.xdc` — 125 MHz clock on `clk_i` (pin H16), reset on `rst_n_i` (pin M19)                            |
| Date             | 2026-09-03 (output FIFO + back-pressure + tlast)                                                                            |

## 2. Utilization (post-route)

| Resource                               | Used  | Available   | Utilization |
| -------------------------------------- | ----- | ----------- | ----------- |
| LUTs (total)                           | 1230  | 53 200      | 2.3 %       |
| — as logic                             | 1202  | —           | —           |
| — as LUTRAM (output FIFO)              | 12    | 17 400      | 0.1 %       |
| — as shift registers (line buffers)    | 16    | 17 400      | 0.1 %       |
| FFs                                    | 387   | 106 400     | 0.4 %       |
| Block RAM (RAMB18: output memory only) | 1     | 280 (18 Kb) | 0.4 %       |
| DSPs                                   | **0** | 220         | 0 %         |

Top consumers: `kernel_reg_bank` 505 LUTs (includes the 9 LUT-based Booth
multipliers, cross-hierarchy), `window_array` 533 (window + line-buffer logic,
cross-hierarchy), `adder_tree` 97. The output FIFO (16 × 17-bit FWFT) is
implemented in 12 LUTRAMs + the top-level FFs, not block RAM. All multipliers
are LUT-based (0 DSPs).

Delta vs the streaming-input design (PR #15): +25 LUTs, +12 FFs, +12 LUTRAMs —
the FIFO pointers/storage and the pipeline freeze logic (`output_stall` gating
of every pipeline stage, the `last_p`/`col_valid_p` chains). RAMB18 unchanged
(1, the output `res_mem`).

## 3. Timing (post-route, 8.0 ns / 125 MHz constraint)

| Metric        | Value                                                |
| ------------- | ---------------------------------------------------- |
| WNS           | **+0.455 ns (MET)**                                  |
| WHS           | **+0.185 ns (hold met)**                             |
| Critical path | ≈ 7.55 ns                                            |
| **Fmax**      | **≥ 125 MHz** (constraint met; ≈ 132 MHz achievable) |

The critical path is unchanged in nature (kernel LUT multiplier → MAC →
adder tree); the freeze muxes added to the pipeline registers cost a small
margin vs the previous +0.764 ns WNS, but 125 MHz is still met comfortably.

## 4. Power (post-route, SAIF-annotated from `tb_accelerator_top`)

| Metric              | Value       |
| ------------------- | ----------- |
| Total on-chip power | **0.119 W** |
| Dynamic             | 0.014 W     |
| Device static       | 0.105 W     |
| Confidence          | **Medium**  |

Switching activity comes from `scripts/run_power_sim.tcl` (batch xsim with
`open_saif`/`log_saif` over the full end-to-end testbench — now including the
back-pressure frames and the output-FIFO activity → `synth_out/activity.saif`),
applied in `run_synth.tcl` via `read_saif`. The FIFO is nearly idle in the
power trace (consumer keeps up), so power is unchanged at 0.119 W.

## 5. Figure of Merit

```
FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))
```

- Resource penalty = 1230 + 50·0 + 100·1 = **1330**
- **Streaming valid (the bonus): 958 valid pulses over 958 COMPUTE cycles =
  1.0 output/cycle sustained** — `result_valid_o` stays high every cycle in
  COMPUTE after the pipeline fill (no row-boundary gaps), because the valid
  now covers every accepted pixel; the N−1 border windows per row produce
  deterministic boundary values the host discards. Verified by a dedicated TB
  checker (no two-cycle deassertions while the input is continuously valid).
- With the output FIFO, the bonus holds for any consumer that can keep up at
  one word/cycle; a slower consumer back-pressures through `result_ready_i`
  and the pipeline freezes without losing or reordering words (verified with
  an injected 1-2-cycle-every-16 back-pressure test) — the sustained average
  then equals the consumer's rate.
- Real output rate (in-image results): 900 outputs / 1037 cycles × 125 MHz
  ≈ **108.5 Mpix/s**
- Peak throughput = 125 Mpix/s (consumer keeps up)
- MAC rate ≈ 0.98 GMAC/s (real outputs, average)

| Power basis             | FoM            |
| ----------------------- | -------------- |
| Total power (0.119 W)   | **6.86 × 10⁵** |
| Dynamic power (0.014 W) | **5.83 × 10⁶** |

vs. the streaming-input design (7.05 × 10⁵ total-power basis): ≈ 0.97× — the
small LUT/power delta from the output FIFO slightly lowers the FoM, in
exchange for a DMA-ready output with back-pressure and `tlast`. vs. the
original memory-mapped design (6.44 × 10⁵): still ≈ 1.06× higher.

**Throughput reporting (organizer requirement):** peak and average are both
reported above. The one-output-per-cycle bonus is implemented and verified:
`result_valid_o` pulses once per accepted pixel past the fill (958/958 in
COMPUTE); the output memory is gated by a pipeline-aligned column flag so it
still stores only the 900 in-image results. Initial latency (FILL + pipeline
fill) and pauses between frames are not counted, per the rules.

---

## Prior entry — streaming input (PR #15), 2026-08-29

Same setup but the output was direct from the pipeline (`result_o` /
`result_valid_o`, no FIFO, no back-pressure). Post-route:

| Metric        | Value                                            |
| ------------- | ------------------------------------------------ |
| LUTs          | 1205 (logic 1189, SRL 16)                        |
| FFs           | 375                                              |
| RAMB18        | 1                                                |
| WNS           | +0.764 ns (MET, ≈ 138 MHz achievable)            |
| Total power   | 0.119 W (dynamic 0.014 W, static 0.105 W)        |
| FoM (total)   | **7.05 × 10⁵**                                   |
| FoM (dynamic) | **5.94 × 10⁶**                                   |
