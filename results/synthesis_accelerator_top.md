# Synthesis Results — `accelerator_top` on PYNQ-Z2

Streaming-interface design (PR #15), post-route, 2026-08-29.

## 1. Setup

| Item | Value |
|---|---|
| Design | `accelerator_top` (N=3, 32×32 image, 8-bit unsigned pixels, 8-bit signed coefficients, 16-bit signed outputs) |
| Input interface | Streaming: `pixel_in_i[7:0]` + `pixel_valid_i` (deasserted valid = stall; counters/window hold) |
| Output interface | Streaming `result_o`/`result_valid_o` + output RAM readback (`res_rd_addr_i`/`res_rd_data_o`) |
| Pipeline | `PIPE_STAGES = 2` (streaming input adds no registered read, so 2 register stages align the valid flag with the result data) |
| Device | XC7Z020-CLG400-1 (PYNQ-Z2), speed grade -1 |
| Tool | Vivado 2025.2, batch flow (`scripts/run_synth.tcl`) |
| Flow | synthesis → opt_design → place → route (reports post-route) |
| Constraints | `src/constraints/pynq_z2.xdc` — 125 MHz clock on `clk_i` (pin H16), reset on `rst_n_i` (pin M19) |
| Date | 2026-08-29 (streaming interface + reset-free line buffers) |

Notable design choices since the previous report:

- **Streaming input**: the memory-mapped image load (`img_mem` + double buffering)
  was removed; pixels stream in one per cycle. This is the organizer-required
  mode and also removes the input memory (2 RAMB18 → 1).
- **Stall handling**: `pixel_valid_i` gates `shift_valid_o` and `result_valid_d`
  — a deasserted valid stalls the address counters, line buffers, and window in
  lockstep; no stale results are produced.
- **Reset-free line buffers**: `line_buffer` has no reset (SRLC32E has no reset
  pin); the FILL phase primes the whole buffer before the first output. Saves
  37 FFs and improves timing.
- **`addr_gen_in` → `pixel_counter`**: no longer an address generator; counts
  accepted pixels as the frame-position reference.

## 2. Utilization (post-route)

| Resource | Used | Available | Utilization |
|---|---|---|---|
| LUTs (total) | 1206 | 53 200 | 2.3 % |
| — as logic | 1190 | — | — |
| — as shift registers (line buffers) | 16 | 17 400 | 0.1 % |
| FFs | 372 | 106 400 | 0.3 % |
| Block RAM (RAMB18: output memory only) | 1 | 280 (18 Kb) | 0.4 % |
| DSPs | **0** | 220 | 0 % |

Top consumers: `kernel_reg_bank` 505 LUTs (includes the 9 LUT-based Booth
multipliers, cross-hierarchy), `window_array` 532 (window + line-buffer logic,
cross-hierarchy), `adder_tree` 97. All multipliers are LUT-based (0 DSPs).

## 3. Timing (post-route, 8.0 ns / 125 MHz constraint)

| Metric | Value |
|---|---|
| WNS | **+0.751 ns (MET)** |
| WHS | +0.140 ns (hold met) |
| Critical path | 7.26 ns (logic 2.49 ns / route 4.77 ns) |
| **Fmax** | **≥ 125 MHz** (constraint met; ≈ 138 MHz achievable) |

Timing improved vs the previous report (WNS +0.367 ns) — the reset-free line
buffers removed the FDCE overhead from the SRL chain and simplified the input
path.

## 4. Power (post-route, SAIF-annotated from `tb_accelerator_top`)

| Metric | Value |
|---|---|
| Total on-chip power | **0.119 W** |
| Dynamic | 0.014 W |
| Device static | 0.105 W |
| Confidence | **Medium** |

Switching activity comes from `scripts/run_power_sim.tcl` (batch xsim with
`open_saif`/`log_saif` over the full end-to-end testbench, including the
stall-injection frames → `synth_out/activity.saif`), applied in
`run_synth.tcl` via `read_saif`.

## 5. Figure of Merit

```
FoM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs))
```

- Resource penalty = 1206 + 50·0 + 100·1 = **1306**
- Peak throughput = 1 output/cycle during the block-valid runs = **125 Mpix/s**
- Sustained throughput (within COMPUTE) = 900 outputs / 958 cycles = 0.939
- Average throughput (per frame) = 900 outputs / 1037 cycles × 125 MHz
  ≈ **108.5 Mpix/s**
- MAC rate ≈ 0.98 GMAC/s (average)

| Power basis | FoM |
|---|---|
| Total power (0.119 W) | **6.98 × 10⁵** |
| Dynamic power (0.014 W) | **5.93 × 10⁶** |

vs. the previous memory-mapped design (6.44 × 10⁵): **≈ 1.08× higher FoM**,
and vs. the unpipelined design (62 MHz, penalty 2082, 0.154 W): **≈ 4.2×
higher**.

**Throughput reporting (organizer requirement):** peak and average are both
reported above. Note that `result_valid_o` deasserts for 2 cycles at every
output-row boundary inside COMPUTE (the window needs a row-start pixel whose
column < N−1, so no block completes then). Per the organizers' strict reading
of the one-output-per-cycle bonus, this means the design sustains 0.939
outputs/cycle in COMPUTE — making the stream gap-free would require zero
padding (SAME convolution, 32×32 output) or re-scheduling the output stream;
see Next steps.

## 6. Verification status

- RTL verified end-to-end (`tb_accelerator_top`): golden triple-loop
  convolution model checked against **both** the streaming port and the output
  RAM readback; covers continuous streams, randomized kernels/images, and
  pixel-stream stalls (1–3-cycle `pixel_valid_i` deassertions every 32 pixels).
- Control unit (`tb_conv_fsm`): stall-aware golden reference; directed stall
  test deasserts valid 3 cycles out of every 40 mid-frame.
- All 17 testbenches pass (`./scripts/run_ci.sh`, Icarus Verilog).
- Post-synthesis gate-level netlist check: a 2-output startup discrepancy
  (out[0]/out[1]) seen in the flattened `write_verilog` netlist could not be
  reproduced at RTL and was traced to `write_verilog` name-collision artifacts;
  the in-memory routed netlist connections were verified correct. The RTL
  suite is the trusted check; board-level bring-up is the definitive one.

## 7. Next steps

- **64×64 configuration** (TPG minimum): parameterized RTL; override via
  `-generic` in `run_synth.tcl` and parameterize the TB localparams. Better
  frame efficiency (fill amortized) and satisfies the TPG demo.
- **Gap-free output stream** for the one-output-per-cycle bonus: zero padding
  (SAME convolution → 1024 outputs, one per input pixel) or an output
  re-scheduling scheme.
- Board demo on PYNQ-Z2 (bonus), SoC/AXI-Stream wrapper with Zynq + DMA + TPG.
- Optional bonuses: ReLU/bias, Python golden-reference model.
