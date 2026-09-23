`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Accelerator - Top Level
// Module Name: accelerator_top
// Tool Versions: Vivado 2025.2
// Description: Top level of the convolution accelerator. A host loads the NxN
//              kernel (one coefficient per kernel_wr_valid_i pulse), pulses
//              start_i, then streams one 8-bit pixel per cycle; the accelerator
//              answers with one 16-bit output word per accepted pixel through a
//              FWFT output FIFO. pixel_pad_inserter writes the vertical zero
//              padding as real rows and row_buffer_bank presents a centred NxN
//              window, so the result is an exact same-size centred convolution
//              with no gap in the output valid stream.
//
//              Pipeline: PIPE_STAGES = 11
//                Stages 1-9: mac_chain's per-tap DSP48E1 multiply-adders
//                Stage 10: sat_round_unit rescaled-sum register
//                Stage 11: sat_round_unit saturated-result register
//              conv_fsm's result_valid_o is registered, so it asserts exactly on
//              the cycle row_buffer_bank presents the completed window; the
//              tag pipeline (see result_tag_pipeline) is PIPE_STAGES deep to
//              stay aligned with the result. The FSM's drain counter uses
//              PIPE_STAGES + 2.
//
//              The pipeline freezes on output_fifo's registered high-water flag
//              (fifo_almost_full) rather than on its exact ready signal: the
//              exact-ready comparator hangs off the read pointer and the freeze
//              net fans out to every clock enable, so it was the critical path.
//              The (* max_fanout = 40 *) attribute stays attached to
//              fifo_almost_full itself, right where it fans out, and the guard
//              band inside output_fifo absorbs the flag's one cycle of
//              staleness (output_fifo still gates the write on exact
//              readiness). See README.md (Design notes).
//
//              Multiple kernels (N_Kernel > 1): the host still streams the
//              image exactly once, on pass 0 (kernel 0). frame_buffer captures
//              every accepted real pixel during that live pass; conv_fsm then
//              loops S_COMPUTE for kernels 1..N_Kernel-1, and for those passes
//              pixel_source_mux feeds pixel_pad_inserter from frame_buffer
//              instead of the host's pixel_in_i/pixel_valid_i (replay is
//              always "valid" - the data is already in on-chip memory) and
//              gates ready_o off so the host never re-sends the frame. Each
//              output word is tagged with result_kernel_idx_o, its source
//              kernel's index, carried through the pipeline by
//              result_tag_pipeline alongside last_p/result_valid_p.
//
//              This module is structural only: every behavioural block that
//              used to live directly in accelerator_top (the live/replay
//              pixel mux + frame_buffer enables + host-ready gating, the
//              last/kidx/valid pipeline shift registers, the pix_col
//              arithmetic, and the output-word field unpack) has been moved
//              into its own leaf module below and is only instantiated here.
//              No functional change versus the previous revision - see each
//              new leaf module's header for exactly what was extracted from
//              where.
//
// Dependencies: pixel_source_mux    (src/control/pixel_source_mux.v)
//               pixel_pad_inserter (src/datapath/pixel_pad_inserter.v)
//               conv_fsm            (src/control/conv_fsm.v)
//               pixel_counter       (src/control/pixel_counter.v)
//               pixel_col_calc      (src/datapath/pixel_col_calc.v)
//               row_buffer_bank     (src/datapath/row_buffer_bank.v)
//               kernel_reg_bank     (src/datapath/kernel_reg_bank.v)
//               frame_buffer        (src/datapath/frame_buffer.v)
//               mac_chain           (src/datapath/mac_chain.v)
//               output_fifo         (src/datapath/output_fifo.v)
//               result_tag_pipeline (src/control/result_tag_pipeline.v)
//               result_field_unpack (src/datapath/result_field_unpack.v)
//               sat_round_unit      (src/datapath/sat_round_unit.v)
//
// Revision:
//   0.01 - File Created.
//   0.02 - Added N_Kernel: multiple output channels via a replayed pass
//          per kernel, fed by a new internal frame_buffer.
//   0.03 - Structural refactor only (no functional change): moved every
//          behavioural block that lived directly in this module (pixel
//          source mux + frame_buffer enables + host-ready gating, the
//          last/kidx/valid tag pipeline, pix_col arithmetic, output-word
//          field unpack) into new leaf modules, instantiated here.
//////////////////////////////////////////////////////////////////////////////////

module accelerator_top #(
    parameter N = 3,  // Kernel size (N >= 2)
    parameter N_Kernel = 1,  // Number of kernels / output channels per job
    parameter IMAGE_WIDTH = 32,  // Input feature-map width
    parameter IMAGE_HEIGHT = 32,  // Input feature-map height (real rows)
    parameter PIXEL_WIDTH = 8,  // Input pixel width (unsigned)
    parameter COEFF_WIDTH = 8,  // Kernel coefficient width (signed)
    parameter OUT_WIDTH = 16,  // Output pixel width (signed)
    parameter ROUND_ENABLE = 1,  // Round-half-up before truncation
    parameter FRAC_BITS    = 4,   // number of fractional bits in the fixed-point kernel
    parameter PIPE_STAGES = 11,  // mac_chain's 9 DSP multiply-adders + sat_round's 2 stages
    parameter PAD_ROWS_BEFORE = (N - 1) / 2,  // Zero rows prepended for top-edge same-padding
    parameter PAD_ROWS_AFTER = (N + 1) / 2,  // Zero rows appended so the last rows still complete
    parameter PADDED_HEIGHT = IMAGE_HEIGHT + N,  // Padded row count (real rows + N pad rows)
    parameter PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * PADDED_HEIGHT),
    parameter PROD_WIDTH = PIXEL_WIDTH + COEFF_WIDTH + 2,
    parameter SUM_WIDTH = PROD_WIDTH + $clog2(N*N)
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire start_i,  // Frame start pulse
    input wire [PIXEL_WIDTH-1:0] pixel_in_i,  // Streaming input pixel data
    input wire pixel_valid_i,  // Pixel valid (deasserted = stall)
    input wire kernel_wr_valid_i,  // Kernel coefficient write valid (host-paced)
    input wire [COEFF_WIDTH-1:0] kernel_wr_data_i,  // Kernel coefficient data
    input wire relu_en_i,  // ReLU enable (host-set per frame)
    output wire busy_o,  // Job in progress (spans every kernel's pass)
    output wire done_o,  // Job complete (all kernels done)
    output wire [1:0] state_o,  // FSM state (observability)
    output wire result_valid_o,  // Output word available (FIFO not empty)
    output wire [OUT_WIDTH-1:0] result_o,  // Output data (FIFO read)
    output wire [(N_Kernel>1 ? $clog2(N_Kernel) : 1)-1:0] result_kernel_idx_o,  // Source kernel/channel of result_o
    output wire result_tlast_o,  // Last output word of the current kernel's pass
    input wire result_ready_i,  // Output ready
    output wire ready_o  // Accepting input pixels (AXI-Stream TREADY); only asserts on the live pass
);

    localparam KIDX_WIDTH = (N_Kernel > 1) ? $clog2(N_Kernel) : 1;

    // Control-unit interconnect
    wire [PIX_ADDR_WIDTH-1:0] pix_addr;
    wire pix_last;
    wire kernel_we;
    wire [$clog2(N_Kernel*N*N)-1:0] kernel_addr;
    wire shift_valid;
    wire stream_start;  // One-cycle pulse: (re)arms pixel_pad_inserter for the current pass
    wire fsm_ready;  // conv_fsm's own readiness (gates the pad inserter)
    wire result_valid;
    wire rst_count;
    wire [KIDX_WIDTH-1:0] kernel_idx;  // Current pass's kernel/channel index
    wire replay_pass;  // High while the current pass replays frame_buffer (kernel_idx != 0)

    // Pad-inserter interconnect
    wire [PIXEL_WIDTH-1:0] padded_pixel;
    wire padded_pixel_valid;
    wire pad_ready;  // pixel_pad_inserter's own ready, ungated by live/replay

    // Multi-kernel pixel source mux interconnect
    wire [PIXEL_WIDTH-1:0] fb_rd_data;
    wire [PIXEL_WIDTH-1:0] pad_inserter_pixel_in;
    wire                   pad_inserter_pixel_valid;
    wire                   fb_wr_en;  // accepted a real host pixel (live pass capture)
    wire                   fb_rd_en;  // consumed a replay pixel

    // Datapath interconnect
    wire [$clog2(IMAGE_WIDTH)-1:0] pix_col;  // Column of the pixel being presented
    wire [N*N*PIXEL_WIDTH-1:0] window;        // flattened NxN window (72 bits)
    wire [N*N*COEFF_WIDTH-1:0] kernel;
    wire signed [SUM_WIDTH-1:0] conv_sum;     // registered MAC-chain output
    wire signed [OUT_WIDTH-1:0] result;

    // Pipeline interconnect
    wire result_valid_p;  // result valid shifted with the pipeline data
    wire last_p;  // frame-last flag shifted with the pipeline data
    wire [KIDX_WIDTH-1:0] kidx_p;  // source kernel index shifted with the pipeline data
    wire fifo_wr_ready;  // output FIFO write not full
    // Back-pressure freeze net: output_fifo's registered high-water flag.
    // max_fanout stays attached right at the net that fans out to every
    // clock enable in the design.
    (* max_fanout = 40 *) wire fifo_almost_full;
    wire fifo_rd_valid;  // output FIFO read not empty
    wire [OUT_WIDTH+KIDX_WIDTH:0] fifo_rd_data;  // {last, kernel_idx, result}

    // Live/replay pixel source selection, frame_buffer enables, host ready
    pixel_source_mux #(
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) u_pixel_source_mux (
        .replay_pass_i(replay_pass),
        .pixel_in_i   (pixel_in_i),
        .pixel_valid_i(pixel_valid_i),
        .fb_rd_data_i (fb_rd_data),
        .pad_ready_i  (pad_ready),
        .pixel_o      (pad_inserter_pixel_in),
        .pixel_valid_o(pad_inserter_pixel_valid),
        .fb_wr_en_o   (fb_wr_en),
        .fb_rd_en_o   (fb_rd_en),
        .host_ready_o (ready_o)
    );

    // last/kidx sampling + last_p/kidx_p/result_valid_p pipeline shift chains
    result_tag_pipeline #(
        .PIPE_STAGES(PIPE_STAGES),
        .KIDX_WIDTH (KIDX_WIDTH)
    ) u_result_tag_pipeline (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .freeze_i        (fifo_almost_full),
        .pix_last_i      (pix_last),
        .kernel_idx_i    (kernel_idx),
        .result_valid_i  (result_valid),
        .last_p_o        (last_p),
        .kidx_p_o        (kidx_p),
        .result_valid_p_o(result_valid_p)
    );

    // Output FIFO. The write valid is gated by the same freeze that holds the
    // pipeline: while fifo_almost_full is high the result presented is the
    // *held* word, so exact-ready gating alone would enqueue it again every
    // cycle.
    output_fifo #(
        .DATA_WIDTH(OUT_WIDTH + 1 + KIDX_WIDTH),  // {frame_last, kernel_idx, result}
        .DEPTH(16)
    ) u_out_fifo (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .wr_data_i       ({last_p, kidx_p, result}),
        .wr_valid_i      (result_valid_p && !fifo_almost_full),
        .wr_ready_o      (fifo_wr_ready),
        .wr_almost_full_o(fifo_almost_full),
        .rd_data_o       (fifo_rd_data),
        .rd_valid_o      (fifo_rd_valid),
        .rd_ready_i      (result_ready_i)
    );

    // Streaming output (FWFT): unpack the FIFO's {last, kernel_idx, result} word
    result_field_unpack #(
        .OUT_WIDTH (OUT_WIDTH),
        .KIDX_WIDTH(KIDX_WIDTH)
    ) u_result_field_unpack (
        .fifo_rd_valid_i    (fifo_rd_valid),
        .fifo_rd_data_i     (fifo_rd_data),
        .result_valid_o     (result_valid_o),
        .result_o           (result_o),
        .result_kernel_idx_o(result_kernel_idx_o),
        .result_tlast_o     (result_tlast_o)
    );

    // Frame buffer: captures the live pass, replays it for later kernels
    frame_buffer#(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH (PIXEL_WIDTH)
    ) u_frame_buffer (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .wr_en_i      (fb_wr_en),
        .wr_rst_addr_i(start_i),
        .wr_data_i    (pixel_in_i),
        .rd_en_i      (fb_rd_en),
        .rd_rst_addr_i(stream_start),
        .rd_data_o    (fb_rd_data)
    );

    // Row zero-pad inserter
    pixel_pad_inserter #(
        .IMAGE_WIDTH    (IMAGE_WIDTH),
        .IMAGE_HEIGHT   (IMAGE_HEIGHT),
        .PIXEL_WIDTH    (PIXEL_WIDTH),
        .PAD_ROWS_BEFORE(PAD_ROWS_BEFORE),
        .PAD_ROWS_AFTER (PAD_ROWS_AFTER)
    ) u_pixel_pad_inserter (
        .clk_i               (clk_i),
        .rst_n_i             (rst_n_i),
        .en_i                (fsm_ready),
        .start_i             (stream_start),
        .pixel_in_i          (pad_inserter_pixel_in),
        .pixel_valid_i       (pad_inserter_pixel_valid),
        .padded_pixel_o      (padded_pixel),
        .padded_pixel_valid_o(padded_pixel_valid),
        .ready_o             (pad_ready),
        .real_pixel_o        (),
        .last_pixel_o        ()
    );

    // Frame controller
    conv_fsm #(
        .N             (N),
        .IMAGE_WIDTH   (IMAGE_WIDTH),
        .IMAGE_HEIGHT  (PADDED_HEIGHT),
        .COEFF_WIDTH   (COEFF_WIDTH),
        .PIPE_STAGES   (PIPE_STAGES),
        .PIX_ADDR_WIDTH(PIX_ADDR_WIDTH),
        .STATE_WIDTH   (2),
        .N_Kernel   (N_Kernel)
    ) u_fsm (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .start_i         (start_i),
        .pixel_valid_i   (padded_pixel_valid),
        .output_stall_i  (fifo_almost_full),
        .kernel_wr_valid_i(kernel_wr_valid_i),
        .kernel_data_i   (kernel_wr_data_i),
        .pix_addr_i      (pix_addr),
        .pix_last_i      (pix_last),
        .kernel_we_o     (kernel_we),
        .kernel_addr_o   (kernel_addr),
        .shift_valid_o   (shift_valid),
        .stream_start_o  (stream_start),
        .ready_o         (fsm_ready),
        .result_valid_o  (result_valid),
        .rst_count_o     (rst_count),
        .busy_o          (busy_o),
        .done_o          (done_o),
        .state_o         (state_o),
        .kernel_idx_o    (kernel_idx),
        .replay_o        (replay_pass)
    );

    // Pixel position counter (input), sized to the padded row count
    pixel_counter #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(PADDED_HEIGHT),
        .ADDR_WIDTH  (PIX_ADDR_WIDTH)
    ) u_in (
        .clk_i       (clk_i),
        .rst_n_i     (rst_n_i),
        .en_i        (shift_valid),
        .rst_count_i (rst_count),
        .addr_o      (pix_addr),
        .last_o      (pix_last)
    );

    // Column of the pixel the pixel counter is presenting, used by the window
    // bank to place its taps and to zero them at the image's left/right borders.
    pixel_col_calc #(
        .IMAGE_WIDTH   (IMAGE_WIDTH),
        .PIX_ADDR_WIDTH(PIX_ADDR_WIDTH)
    ) u_pixel_col_calc (
        .pix_addr_i(pix_addr),
        .pix_col_o (pix_col)
    );

    // Datapath
    // Centred sliding window out of rotating row buffers: each row is held in
    // distributed RAM and read one row behind the write pointer, so the window
    // taps reach one row and one column past the pixel being streamed and the
    // window lands centred on the output pixel.
    row_buffer_bank #(
        .N          (N),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) u_row_buffer_bank (
        .clk_i   (clk_i),
        .rst_n_i (rst_n_i),
        .en_i    (shift_valid),
        .col_i   (pix_col),
        .pixel_i (padded_pixel),
        .window_o(window)
    );

    kernel_reg_bank #(
        .N           (N),
        .COEFF_WIDTH (COEFF_WIDTH),
        .N_Kernel (N_Kernel)
    ) u_kernel_reg_bank (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .load_valid_i (kernel_wr_valid_i && kernel_we),
        .load_addr_i  (kernel_addr),
        .load_data_i  (kernel_wr_data_i),
        .kernel_sel_i (kernel_idx),
        .kernel_o     (kernel)
    );

    // DSP MAC chain: the N*N taps multiply *and* accumulate inside the
    // DSP48E1s' own adders, so the convolution reduction needs no fabric adder
    // tree at all. The chain is registered (its TAPS-deep latency is part of
    // PIPE_STAGES).
    mac_chain #(
        .N          (N),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .PROD_WIDTH (PROD_WIDTH),
        .SUM_WIDTH  (SUM_WIDTH)
    ) u_mac_chain (
        .clk_i   (clk_i),
        .rst_n_i (rst_n_i),
        .en_i    (!fifo_almost_full),
        .window_i(window),
        .kernel_i(kernel),
        .sum_o   (conv_sum)
    );

    sat_round_unit #(
        .SUM_WIDTH    (SUM_WIDTH),
        .OUT_WIDTH    (OUT_WIDTH),
        .FRAC_BITS    (FRAC_BITS),
        .ROUND_ENABLE (ROUND_ENABLE)
    ) u_sat_round_unit (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .en_i      (!fifo_almost_full),
        .sum_i     (conv_sum),
        .relu_en_i (relu_en_i),
        .result_o  (result)
    );

endmodule
