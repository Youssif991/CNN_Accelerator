# Synthesis & Implementation Results — accelerator_top

- **Design:** CNN convolution accelerator, $N=3$, $32 \times 32$ image
- **Target:** PYNQ-Z2 (XC7Z020-CLG400-1)
- **Tool:** Vivado 2025.1 (`scripts/run_synth.tcl`, `scripts/run_power_sim.tcl`)
- **Date:** 2026-09-25
- **Design state:** Routed (post-implementation)

---

## 1. Configuration

| Parameter | Value |
| :--- | :--- |
| **Kernel size ($N$)** | 3 |
| **Input image** | $32 \times 32$, 8-bit unsigned |
| **Kernel coefficients** | 8-bit signed, programmable |
| **Output precision** | 16-bit signed |
| **Padding** | 1 zero row before, 2 after (`PADDED_HEIGHT` = 35) |
| **Window** | Centred, `row_buffer_bank` |
| **MAC** | $9 \times \text{DSP48E1}$, `mac_chain` |
| **Pipeline stages** | 11 |
| **Rounding / rescale** | Round-half-up, `FRAC_BITS` = 4 |
| **Activation** | Optional ReLU |
| **Input interface** | Streaming, 1 pixel/cycle, `pixel_valid_i` / `ready_o` |
| **Output interface** | FWFT FIFO, $16 \times 17$ bit, `result_valid_o` / `result_tlast_o` / `result_ready_i` |
| **Clock / reset** | 166.67 MHz (6.000 ns), pin H16 / pin M19 |
| **Power activity capture** | No SAIF supplied for this run (vectorless estimate) |

---

## 2. Utilization (Post-Route)

| Resource | Used | Available | Utilization |
| :--- | :--- | :--- | :--- |
| **Slice LUTs** | 370 | 53 200 | 0.70 % |
| — *LUT as Logic* | 287 | 53 200 | 0.54 % |
| — *LUT as Distributed RAM* | 48 | 17 400 | 0.28 % |
| — *LUT as Shift Register* | 35 | 17 400 | 0.20 % |
| **Slice Registers (FFs)** | 626 | 106 400 | 0.59 % |
| **DSP48E1** | 9 | 220 | 4.09 % |
| **Block RAM Tiles** | 0.5 | 140 | 0.36 % |
| **F7 Muxes / F8 Muxes** | 36 / 18 | 26 600 / 13 300 | 0.14 % |
| **Unique Control Sets** | 41 | 13 300 | 0.31 % |
| **Bonded IOB** | 47 | 125 | 37.60 % |

| Instance | LUTs | FFs |
| :--- | :--- | :--- |
| `u_row_buffer_bank` | 81 (33 logic + 48 distributed RAM) | 12 |
| `u_out_fifo` | 9 | 128 |
| `u_kernel_reg_bank` | 0 | 72 |
| `u_mac_chain` | 34 (shift-register LUTs) | 9 × DSP48E1 |

> **Note:** Per-instance LUT/FF breakdown is not present in the new reports (only aggregate totals and a partial power-by-hierarchy table were supplied), so this sub-table still reflects the prior run and has not been updated.

$$\text{Penalty} = \text{LUTs} + 50 \cdot \text{DSPs} + 100 \cdot \text{BRAMs} = 370 + 50(9) + 100(0.5) = 870$$

---

## 3. Timing (Post-Route, 6.000 ns constraint)

| Metric | Value |
| :--- | :--- |
| **Setup WNS** | **+0.404 ns** (MET) |
| **Setup TNS** | 0.000 ns |
| **Setup failing endpoints** | 0 / 2362 |
| **Hold WHS** | **+0.044 ns** (MET) |
| **Hold THS** | 0.000 ns |
| **Hold failing endpoints** | 0 / 2362 |
| **Pulse-width slack (WPWS)** | **+1.750 ns** (MET) |
| **Pulse-width failing endpoints** | 0 / 753 |
| **$F_{\max}$ (from WNS)** | **178.7 MHz** ($T_{\min} = 6.000\text{ ns} - 0.404\text{ ns} = 5.596\text{ ns}$) |
| **Clock uncertainty** | 0.035 ns |
| **DSP48E1 minimum period** | 2.154 ns |

