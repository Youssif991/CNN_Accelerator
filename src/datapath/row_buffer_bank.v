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
//              (w-1) ... (w-N) are read. Those rows are complete, so reading column
//              c+1 out of a row the raster has already passed is a plain address
//              rather than a lookahead, and the window lands centred on real row
//              w - N. One asynchronous RAM read port per row is enough: the read
//              address cycles 1, 2 ... W-1, 0 (see rd_col) and two flip-flops
//              behind it give columns c and c-1. The read row select switches one
//              cycle early at the last column so the flip-flop chain stays on one
//              row across the row boundary.
//
//              Vertical zero padding comes from the caller's pad rows; the
//              horizontal borders are the two tap multiplexers below, which cost
//              no stream cycles, so the output stream stays gap-free.
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

    // Rotating write-buffer index (current state)
    reg [PTR_WIDTH-1:0] wr_buf_q;
    // Rotating write-buffer index (next state)
    reg [PTR_WIDTH-1:0] wr_buf_d;

    // Last column of the row: the row is complete and the pointer rotates
    wire row_end = (col_i == IMAGE_WIDTH - 1);
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

    // Read row select: normally the current write buffer, but advanced at the
    // last column so that the taps stay on one row across the row boundary.
    wire [PTR_WIDTH-1:0] rd_ptr = (en_i && row_end) ? wr_buf_d : wr_buf_q;

    // Read column: one ahead of the write column, wrapping to 0 at the last
    // column. The wrap is deliberate: it (a) pre-loads the c-1 tap boundary and
    // (b) keeps the flip-flops on the read row. The value read there is the
    // right image border and is discarded by the border mux.
    wire [COL_WIDTH-1:0] rd_col = row_end ? {COL_WIDTH{1'b0}} : col_i + 1'b1;

    // Combinational window (registered into window_q below)
    wire [N*N*PIXEL_WIDTH-1:0] window_d;

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : gen_row_taps
            // Group g reads the buffer holding padded row w-N+g, which is window
            // row g: group 0 is the oldest row, i.e. the top of the patch.
            wire [PTR_WIDTH:0] read_index = {1'b0, rd_ptr} + (g + 1);
            wire [PTR_WIDTH-1:0] rd_buf = (read_index >= NUM_BUFS) ? read_index[PTR_WIDTH-1:0] -
                                          NUM_BUFS : read_index[PTR_WIDTH-1:0];

            wire [PIXEL_WIDTH-1:0] rd_data = row_mem[rd_buf * IMAGE_WIDTH + rd_col];

            // Taps are the flip-flop chain of the single RAM read: the current
            // read is column c+1, one delay back is column c and two delays back
            // is column c-1. Across the row boundary the chain still lines up
            // because the read row select switched at the last column (see
            // rd_ptr); only the current read then comes from the next row, and
            // that tap is the right border, which is zero there anyway.
            wire [PIXEL_WIDTH-1:0] tap_base = row_end ? {PIXEL_WIDTH{1'b0}} : rd_data;
            reg [PIXEL_WIDTH-1:0] tap_mid_q;
            reg [PIXEL_WIDTH-1:0] tap_old_q;

            always @(posedge clk_i) begin : tap_shift
                if (en_i) begin
                    tap_mid_q <= rd_data;
                    tap_old_q <= tap_mid_q;
                end
            end

            wire [PIXEL_WIDTH-1:0] tap_mid = tap_mid_q;
            wire [PIXEL_WIDTH-1:0] tap_old = row_start ? {PIXEL_WIDTH{1'b0}} : tap_old_q;

            assign window_d[((g)*N + 0)*PIXEL_WIDTH +: PIXEL_WIDTH] = tap_old;
            assign window_d[((g)*N + 1)*PIXEL_WIDTH +: PIXEL_WIDTH] = tap_mid;
            assign window_d[((g)*N + 2)*PIXEL_WIDTH +: PIXEL_WIDTH] = tap_base;
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
