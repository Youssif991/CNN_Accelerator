# Synthesis Results — `accelerator_top` on PYNQ-Z2

## 1. Setup

| Item | Value |
|---|---|
| Design | `accelerator_top` (N=3, 32×32 image, 8-bit pixels, 8-bit signed coefficients, 16-bit outputs) |
| Device | XC7Z020-CLG400-1 (PYNQ-Z2), speed grade -1 |
| Tool | Vivado 2025.2, batch flow (`scripts/run_synth.tcl`) |
| Flow | synthesis → opt_design → place → route (reports post-route) |
| Constraints | `src/constraints/pynq_z2.xdc` — 125 MHz clock on `clk_i` (pin H16), reset on `rst_n_i` (pin M19) |
| Date | 2026-08-27 |

## 2. Utilization (post-route)

| Resource | Used | Available | Utilization |
|---|---|---|---|
| LUTs (total) | 1982 | 53 200 | 3.7 % |
| — as logic | 1582 | — | — |
| — as distributed RAM (input image) | 384 | 17 400 | 2.2 % |
| — as shift registers (line buffers) | 16 | 17 400 | 0.1 % |
| FFs | 236 | 106 400 | 0.2 % |
| CARRY4 | 74 | 13 300 | 0.6 % |
| Block RAM (RAMB18, output memory) | 1 | 280 (18 Kb) | 0.4 % |
| DSPs | **0** | 220 | 0 % |

Top consumers: `kernel_reg_bank` 612 LUTs, `line_buffer_bank` 476, top-level
memories/muxing 416, `window_array` 221, `mac_array` 90 (multiplier logic is
absorbed across hierarchy boundaries), `sat_round_unit` 56.

## 3. Timing (post-route, 8.0 ns / 125 MHz constraint)

| Metric | Value |
|---|---|
| WNS | **−8.180 ns** (VIOLATED) |
| TNS | −131.882 ns |
| WHS | +0.168 ns (hold met) |
| THS | 0.000 ns |
| Critical path | 15.865 ns (logic 5.68 ns / route 10.19 ns), 16 logic levels |
| **Achievable Fmax** | **≈ 61.8 MHz** (1 / (8.0 + 8.18) ns) |

Critical path: line-buffer register → window/kernel read mux → Booth
multiplier tap-4 final adder → `sat_round_unit` carry chains → output BRAM
write port. The MAC → adder-tree → saturate/round chain is fully
combinational in one cycle; this is the Fmax limiter.

## 4. Power (post-route, vector-less estimate)

| Metric | Value |
|---|---|
| Total on-chip power | **0.154 W** |
| Dynamic | 0.049 W (clocks 0.005, slice 0.010, signals 0.017, BRAM 0.001, I/O 0.015) |
| Device static | 0.105 W |
| Confidence | Low (no switching-activity file; annotate with SAIF from `tb_accelerator_top` for the report) |

## 5. Figure of Merit

FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))

- Resource penalty = 1982 + 50·0 + 100·1 = **2082**
- Effective throughput = (900 outputs / 1037 cycles) × 61.8 MHz ≈ **53.8 Mpix/s**
- MAC rate ≈ 0.48 GMAC/s

| Power basis | FoM |
|---|---|
| Total power (0.154 W) | **1.68 × 10⁵** |
| Dynamic power (0.049 W) | **5.27 × 10⁵** |

## 6. Observations and next steps

- The design meets the issue-#7 goals: **0 DSPs** (LUT-based radix-4 Booth)
  and **1 BRAM** (single output memory; input is distributed RAM).
- Timing fails at 125 MHz — the unpipelined combinational MAC chain caps
  Fmax at ~62 MHz. Pipelining the MAC → adder-tree → saturate chain
  (1–2 stages, with a valid bit shifted alongside) would roughly double the
  throughput and FoM.
- Power confidence is low; annotate switching activity from the
  end-to-end testbench for the final competition report.
- Optional: DSP-variant comparison (`dsp_mult` drop-in in `mac_array`) for
  the FoM trade-off table.
