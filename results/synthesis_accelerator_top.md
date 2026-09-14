# Synthesis & Implementation Results — `accelerator_top`

**Design:** CNN convolution accelerator, N=3, 32×32 image
**Target:** PYNQ-Z2 (XC7Z020-CLG400-1)
**Tool:** Vivado 2025.2 (`scripts/run_synth.tcl`, `scripts/run_power_sim.tcl`)
**Date:** 2026-09-14
**Design state:** Routed (post-implementation)

## 1. Configuration

| Parameter | Value |
|---|---|
| Kernel size (N) | 3 |
| Input image | 32 × 32, 8-bit unsigned |
| Kernel coefficients | 8-bit signed, programmable |
| Output precision | 16-bit signed |
| Padding | 1 zero row before, 2 after (`PADDED_HEIGHT` = 35) |
| Window | Centred, `row_buffer_bank` |
| MAC | 9 × DSP48E1, `mac_chain` |
| Pipeline stages | 11 |
| Rounding / rescale | Round-half-up, `FRAC_BITS` = 4 |
| Activation | Optional ReLU |
| Input interface | Streaming, 1 pixel/cycle, `pixel_valid_i` / `ready_o` |
| Output interface | FWFT FIFO, 16 × 17 bit, `result_valid_o` / `result_tlast_o` / `result_ready_i` |
| Clock / reset | 125 MHz (8.000 ns), pin H16 / pin M19 |
| Power activity capture | SAIF at 125 MHz, matching the constraint |

## 2. Utilization (Post-Route)

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 330 | 53 200 | 0.62 % |
| — LUT as Logic | 248 | 53 200 | 0.47 % |
| — LUT as Distributed RAM | 48 | 17 400 | 0.28 % |
| — LUT as Shift Register | 34 | 17 400 | 0.20 % |
| Slice Registers (FFs) | 587 | 106 400 | 0.55 % |
| DSP48E1 | 9 | 220 | 4.09 % |
| Block RAM Tiles | 0 | 140 | 0.00 % |
| F7 Muxes / F8 Muxes | 34 / 17 | 26 600 / 13 300 | 0.13 % |
| Unique Control Sets | 39 | 13 300 | 0.29 % |
| Bonded IOB | 46 | 125 | 36.80 % |

| Instance | LUTs | FFs |
|---|---:|---:|
| `u_row_buffer_bank` | 81 (33 logic + 48 distributed RAM) | 122 |
| `u_out_fifo` | 91 | 283 |
| `u_kernel_reg_bank` | 0 | 72 |
| `u_mac_chain` | 34 (shift-register LUTs) | — |
| 9 × DSP48E1 | 0 | — |

```
Penalty = LUTs + 50·DSPs + 100·BRAMs = 330 + 450 + 0 = 780
```

## 3. Timing (Post-Route, 8.000 ns constraint)

| Metric | Value |
|---|---:|
| Setup WNS | +3.006 ns (MET) |
| Setup TNS | 0.000 ns |
| Setup failing endpoints | 0 / 2271 |
| Hold WHS | +0.054 ns (MET) |
| Hold THS | 0.000 ns |
| Hold failing endpoints | 0 / 2271 |
| Pulse-width slack | +2.750 ns (MET) |
| Pulse-width failing endpoints | 0 / 711 |
| Fmax (from WNS) | 200.3 MHz |
| Clock uncertainty | 0.035 ns |
| DSP48E1 minimum period | 2.154 ns |

| Worst setup path | |
|---|---|
| Source | `u_kernel_reg_bank/kernel_q_reg[0][6]/C` |
| Destination | `u_mac_chain/gen_tap[0].product/B[6]` (DSP48E1) |
| Data path delay | 1.314 ns (logic 0.478 ns, route 0.836 ns) |
| Logic levels | 0 |
| Clock path skew | +0.064 ns |
| Slack | +3.006 ns |

## 4. Power (Post-Route, SAIF-Annotated)

| Metric | Value |
|---|---:|
| Total on-chip power | 0.117 W |
| Dynamic | 0.013 W (11 %) |
| Device static | 0.105 W (89 %) |
| Confidence level | Medium |
| Activity file | `synth_out/activity.saif` (captured at 125 MHz) |
| Design nets matched | 15 % (200 / 1363) |
| Junction temperature | 26.4 °C |

| Dynamic breakdown | Power | Share |
|---|---:|---:|
| I/O | 0.006 W | 46 % |
| Clocks | 0.003 W | 23 % |
| Signals | 0.002 W | 15 % |
| DSP | 0.001 W | 8 % |
| Logic | < 0.001 W | < 4 % |

## 5. Throughput

| Quantity | Value |
|---|---:|
| Peak (steady-state COMPUTE) | 1.000 output pixel / cycle |
| Frame average (32×32) | 0.897 output pixel / cycle |
| Peak absolute (at 125 MHz) | 125 Mpix/s |
| Peak compute rate | 2.25 GOPS |
| Energy efficiency | 19.2 GOPS/W |

```
Frame cycles = 9 + 35 × 32 + 13 = 1142
Frame average = 1024 / 1142 = 0.897 px/cycle
```

## 6. Figure of Merit

```
FOM = Throughput(px/cycle) / (Power × (LUTs + 50·DSPs + 100·BRAMs))
```

| Throughput | Power basis | Denominator | FOM |
|---|---|---:|---:|
| Peak 1.000 | Total 0.117 W | 91.26 | 1.10 × 10⁻² |
| Peak 1.000 | Dynamic 0.013 W | 10.14 | 9.86 × 10⁻² |
| Frame avg 0.897 | Total 0.117 W | 91.26 | 9.83 × 10⁻³ |

```
Headline FOM = 1 / (0.117 × 780) = 1.10 × 10⁻²
```

## 7. Variant Comparison

| Metric | Trailing window, LUT adder tree | Centred window, LUT adder tree | Centred window, DSP chain |
|---|---:|---:|---:|
| LUTs | 345 | 393 | 330 |
| FFs | 501 | 642 | 587 |
| DSP48E1 | 9 | 9 | 9 |
| Block RAMs | 0 | 0 | 0 |
| Penalty | 795 | 843 | 780 |
| WNS @ 8.000 ns | +0.895 ns | +2.735 ns | +3.006 ns |
| Fmax | 140.7 MHz | 190.0 MHz | 200.3 MHz |
| Total power | 0.110 W | 0.111 W | 0.117 W |
| Output geometry | centred image shifted by (+1, +1) | centred, no shift | centred, no shift |
| Sustained output / cycle | 1.000 | 1.000 | 1.000 |
| FOM (peak, total power) | 1.14 × 10⁻² | 1.07 × 10⁻² | 1.10 × 10⁻² |

The two LUT-adder-tree variants were measured with an activity file captured at
50 MHz; only the DSP-chain column reflects the 125 MHz capture. Their power and
FOM are therefore not directly comparable. Resource and timing columns are
unaffected.