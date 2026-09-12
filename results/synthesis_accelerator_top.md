# Synthesis & Implementation Report — `accelerator_top`

**Design:** CNN convolution accelerator, N=3, 32×32 image
**Target:** PYNQ-Z2 (XC7Z020-CLG400-1)
**Tool:** Vivado 2025.2, batch flow (`scripts/run_synth.tcl`)
**Date:** 2026-09-12
**Design state:** Routed (post-implementation)

---

## 1. Design Configuration

| Parameter | Value |
|---|---|
| Kernel size (N) | 3 |
| Input image | 32 × 32, 8-bit unsigned pixels |
| Kernel coefficients | 8-bit signed, programmable |
| Output precision | 16-bit signed |
| Padding | Row-only: 2 zero rows prepended, 0 appended |
| Stride | 1 |
| Activation | Optional ReLU (`relu_en_i`, host-set per frame) |
| Pipeline stages | 2 (DSP P register + adder-tree sum register) |
| Rounding | Round-half-up, `FRAC_BITS = 4` |
| MAC mapping | 9 × `dsp_mult_r4` → 9 × DSP48E1 |
| Input interface | Streaming: `pixel_in_i[7:0]` + `pixel_valid_i`, `ready_o` |
| Output interface | FWFT 16×17-bit FIFO: `result_o` / `result_valid_o` / `result_tlast_o` / `result_ready_i` |
| Clock | 125 MHz (8.000 ns), pin H16 |
| Reset | `rst_n_i`, pin M19 |

---

## 2. Utilization (Post-Route)

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | **345** | 53 200 | 0.65 % |
| — LUT as Logic | 329 | 53 200 | 0.62 % |
| — LUT as Shift Register | 16 | 17 400 | 0.09 % |
| — LUT as Distributed RAM | 0 | 17 400 | 0.00 % |
| Slice Registers (FFs) | **501** | 106 400 | 0.47 % |
| F7 Muxes | 34 | 26 600 | 0.13 % |
| F8 Muxes | 17 | 13 300 | 0.13 % |
| Unique Control Sets | 36 | 13 300 | 0.27 % |
| **DSP48E1** | **9** | 220 | 4.09 % |
| **Block RAM Tiles** | **0** | 140 | 0.00 % |
| BUFGCTRL | 1 | 32 | 3.13 % |
| Bonded IOB | 46 | 125 | 36.80 % |

**Slices used:** 189 of 13 300 (1.42 %), split 92 SLICEL / 97 SLICEM.

**Primitive breakdown:** 492 FDCE, 180 LUT6, 125 LUT3, 80 LUT4, 34 MUXF7, 34 CARRY4, 23 OBUF, 23 IBUF, 19 LUT2, 17 MUXF8, 16 SRLC32E, 15 LUT5, 10 LUT1, 9 DSP48E1, 8 FDRE, 1 FDPE, 1 BUFG.

**Weighted resource penalty (competition formula):**

```
LUTs + 50·DSPs + 100·BRAMs = 345 + 50·9 + 100·0 = 795
```

---

## 3. Timing (Post-Route, 125 MHz constraint / 8.000 ns)

| Metric | Value |
|---|---:|
| Clock constraint | 8.000 ns (125 MHz) |
| **Setup WNS** | **+0.895 ns (MET)** |
| Setup TNS | 0.000 ns |
| Setup failing endpoints | 0 / 1198 |
| **Hold WHS** | **+0.079 ns (MET)** |
| Hold THS | 0.000 ns |
| Hold failing endpoints | 0 / 1198 |
| **Pulse-width slack** | **+3.020 ns (MET)** |
| Pulse-width failing endpoints | 0 / 527 |
| **Fmax (from WNS)** | **1 / (8.000 − 0.895) = 140.7 MHz** |

**All user timing constraints are met.**

**Critical path (worst setup):**

| | |
|---|---|
| Source | `u_mac_array/gen_mac_taps[4].u_dsp_mult_r4/prod_q_reg/CLK` (DSP48E1) |
| Destination | `gen_pipe_sum.sum_p1_reg[21]/D` (FDCE) |
| Data path delay | 6.984 ns (logic 3.270 ns / 46.8 %, route 3.714 ns / 53.2 %) |
| Logic levels | 11 (CARRY4 = 7, LUT3 = 2, LUT4 = 2) |
| Clock path skew | −0.149 ns |
| Slack | +0.895 ns |

The path goes DSP P register → 9-input adder tree (7 CARRY4 stages) → `sum_p1` register. Route delay is slightly over half the path.

**Critical path (worst hold):**

| | |
|---|---|
| Source | `u_line_buffer_bank/gen_line_buffers[1].u_line_buffer/line_q_reg[31][0]` (FDRE) |
| Destination | `u_line_buffer_bank/gen_line_buffers[2].u_line_buffer/line_q_reg[31][0]_srl32` (SRLC32E) |
| Slack | +0.079 ns |

The three worst hold paths are all the same SRLC32E cascade inside the line buffer bank.

---

## 4. Power (Post-Route, SAIF-Annotated)

