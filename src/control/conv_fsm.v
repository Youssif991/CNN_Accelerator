`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Control - Conv FSM
// Module Name: conv_fsm
// Tool Versions: Vivado 2025.2
// Description: Frame controller for the convolution accelerator. Sequences
//              kernel loading (LOAD) and the compute pass (COMPUTE) with one
//              output pixel per cycle, then the done handoff. The kernel load
//              is host-paced: LOAD advances one coefficient per
//              kernel_wr_valid_i pulse, across all N_Kernel kernels back
//              to back. The pixel stream is gated by pixel_valid_i: a
//              deasserted valid stalls the shift (window delay bank and
//              address counter all hold), so the pipeline stays synchronized
//              under stalls. Outputs are Moore (state-derived); result_valid_o
//              is registered to align with the window that is presented one
//              cycle after its last pixel arrives.
//
//              IMAGE_HEIGHT here is the *padded* row count (real image rows
//              plus the pixel_pad_inserter's leading and trailing zero rows):
//              the caller (accelerator_top) binds it to IMAGE_HEIGHT_real + N.
//              row_buffer_bank centres the NxN window on real row w - N while
//              padded row w is being written, so a result is valid from padded
//              row N onwards; that single row gate suppresses the (one-time,
//              not periodic) padding prefix, and the bank's own row-border tap
//              muxes already give every column its horizontal zero padding.
//              There is therefore no column gate and no FILL state: LOAD
//              transitions straight into COMPUTE.
//
//              Multiple kernels (N_Kernel > 1): once a pass's pipeline has
//              fully drained (the same exit_cnt countdown used for the
//              single-kernel case), the FSM either finishes (S_DONE) if this
//              was the last kernel, or loops back for the next kernel without
//              leaving S_COMPUTE. Looping re-issues the same stream_start_o /
//              rst_count_o pulses that originally armed pixel_pad_inserter and
//              reset pixel_counter for pass 0, so every pass looks identical
//              to row_buffer_bank/mac_chain/pixel_counter downstream; the
//              caller (accelerator_top) is responsible for replaying the same
//              image into pixel_pad_inserter on every pass after the first
//              (see frame_buffer). kernel_idx_o tells the caller which
//              kernel's taps to select and which output channel the pass's
//              results belong to.
//
// Dependencies: none (drives the datapath and pixel_pad_inserter)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Added column gate to block_valid (fix row-boundary
//                  wraparound window bug)
// Revision 0.03 - Removed the column gate and the FILL state: IMAGE_HEIGHT
//                  now denotes the padded row count, block_valid is a
//                  row-only check, and row padding + the window's row-start
//                  flush give a gap-free, zero-padded stream for free. Added
//                  row_start_o (drives window_array's flush) and
//                  stream_start_o (a one-cycle pulse on the LOAD->COMPUTE
//                  transition, used to arm pixel_pad_inserter for the frame).
// Revision 0.04 - Repointed at row_buffer_bank, which centres the window on the
//                  output pixel: the padded stream is now IMAGE_HEIGHT_real + N
//                  rows long and block_valid opens at padded row N. Because the
//                  bank derives its border zeroing from the pixel column,
//                  row_start_o is gone and no row_end_o was added.
// Revision 0.05 - Added N_Kernel: LOAD now loads N_Kernel*N*N
//                  coefficients, and S_COMPUTE loops per-kernel (kernel_idx_o,
//                  replay_o) instead of always exiting to S_DONE after one
//                  pass.
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module conv_fsm #(
    parameter N = 3,  // Kernel size (N >= 2)
    parameter IMAGE_WIDTH = 32,  // Input feature-map width
    parameter IMAGE_HEIGHT = 32,  // Padded row count (real rows + (N-1)/2 leading + (N+1)/2 trailing pad rows)
    parameter COEFF_WIDTH = 8,  // Kernel coefficient width
    parameter PIPE_STAGES = 0,  // Datapath pipeline delay (stages after the window)
    parameter PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT),
    parameter STATE_WIDTH = 2,  // State encoding width
    parameter N_Kernel = 1   // Number of kernels / output channels per job
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire start_i,  // Frame start request
    input wire pixel_valid_i,  // Input pixel valid (deasserted = stall)
    input wire output_stall_i,  // Output consumer stalled (freeze the accept)
    input wire kernel_wr_valid_i,  // Kernel coefficient write valid (host-paced)
    input wire [COEFF_WIDTH-1:0] kernel_data_i,  // Kernel coefficient data in
    input wire [PIX_ADDR_WIDTH-1:0] pix_addr_i,  // Current input pixel index
    input wire pix_last_i,  // Last input pixel is being presented
    output wire kernel_we_o,  // Kernel load write enable
    output wire [$clog2(N_Kernel*N*N)-1:0] kernel_addr_o,  // Kernel load address (flat, across all kernels)
    output wire shift_valid_o,  // Shift the row buffers and advance the pixel counter
    output wire stream_start_o,  // One-cycle pulse on every pass start: (re)arms pixel_pad_inserter
    output wire ready_o,  // Accepting input pixels (COMPUTE, ungated)
    output wire result_valid_o,  // Output pixel valid (pipeline aligned)
    output wire rst_count_o,  // Reset the address-generator counters
    output wire busy_o,  // Job in progress (spans every kernel's pass)
    output wire done_o,  // Job complete (all kernels done)
    output wire [STATE_WIDTH-1:0] state_o,  // Current state (observability)
    output wire [(N_Kernel>1 ? $clog2(N_Kernel) : 1)-1:0] kernel_idx_o,  // Current pass's kernel/channel index
    output wire replay_o  // High while this pass replays a stored frame (kernel_idx_o != 0)
);

    localparam KIDX_WIDTH  = (N_Kernel > 1) ? $clog2(N_Kernel) : 1;
    localparam TOTAL_TAPS  = N_Kernel * N * N;

    // State encoding
    localparam S_IDLE = 0;
    localparam S_LOAD = 1;
    localparam S_COMPUTE = 2;
    localparam S_DONE = 3;

    // Current state
    reg [STATE_WIDTH-1:0] state_q;
    // Next state
    reg [STATE_WIDTH-1:0] state_d;
    // Kernel load index (current, flat across all kernels)
    reg [$clog2(TOTAL_TAPS)-1:0] load_cnt_q;
    // Kernel load index (next)
    reg [$clog2(TOTAL_TAPS)-1:0] load_cnt_d;
    // Compute-exit countdown (current)
    reg [$clog2(PIPE_STAGES+3)-1:0] exit_cnt_q;
    // Compute-exit countdown (next)
    reg [$clog2(PIPE_STAGES+3)-1:0] exit_cnt_d;
    // Result valid (current, pipeline aligned)
    reg result_valid_q;
    // Result valid (next)
    reg result_valid_d;
    // Current pass's kernel/channel index (current)
    reg [KIDX_WIDTH-1:0] kernel_idx_q;
    // Current pass's kernel/channel index (next)
    reg [KIDX_WIDTH-1:0] kernel_idx_d;

    // Row of the current input pixel (padded coordinate system)
    wire [PIX_ADDR_WIDTH-1:0] pix_row = pix_addr_i / IMAGE_WIDTH;

    // A result is valid once the centred window has N complete padded rows of
    // history behind it, i.e. from padded row N onwards (row_buffer_bank
    // presents real row w-N while padded row w is written).
    wire block_valid = (pix_row >= N);

    // The last cycle of LOAD (about to move to COMPUTE): arms the pad inserter
    // for pass 0.
    wire load_done = (state_q == S_LOAD) && kernel_wr_valid_i && (load_cnt_q == TOTAL_TAPS-1);

    // The last cycle of a pass's pipeline drain, with more kernels left to go:
    // arms the pad inserter for the NEXT pass without leaving S_COMPUTE.
    wire pass_advance = (state_q == S_COMPUTE) && !output_stall_i &&
                         (exit_cnt_q == 1) && (kernel_idx_q != N_Kernel-1);

    // Next-state
    always @(*) begin : next_state
        state_d = state_q;
        load_cnt_d = load_cnt_q;
        exit_cnt_d = exit_cnt_q;
        result_valid_d = 1'b0;
        kernel_idx_d = kernel_idx_q;

        case (state_q)
            // Wait for a frame-start request
            S_IDLE: begin
                if (start_i) begin
                    state_d = S_LOAD;
                    kernel_idx_d = {KIDX_WIDTH{1'b0}};
                end
            end
            // Load the N_Kernel*N*N kernel coefficients, one per host write
            S_LOAD: begin
                if (kernel_wr_valid_i) begin
                    load_cnt_d = (load_cnt_q == TOTAL_TAPS-1) ? 0 : load_cnt_q + 1;
                    if (load_cnt_q == TOTAL_TAPS-1) state_d = S_COMPUTE;
                end
            end
            // Shift the padded stream and produce one output pixel per cycle,
            // once per kernel.
            S_COMPUTE: begin
                if (output_stall_i) begin
                    result_valid_d = result_valid_q;
                end else begin
                    result_valid_d = block_valid && pixel_valid_i;
                    if (pix_last_i && pixel_valid_i) begin
                        exit_cnt_d = PIPE_STAGES + 2;
                    end else if (exit_cnt_q > 0) begin
                        exit_cnt_d = exit_cnt_q - 1;
                        if (exit_cnt_q == 1) begin
                            if (kernel_idx_q == N_Kernel-1) begin
                                state_d = S_DONE;  // Last kernel's pass drained: job done
                            end else begin
                                kernel_idx_d = kernel_idx_q + 1'b1;  // Loop for the next kernel
                            end
                        end
                    end
                end
            end
            // Hold the done flag, then re-arm for the next frame
            S_DONE: state_d = S_IDLE;
            default: state_d = S_IDLE;
        endcase
    end

    // State update
    always @(posedge clk_i or negedge rst_n_i) begin : state
        if (!rst_n_i) begin
            state_q <= S_IDLE;
            load_cnt_q <= 0;
            exit_cnt_q <= 0;
            result_valid_q <= 1'b0;
            kernel_idx_q <= 0;
        end else begin
            state_q <= state_d;
            load_cnt_q <= load_cnt_d;
            exit_cnt_q <= exit_cnt_d;
            result_valid_q <= result_valid_d;
            kernel_idx_q <= kernel_idx_d;
        end
    end

    // Output decode (Moore, except stream_start_o/load_done/pass_advance which
    // are Mealy pulses on the LOAD->COMPUTE and per-kernel pass transitions)
    assign kernel_we_o = (state_q == S_LOAD);
    assign kernel_addr_o = load_cnt_q;
    assign shift_valid_o = (state_q == S_COMPUTE) && pixel_valid_i && !output_stall_i;
    assign stream_start_o = load_done || pass_advance;
    assign ready_o = (state_q == S_COMPUTE) && !output_stall_i;
    assign result_valid_o = result_valid_q;
    assign rst_count_o = (state_q == S_LOAD) || pass_advance;
    assign busy_o = (state_q == S_LOAD) || (state_q == S_COMPUTE);
    assign done_o = (state_q == S_DONE);
    assign state_o = state_q;
    assign kernel_idx_o = kernel_idx_q;
    assign replay_o = (kernel_idx_q != {KIDX_WIDTH{1'b0}});

endmodule
