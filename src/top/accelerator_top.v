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
//              top-level valid/last shift registers are PIPE_STAGES deep to stay
//              aligned with the result. The FSM's drain counter uses
//              PIPE_STAGES + 2.
//
//              The pipeline freezes on output_fifo's registered high-water flag
//              rather than on its exact ready signal: the exact-ready comparator
//              hangs off the read pointer and the freeze net fans out to every
//              clock enable, so it was the critical path. The guard band absorbs
//              the flag's one cycle of staleness and output_fifo still gates the
//              write on exact readiness. See README.md (Design notes).
//
// Dependencies: pixel_pad_inserter (src/datapath/pixel_pad_inserter.v)
//               conv_fsm (src/control/conv_fsm.v)
//               pixel_counter (src/control/pixel_counter.v)
//               row_buffer_bank (src/datapath/row_buffer_bank.v)
//               kernel_reg_bank (src/datapath/kernel_reg_bank.v)
//               mac_chain (src/datapath/mac_chain.v)
//               output_fifo (src/datapath/output_fifo.v)
//               sat_round_unit (src/datapath/sat_round_unit.v)
//
// Revision:
//   0.01 - File Created.
//////////////////////////////////////////////////////////////////////////////////

module accelerator_top #(
    parameter N = 3,  // Kernel size (N >= 2)
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
    output wire busy_o,  // Frame in progress
    output wire done_o,  // Frame complete
    output wire [1:0] state_o,  // FSM state (observability)
    output wire result_valid_o,  // Output word available (FIFO not empty)
    output wire [OUT_WIDTH-1:0] result_o,  // Output data (FIFO read)
    output wire result_tlast_o,  // Last output word of the frame
    input wire result_ready_i,  // Output ready
    output wire ready_o  // Accepting input pixels (AXI-Stream TREADY)
);

    // Control-unit interconnect
    wire [PIX_ADDR_WIDTH-1:0] pix_addr;
    wire pix_last;
    wire kernel_we;
    wire [$clog2(N*N)-1:0] kernel_addr;
    wire shift_valid;
    wire stream_start;  // One-cycle pulse: arms pixel_pad_inserter
    wire fsm_ready;  // conv_fsm's own readiness (gates the pad inserter)
    wire result_valid;
    wire rst_count;

    // Pad-inserter interconnect
    wire [PIXEL_WIDTH-1:0] padded_pixel;
    wire padded_pixel_valid;

    // Datapath interconnect
    wire [$clog2(IMAGE_WIDTH)-1:0] pix_col;  // Column of the accepted pixel
    wire [N*N*PIXEL_WIDTH-1:0] window;        // flattened NxN window (72 bits)
    wire [N*N*COEFF_WIDTH-1:0] kernel;
    wire signed [SUM_WIDTH-1:0] conv_sum;     // registered MAC-chain output
    wire signed [OUT_WIDTH-1:0] result;

    // Pipeline interconnect
    wire signed [SUM_WIDTH-1:0] sum_to_sat;
    wire result_valid_p;  // result valid shifted with the pipeline data
    wire last_p;  // frame-last flag shifted with the pipeline data
    wire fifo_wr_ready;  // output FIFO write not full
    wire fifo_almost_full;  // output FIFO registered high-water flag
    wire fifo_rd_valid;  // output FIFO read not empty
    wire [OUT_WIDTH:0] fifo_rd_data;  // {last, result}

    // Back-pressure freeze: output_fifo's registered high-water flag. The FIFO
    // write valid is gated by the same freeze, so the held word is enqueued once,
    // when the freeze lifts, instead of on every stalled cycle.
    (* max_fanout = 40 *) wire output_stall;

    assign output_stall = fifo_almost_full;

    // Frame-last flag: the last accepted pixel's result ends the frame
    reg last_q;
    always @(posedge clk_i or negedge rst_n_i) begin : last_reg
        if (!rst_n_i) last_q <= 1'b0;
        else if (!output_stall) last_q <= pix_last;
    end

    generate
        if (PIPE_STAGES == 1) begin : gen_pipe_last1
            reg last_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) last_p1 <= 1'b0;
                else if (!output_stall) last_p1 <= last_q;
            end
            assign last_p = last_p1;
        end else if (PIPE_STAGES >= 2) begin : gen_pipe_lastn
            reg [PIPE_STAGES-1:0] last_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) last_p1 <= 0;
                else if (!output_stall) last_p1 <= {last_p1[PIPE_STAGES-2:0], last_q};
            end
            assign last_p = last_p1[PIPE_STAGES-1];
        end else begin : gen_no_pipe_last
            assign last_p = last_q;
        end
    endgenerate

    // The MAC chain output is already registered and feeds sat_round directly.
    assign sum_to_sat = conv_sum;

    // Pipeline valid: shifts with the data (holds while stalled)
    generate
        if (PIPE_STAGES == 1) begin : gen_pipe_valid1
            reg valid_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) valid_p1 <= 1'b0;
                else if (!output_stall) valid_p1 <= result_valid;
            end
            assign result_valid_p = valid_p1;
        end else if (PIPE_STAGES >= 2) begin : gen_pipe_validn
            reg [PIPE_STAGES-1:0] valid_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) valid_p1 <= 0;
                else if (!output_stall) valid_p1 <= {valid_p1[PIPE_STAGES-2:0], result_valid};
            end
            assign result_valid_p = valid_p1[PIPE_STAGES-1];
        end else begin : gen_no_pipe_valid
            assign result_valid_p = result_valid;
        end
    endgenerate

    // Output FIFO. The write valid is gated by the same freeze that holds the
    // pipeline: while output_stall is high the result presented is the *held*
    // word, so exact-ready gating alone would enqueue it again every cycle.
    output_fifo #(
        .DATA_WIDTH(OUT_WIDTH + 1),  // {frame_last, result}
        .DEPTH(16)
    ) u_out_fifo (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .wr_data_i ({last_p, result}),
        .wr_valid_i(result_valid_p && !output_stall),
        .wr_ready_o(fifo_wr_ready),
        .wr_almost_full_o(fifo_almost_full),
        .rd_data_o (fifo_rd_data),
        .rd_valid_o(fifo_rd_valid),
        .rd_ready_i(result_ready_i)
    );

    // Streaming output (FWFT)
    assign result_valid_o = fifo_rd_valid;
    assign result_o       = fifo_rd_data[OUT_WIDTH-1:0];
    assign result_tlast_o = fifo_rd_data[OUT_WIDTH];

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
        .pixel_in_i          (pixel_in_i),
        .pixel_valid_i       (pixel_valid_i),
        .padded_pixel_o      (padded_pixel),
        .padded_pixel_valid_o(padded_pixel_valid),
        .ready_o             (ready_o),
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
        .STATE_WIDTH   (2)
    ) u_fsm (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .start_i         (start_i),
        .pixel_valid_i   (padded_pixel_valid),
        .output_stall_i  (output_stall),
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
        .state_o         (state_o)
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
    assign pix_col = pix_addr % IMAGE_WIDTH;

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
        .COEFF_WIDTH (COEFF_WIDTH)
    ) u_kernel_reg_bank (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .load_valid_i (kernel_wr_valid_i && kernel_we),
        .load_addr_i  (kernel_addr),
        .load_data_i  (kernel_wr_data_i),
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
        .en_i    (!output_stall),
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
        .en_i      (!output_stall),
        .sum_i     (sum_to_sat),
        .relu_en_i (relu_en_i),
        .result_o  (result)
    );

endmodule