| Metric | Value |
|---|---:|
| **Total On-Chip Power** | **0.110 W** |
| Dynamic | 0.006 W (5 %) |
| Device Static | 0.104 W (95 %) |
| Confidence Level | **Medium** |
| Simulation Activity File | `synth_out/activity.saif` |
| Design Nets Matched | 9 % (125 / 1363) |
| Junction Temperature | 26.3 °C |
| Max Ambient | 83.7 °C |
| Effective θJA | 11.5 °C/W |

**Dynamic power breakdown:**

| Component | Power | % of Dynamic |
|---|---:|---:|
| Clocks | 0.003 W | 44 % |
| I/O | 0.002 W | 40 % |
| Signals | 0.001 W | 11 % |
| Logic | < 0.001 W | < 4 % |
| DSP | < 0.001 W | < 1 % |

**Power supply rails (dynamic only):**
- Vccint: 0.004 A → ~0.004 W
- Vcco18: 0.001 A → ~0.002 W
- All other rails: negligible dynamic current


---

## 5. Throughput

| Quantity | Value |
|---|---:|
| Peak (steady-state COMPUTE) | **1.000 output pixel / cycle** |
| Frame average (32×32, N=3) | 0.930 output pixel / cycle |
| Peak absolute (at 125 MHz) | 125 Mpix/s |
| Frame-average absolute | 116.3 Mpix/s |
| Peak compute rate | 2.25 GOPS |
| Energy efficiency | 20.45 GOPS/W |

**Frame-average derivation:**

```
Frame cycles = N² + PADDED_HEIGHT × IMAGE_WIDTH + (PIPE_STAGES + 2)
             = 9 + 34 × 32 + 4
             = 1101
Output pixels = 32 × 32 = 1024
Frame average = 1024 / 1101 = 0.930 px/cycle
```

The one-output-per-cycle bonus is implemented and verified: `result_valid_o` is high on every COMPUTE cycle after pipeline fill. The testbench confirms 1024 output words per frame with exactly one `tlast`, no dropped words, and correct data against a golden model with ReLU, input stalls, and output back-pressure.

---

## 6. Figure of Merit

```
FOM = Throughput(px/cycle) / (Power × (LUTs + 50·DSPs + 100·BRAMs))
```

### Using peak throughput (1.000 px/cycle)

```
Numerator   = 1.000
Denominator = Power × 795
```

| Power basis | Denominator | FOM |
|---|---:|---:|
| Total (0.110 W) | 0.110 × 795 = 87.45 | **1.14 × 10⁻²** |
| Dynamic (0.006 W) | 0.006 × 795 = 4.770 | **2.10 × 10⁻¹** |

### Using frame-average throughput (0.930 px/cycle)

| Power basis | FOM |
|---|---:|
| Total (0.110 W) | **1.06 × 10⁻²** |
| Dynamic (0.006 W) | **1.95 × 10⁻¹** |

### Headline FOM

```
FOM = 1 / (0.110 × 795) = 1.14 × 10⁻²
```

Per the competition's Table 1, report the peak-throughput number on total power as the official FOM.

---

## 7. Summary Table (Table 1 Format)

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | ≥ 32×32 | 32×32 | pixels | Grayscale, single-channel |
| Input precision | unsigned fixed-point | 8-bit unsigned | bits | Justified in report |
| Kernel precision | 8-bit signed | 8-bit signed | bits | Programmable via host port |
| Architecture type | — | Pipelined streaming MAC array | — | 9 taps, 2 pipeline stages |
| Multipliers / MACs | N² | 9 | count | 9 × DSP48E1 |
| Pipeline stages | — | 2 | stages | DSP P reg + adder-tree reg |
| Latency (frame) | — | 1101 | cycles | = 8.81 µs at 125 MHz |
| Throughput (peak) | — | 1.000 | output px/cycle | One output per COMPUTE cycle |
| Throughput (frame avg) | — | 0.930 | output px/cycle | 1024/1101 for 32×32 frame |
| FPGA utilization | — | 345 LUTs, 501 FFs, 9 DSPs, 0 BRAMs | — | 0.65 % / 0.47 % / 4.1 % / 0 % |
| Maximum frequency | — | 140.7 | MHz | From WNS = +0.895 ns at 125 MHz constraint |
| Power estimate | — | 0.110 | W | Total on-chip; 0.006 W dynamic + 0.104 W static |
| Verification status | — | PASS | — | Golden model, 6 frames, all matched |
| **FOM** | — | **1.14 × 10⁻²** | (px/cycle)/(W·resource) | Peak throughput, total power |

---

## 8. Prior Entries (for reference)

| Design variant | LUTs | FFs | DSPs | BRAMs | WNS | Total P | FOM (total, peak) |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Current (ReLU, DSP MAC)** | **345** | 501 | 9 | 0 | +0.895 | 0.110 W | **1.14 × 10⁻²** |
| DSP MAC, no ReLU | 179 | 212 | 9 | 0 | +0.746 | 0.112 W | 1.42 × 10⁻² |
| Mirrorless LUT MAC | 1218 | 374 | 0 | 0 | +0.641 | 0.132 W | 6.22 × 10⁻³ |
| Output FIFO + res_mem mirror | 1230 | 387 | 0 | 1 | +0.455 | 0.119 W | 6.32 × 10⁻³ |
| Streaming input (no FIFO) | 1205 | 375 | 0 | 1 | +0.764 | 0.119 W | 6.44 × 10⁻³ |


---