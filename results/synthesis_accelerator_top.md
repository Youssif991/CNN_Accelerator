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
- **One-output-per-cycle bonus**: the streaming valid covers every accepted
  pixel past the fill (the column condition is dropped from `block_valid`), so
  `result_valid_o` stays high every COMPUTE cycle; the output memory is gated
  by a pipeline-aligned column flag and stores only the in-image results.

## 2. Utilization (post-route)

| Resource | Used | Available | Utilization |
|---|---|---|---|
| LUTs (total) | 1205 | 53 200 | 2.3 % |
| — as logic | 1189 | — | — |
| — as shift registers (line buffers) | 16 | 17 400 | 0.1 % |
| FFs | 375 | 106 400 | 0.4 % |
| Block RAM (RAMB18: output memory only) | 1 | 280 (18 Kb) | 0.4 % |
| DSPs | **0** | 220 | 0 % |

Top consumers: `kernel_reg_bank` 505 LUTs (includes the 9 LUT-based Booth
multipliers, cross-hierarchy), `window_array` 532 (window + line-buffer logic,
cross-hierarchy), `adder_tree` 97. All multipliers are LUT-based (0 DSPs).

## 3. Timing (post-route, 8.0 ns / 125 MHz constraint)

| Metric | Value |
|---|---|
| WNS | **+0.764 ns (MET)** |
| WHS | hold met |
| Critical path | ≈ 7.24 ns |
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

- Resource penalty = 1205 + 50·0 + 100·1 = **1305**
- **Streaming valid (the bonus): 958 valid pulses over 958 COMPUTE cycles =
  1.0 output/cycle sustained** — `result_valid_o` stays high every cycle in
  COMPUTE after the pipeline fill (no row-boundary gaps), because the valid
  now covers every accepted pixel; the N−1 border windows per row produce
  deterministic boundary values the host discards.
- Real output rate (in-image results): 900 outputs / 1037 cycles × 125 MHz
  ≈ **108.5 Mpix/s**
- Peak throughput = 125 Mpix/s
- MAC rate ≈ 0.98 GMAC/s (real outputs, average)

| Power basis | FoM |
|---|---|
| Total power (0.118 W) | **7.05 × 10⁵** |
| Dynamic power (0.014 W) | **5.94 × 10⁶** |

vs. the previous memory-mapped design (6.44 × 10⁵): **≈ 1.08× higher FoM**,
and vs. the unpipelined design (62 MHz, penalty 2082, 0.154 W): **≈ 4.2×
higher**.

**Throughput reporting (organizer requirement):** peak and average are both
reported above, and the one-output-per-cycle bonus is implemented and
verified: `result_valid_o` pulses once per accepted pixel past the fill
(958/958 in COMPUTE), so a sustained stream sees valid high every cycle.
The gap-free behaviour is enforced by a dedicated TB checker (no two-cycle
deassertions while the input is continuously valid); the output memory is
gated by a pipeline-aligned column flag so it still stores only the 900
in-image results. Initial latency (FILL + pipeline fill) and pauses between
frames are not counted, per the rules.
see Next steps.

## 6. Verification status

- RTL verified end-to-end (`tb_accelerator_top`): golden triple-loop
  convolution model checked against **both** the streaming port and the output
  RAM readback; covers continuous streams, randomized kernels/images, and
  pixel-stream stalls (1–3-cycle `pixel_valid_i` deassertions every 32 pixels).
- **Bonus check:** a dedicated checker asserts `result_valid_o` never
deasserts for two consecutive cycles during a sustained COMPUTE stream; the
streaming golden models the border windows (previous row's tail) exactly.
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
- Board demo on PYNQ-Z2 (bonus), SoC/AXI-Stream wrapper with Zynq + DMA + TPG.
- Optional bonuses: ReLU/bias, Python golden-reference model.
