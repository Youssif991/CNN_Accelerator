`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/14/2026
// Design Name: CNN Convolution Datapath - Row Buffer Bank
// Module Name: row_buffer_bank
// Tool Versions: Vivado 2025.2
// Description: Presents the whole NxN sliding convolution window, centred on the
//              output pixel, out of N+1 rotating row buffers held in distributed
//              RAM.
//
//              While padded row w is written into buffer (w mod N+1), buffers
//              (w-1) ... (w-N) are read. Those rows are complete, so reading
//              column (c + H) mod W, with H = (N-1)/2, out of a row the raster
//              has already passed is a plain address rather than a lookahead,
//              and the window lands centred on real row w - N. One asynchronous
//              RAM read port per row is enough: the read address cycles
//              H, H+1 ... W-1, 0, 1 ... H-1 (mod W; see rd_col) and N-1
//              flip-flops behind it give the N window columns. The read row
//              select switches one cycle early at the last column so the
//              flip-flop chain stays on one row across the row boundary.
//
//              Vertical zero padding comes from the caller's pad rows; the
//              horizontal borders are the per-tap zeroing below, which costs
//              no stream cycles, so the output stream stays gap-free.
//
//              Generalised from the original N=3-only version:
//                - N window columns per row (was hardcoded 3).
//                - N-1 delay flip-flops per row (was hardcoded 2).
//                - Read column offset H = (N-1)/2 (was hardcoded 1).
//                - Per-tap border zeroing for every window column (was
//                  row_start for j=0 and row_end for j=N-1 only).
//              For N = 3 all of these reduce exactly to the previous behaviour.
//
//              Only the row storage is reset-free (an asynchronous reset would
//              stop Vivado mapping it to distributed RAM); the output register is
//              reset, and result_valid is not asserted until every buffer the taps
//              read holds real data. The output register also makes window_o a
//              clock-aligned signal for the MAC array.
//
//              See README.md (Design notes) for the derivation and the measurements.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created.
//   0.02 - Generalised from N=3 to any (odd) N.
//////////////////////////////////////////////////////////////////////////////////

module row_buffer_bank #(
    parameter N = 3,  // Window size (odd, >= 3)
    parameter IMAGE_WIDTH = 32,  // Row width in pixels
    parameter PIXEL_WIDTH = 8  // Pixel width
) (
    input  wire clk_i,
    input  wire rst_n_i,
    input  wire en_i,  // Accepted pixel: store it and advance the row pointer
    input  wire [$clog2(IMAGE_WIDTH)-1:0] col_i,  // Column of the accepted pixel
    input  wire [PIXEL_WIDTH-1:0] pixel_i,  // Padded pixel stream
    output wire [N*N*PIXEL_WIDTH-1:0] window_o  // Flattened NxN window, row-major, top row first
);

    // Parameters
    localparam NUM_BUFS = N + 1;  // One buffer is being written while N are read
    localparam PTR_WIDTH = (NUM_BUFS > 2) ? $clog2(NUM_BUFS) : 1;
    localparam COL_WIDTH = $clog2(IMAGE_WIDTH);
    localparam H = (N - 1) / 2;  // Window half-width: tap centring offset
    // Wide enough to hold (col_i + H) and the comparison constants IMAGE_WIDTH+k
    localparam EXT_W = COL_WIDTH + $clog2(N) + 1;

    // Rotating write-buffer index (current state)
    reg [PTR_WIDTH-1:0] wr_buf_q;
    // Rotating write-buffer index (next state)
    reg [PTR_WIDTH-1:0] wr_buf_d;

    // Last column of the row: the row is complete and the pointer rotates
    wire row_end   = (col_i == IMAGE_WIDTH - 1);
    // First column of the row: the left image border
    wire row_start = (col_i == {COL_WIDTH{1'b0}});

    // Next-state
    always @(*) begin : next_state
        wr_buf_d = wr_buf_q;
        if (en_i && row_end) begin
            wr_buf_d = (wr_buf_q == NUM_BUFS - 1) ? {PTR_WIDTH{1'b0}} : wr_buf_q + 1'b1;
        end
    end

    // State update
    always @(posedge clk_i or negedge rst_n_i) begin : state
        if (!rst_n_i) wr_buf_q <= {PTR_WIDTH{1'b0}};
        else          wr_buf_q <= wr_buf_d;
    end

    // Row storage: one flat distributed-RAM array holding NUM_BUFS rows of
    // IMAGE_WIDTH pixels each. Flattening is deliberate: Vivado only infers
    // distributed RAM for a simple one-dimensional array with a computed
    // address, not for a two-dimensional array with a variable first index
    // (that form synthesizes to flip-flops plus read multiplexers).
    reg [PIXEL_WIDTH-1:0] row_mem[0:NUM_BUFS*IMAGE_WIDTH-1];

    // Write port (no reset: an async reset would break RAM inference)
    always @(posedge clk_i) begin : write
        if (en_i) row_mem[wr_buf_q * IMAGE_WIDTH + col_i] <= pixel_i;
    end

    // Next buffer (row w+1's slot), independent of row_end
    wire [PTR_WIDTH-1:0] next_buf = (wr_buf_q == NUM_BUFS - 1) ?
                                     {PTR_WIDTH{1'b0}} : wr_buf_q + 1'b1;

    // Read row select: switch H columns before the row boundary so the N-cycle
    // tap chain stays on one row across the boundary for every unmasked tap.
    // For N = 3 (H = 1) this collapses to the original "switch at row_end".
    wire [PTR_WIDTH-1:0] rd_ptr = (en_i && (col_i >= (IMAGE_WIDTH - H))) ?
                                   next_buf : wr_buf_q;

    // Read column: (col_i + H) mod W. The wrap is deliberate: it (a) pre-loads
    // the c-H tap boundary and (b) keeps the flip-flops on the read row. The
    // values read past the right image border are discarded by the per-tap
    // zeroing below. Using the general modulo form (rather than a row_end ? 0
    // special case) is what lets this work for N > 3, where col_i + H can
    // exceed W-1 by more than one column.
    wire [EXT_W-1:0] rd_col_ext = {{(EXT_W-COL_WIDTH){1'b0}}, col_i} + H;
    wire [COL_WIDTH-1:0] rd_col = (rd_col_ext >= IMAGE_WIDTH) ?
                                   (rd_col_ext[COL_WIDTH-1:0] - IMAGE_WIDTH[COL_WIDTH-1:0]) :
                                   rd_col_ext[COL_WIDTH-1:0];

    // Combinational window (registered into window_q below)
    wire [N*N*PIXEL_WIDTH-1:0] window_d;

    genvar g, k;
    generate
        for (g = 0; g < N; g = g + 1) begin : gen_row_taps
            // Group g reads the buffer holding padded row w-N+g, which is window
            // row g: group 0 is the oldest row, i.e. the top of the patch.
            wire [PTR_WIDTH:0] read_index = {1'b0, rd_ptr} + (g + 1);
            wire [PTR_WIDTH-1:0] rd_buf = (read_index >= NUM_BUFS) ? read_index[PTR_WIDTH-1:0] -
                                          NUM_BUFS : read_index[PTR_WIDTH-1:0];

            wire [PIXEL_WIDTH-1:0] rd_data = row_mem[rd_buf * IMAGE_WIDTH + rd_col];

            // Tap delay chain: tap[0] is the current read (window column N-1,
            // rightmost), tap[k] is rd_data delayed by k cycles (window column
            // N-1-k, moving left). N-1 flip-flops give all N window columns.
            wire [PIXEL_WIDTH-1:0] tap [0:N-1];
            assign tap[0] = rd_data;

            for (k = 1; k < N; k = k + 1) begin : gen_tap_delay
                reg [PIXEL_WIDTH-1:0] tap_q;
                always @(posedge clk_i) begin : tap_shift
                    if (en_i) tap_q <= tap[k-1];
                end
                assign tap[k] = tap_q;
            end

            // Per-tap border zeroing. Tap k is window column j = N-1-k, which
            // would read input column c - H + j = c + H - k. That is outside
            // [0, W) exactly when:
            //   c + H < k              (left  border; only for k > H)
            //   c + H >= W + k         (right border; only for k < H)
            // The centre tap (k == H) is never zeroed. For N = 3 this reduces
            // to: tap[0] zeroed at row_end, tap[2] zeroed at row_start.
            for (k = 0; k < N; k = k + 1) begin : gen_window
                wire left_oob  = (rd_col_ext < k);
                wire right_oob = (rd_col_ext >= (IMAGE_WIDTH + k));
                wire [PIXEL_WIDTH-1:0] tap_masked = (left_oob || right_oob) ?
                                                     {PIXEL_WIDTH{1'b0}} : tap[k];
                assign window_d[(g*N + (N-1-k))*PIXEL_WIDTH +: PIXEL_WIDTH] = tap_masked;
            end
        end
    endgenerate

    // Output register: latches the completed window so window_o is stable for a
    // whole cycle (the caller's pipeline counts this stage).
    reg [N*N*PIXEL_WIDTH-1:0] window_q;

    always @(posedge clk_i or negedge rst_n_i) begin : output_reg
        if (!rst_n_i) window_q <= {N*N*PIXEL_WIDTH{1'b0}};
        else if (en_i) window_q <= window_d;
    end

    assign window_o = window_q;

endmodule