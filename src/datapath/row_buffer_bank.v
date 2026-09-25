`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Design Name: CNN Convolution Datapath - Row Buffer Bank (parameterized N)
// Module Name: row_buffer_bank
// Tool Versions: Vivado 2025.2
// Description: Presents the whole NxN sliding convolution window, centred on
//              the output pixel, out of N+1 rotating row buffers held in
//              distributed RAM.
//
//              Generalized for any odd N >= 3 (previous version only worked
//              for N = 3): each row group now builds its N column taps from
//              an (N-1)-deep shift register behind the single RAM read port
//              (tap m=N-1 is the raw read, 0-cycle delay; tap m=0 is the
//              oldest, (N-1)-cycle delay). Each tap's true image column is
//              col_i + (m - HALF), where HALF = (N-1)/2; a tap is zeroed
//              whenever that column falls outside [0, IMAGE_WIDTH-1], which
//              reproduces the exact N=3 left/right border behaviour of the
//              original module and extends it to the (N-1)/2-wide borders
//              needed for larger N.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created (N = 3 only).
//   0.02 - Generalized column-tap generation and border zeroing for any
//          odd N >= 3.
//////////////////////////////////////////////////////////////////////////////////

module row_buffer_bank #(
    parameter N           = 3,   // Window size (odd, >= 3)
    parameter IMAGE_WIDTH = 32,  // Row width in pixels
    parameter PIXEL_WIDTH = 8    // Pixel width
) (
    input  wire clk_i,
    input  wire rst_n_i,
    input  wire en_i,                                // Accepted pixel: store it and advance
    input  wire [$clog2(IMAGE_WIDTH)-1:0] col_i,      // Column of the accepted pixel
    input  wire [PIXEL_WIDTH-1:0] pixel_i,            // Padded pixel stream
    output wire [N*N*PIXEL_WIDTH-1:0] window_o        // Flattened NxN window, row-major
);

    // Parameters
    localparam NUM_BUFS  = N + 1;                         // One written while N are read
    localparam PTR_WIDTH = (NUM_BUFS > 2) ? $clog2(NUM_BUFS) : 1;
    localparam COL_WIDTH = $clog2(IMAGE_WIDTH);
    localparam HALF      = (N - 1) / 2;                   // Half-window (border width)
    localparam EXT_WIDTH = COL_WIDTH + 4;                  // Headroom for col_i + m compares

    // Rotating write-buffer index
    reg [PTR_WIDTH-1:0] wr_buf_q;
    reg [PTR_WIDTH-1:0] wr_buf_d;

    // Last column of the row: the row is complete and the pointer rotates
    wire row_end = (col_i == IMAGE_WIDTH - 1);

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
    // IMAGE_WIDTH pixels each.
    reg [PIXEL_WIDTH-1:0] row_mem[0:NUM_BUFS*IMAGE_WIDTH-1];

    // Write port (no reset: an async reset would break RAM inference)
    always @(posedge clk_i) begin : write
        if (en_i) row_mem[wr_buf_q * IMAGE_WIDTH + col_i] <= pixel_i;
    end

    // Read row select: normally the current write buffer, but advanced at
    // the last column so the taps stay on one row across the row boundary.
    wire [PTR_WIDTH-1:0] rd_ptr = (en_i && row_end) ? wr_buf_d : wr_buf_q;

    // Read column: one ahead of the write column, wrapping to 0 at the last
    // column (same pre-load trick as the original module).
    wire [COL_WIDTH-1:0] rd_col = row_end ? {COL_WIDTH{1'b0}} : col_i + 1'b1;

    // Combinational window (registered into window_q below)
    wire [N*N*PIXEL_WIDTH-1:0] window_d;

    genvar g, m, k;
    generate
        for (g = 0; g < N; g = g + 1) begin : gen_row_taps

            // Row group g reads the buffer holding padded row w-N+g (window
            // row g, top of the patch first) - unchanged from the original.
            wire [PTR_WIDTH:0]   read_index = {1'b0, rd_ptr} + (g + 1);
            wire [PTR_WIDTH-1:0] rd_buf      = (read_index >= NUM_BUFS) ?
                                                read_index[PTR_WIDTH-1:0] - NUM_BUFS :
                                                read_index[PTR_WIDTH-1:0];

            wire [PIXEL_WIDTH-1:0] rd_data = row_mem[rd_buf * IMAGE_WIDTH + rd_col];

            // (N-1)-deep shift register behind the single RAM read.
            // shift_q[0] is 1 cycle behind rd_data, shift_q[k] is (k+1)
            // cycles behind.
            wire [PIXEL_WIDTH-1:0] shift_q[0:N-2];
            reg  [PIXEL_WIDTH-1:0] shift_r[0:N-2];

            always @(posedge clk_i) begin : tap_shift
                integer si;
                if (en_i) begin
                    shift_r[0] <= rd_data;
                    for (si = 1; si < N-1; si = si + 1)
                        shift_r[si] <= shift_r[si-1];
                end
            end

            for (k = 0; k < N-1; k = k + 1) begin : gen_shift_tap
                assign shift_q[k] = shift_r[k];
            end

            // Column taps: m = 0 (oldest/leftmost) .. N-1 (newest/rightmost).
            // tap m = N-1 is rd_data itself (0-cycle delay); tap m < N-1 is
            // shift_q[N-2-m] ((N-1-m)-cycle delay).
            for (m = 0; m < N; m = m + 1) begin : gen_col_taps
                wire [PIXEL_WIDTH-1:0] raw_tap = (m == N-1) ? rd_data : shift_q[N-2-m];

                // This tap's true image column is col_i + (m - HALF). Zero
                // it whenever that column falls outside [0, IMAGE_WIDTH-1],
                // i.e. it belongs to the (unstored) horizontal border.
                wire [EXT_WIDTH-1:0] col_ext    = {{(EXT_WIDTH-COL_WIDTH){1'b0}}, col_i} + m;
                wire                 left_edge  = (col_ext < HALF);
                wire                 right_edge = (col_ext >= (IMAGE_WIDTH + HALF));

                wire [PIXEL_WIDTH-1:0] tap = (left_edge || right_edge) ?
                                             {PIXEL_WIDTH{1'b0}} : raw_tap;

                assign window_d[(g*N + m)*PIXEL_WIDTH +: PIXEL_WIDTH] = tap;
            end
        end
    endgenerate

    // Output register: latches the completed window so window_o is stable
    // for a whole cycle.
    reg [N*N*PIXEL_WIDTH-1:0] window_q;

    always @(posedge clk_i or negedge rst_n_i) begin : output_reg
        if (!rst_n_i) window_q <= {N*N*PIXEL_WIDTH{1'b0}};
        else if (en_i) window_q <= window_d;
    end

    assign window_o = window_q;

endmodule