### Worst Setup Path
- **Source:** `u_kernel_reg_bank/kernel_q_reg[0][6]/C`
- **Destination:** `u_mac_chain/gen_tap[0].product/B[6]` (DSP48E1)
- **Data path delay:** 1.314 ns (logic 0.478 ns, route 0.836 ns)
- **Logic levels:** 0
- **Clock path skew:** +0.064 ns
- **Slack:** +0.404 ns

---

## 4. Power (Post-Route)

| Metric | Value |
| :--- | :--- |
| **Total on-chip power** | **0.124 W** |
| — *Dynamic* | 0.019 W (15 %) |
| — *Device static* | 0.105 W (85 %) |
| **Confidence level** | Low |
| **Activity file** | None supplied (Simulation Activity File: ---) |
| **Design nets matched** | N/A |
| **Junction temperature** | $26.4^\circ\text{C}$ |

### Dynamic Breakdown
| Power Component | Share | Percentage |
| :--- | :--- | :--- |
| **DSP** | 0.009 W | 47 % |
| **Signals** | 0.004 W | 21 % |
| **Clocks** | 0.003 W | 16 % |
| **I/O** | 0.001 W | 5 % |
| **Slice Logic** | 0.001 W | 5 % |
| **Block RAM** | $< 0.001\text{ W}$ | $< 5\%$ |

> **Note on this power run:** No SAIF/simulation activity file was supplied this time (previously a SAIF captured at 125 MHz gave "Medium" confidence with 15 % of nets matched; this run has no activity file, "Low" confidence, and nets-matched is not applicable). Confidence on I/O and internal-node activity is explicitly flagged Low/Medium by the tool. Treat this power figure as a vectorless estimate, and consider re-running with a SAIF captured at the actual 6.000 ns operating point for a higher-confidence number.

---

## 5. Throughput

Per-cycle figures are unchanged (they depend only on cycle counts, not clock frequency). Absolute rates, compute rate, and energy efficiency have been recomputed for the actual 6.000 ns (166.67 MHz) operating point and $F_{\max}$ (178.7 MHz) using the updated 0.124 W total power figure.

| Quantity | Value |
| :--- | :--- |
| **Peak (steady-state COMPUTE)** | 1.000 output pixel / cycle |
| **Frame average ($32 \times 32$)** | 0.897 output pixel / cycle |
| **Peak absolute (at 166.67 MHz)** | 166.7 Mpix/s |
| **Peak absolute (at $F_{\max} = 178.7\text{ MHz}$)** | 178.7 Mpix/s |
| **Peak compute rate (at 166.67 MHz)** | 3.00 GOPS |
| **Peak compute rate (at $F_{\max} = 178.7\text{ MHz}$)** | 3.22 GOPS |
| **Energy efficiency** | 24.2 GOPS/W (based on 0.124 W total power at 166.67 MHz) |

$$\text{Frame cycles} = 9 + 35 \times 32 + 13 = 1142$$

$$\text{Frame average} = \frac{1024}{1142} = 0.897\text{ px/cycle}$$

---

## 6. Figure of Merit

$$\text{FOM} = \frac{\text{Throughput (px/cycle)}}{\text{Power} \times (\text{LUTs} + 50 \cdot \text{DSPs} + 100 \cdot \text{BRAMs})}$$

| Throughput | Power Basis | Denominator | FOM |
| :--- | :--- | :--- | :--- |
| **Peak 1.000** | Total 0.124 W | 107.88 | $9.27 \times 10^{-3}$ |
| **Peak 1.000** | Dynamic 0.019 W | 16.53 | $6.05 \times 10^{-2}$ |
| **Frame avg 0.897** | Total 0.124 W | 107.88 | $8.31 \times 10^{-3}$ |

$$\text{Headline FOM} = \frac{1}{0.124 \times 870} = 9.27 \times 10^{-3}$$

FOM dropped from $1.10 \times 10^{-2}$ to $9.27 \times 10^{-3}$ versus the previous run, driven by the higher Penalty (870 vs 780, from LUTs 330 $\rightarrow$ 370 and the newly reported 0.5 BRAM tile) and higher total power (0.117 W $\rightarrow$ 0.124 W). Note FOM is independent of clock frequency (it's defined in px/cycle), so timing changes don't affect this figure — the drop is purely a resource/power change. Given the missing-activity-file caveat in §4, confirm this isn't an artifact of the low-confidence vectorless power estimate before treating it as a real regression.