`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/12/2026
// Design Name: CNN Convolution Accelerator - Row Zero-Padding Stream Inserter
// Module Name: pixel_pad_inserter
// Tool Versions: Vivado 2025.2
// Description: Sits between the host's real pixel stream and the rest of the
//              datapath (conv_fsm, pixel_counter, line_buffer_bank), presenting
//              a synthetic raster of PADDED_HEIGHT = IMAGE_HEIGHT + PAD_ROWS_BEFORE
//              + PAD_ROWS_AFTER rows, each IMAGE_WIDTH columns wide (columns are
//              never padded here: the sliding window's horizontal zero-padding is
//              handled for free by window_array's row-start flush instead, since
//              spending stream cycles on column padding would reintroduce a
//              periodic per-row gap in the output valid stream). Real rows pass
//              the host's pixels through unchanged; PAD_ROWS_BEFORE/AFTER rows are
//              synthesized as all-zero, with no data requested from the host for
//              those cycles (ready_o only asserts during a real row). This is a
//              one-time cost folded into the frame's initial fill latency, which
//              does not count against sustained throughput. real_pixel_o tags each
//              output word so a downstream consumer can distinguish real image
//              data from a padding row. last_pixel_o pulses on the last position
//              of the padded stream (with PAD_ROWS_AFTER = 0, this is the last
//              real pixel).
//
//              Backpressure: en_i means "the consumer will accept the currently
//              presented word this cycle" (typically wired to the downstream
//              pipeline's own !stall). The four registered outputs only update
//              while en_i is high, exactly like the clock-enable hold already
//              used for the MAC/adder-tree pipeline registers in accelerator_top;
//              this guarantees a pending word is never overwritten before the
//              consumer actually takes it. row_q/col_q/active_q hold automatically
//              whenever en_i is low, since `advance` itself depends on en_i.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Row-only padding (columns handled by window_array's row-start
//                  flush instead, to avoid a periodic per-row valid gap). Fixed a
//                  backpressure bug: the four output registers previously updated
//                  unconditionally every cycle (only row_q/col_q/active_q were
//                  held via the advance/en_i dependency), so a pending,
//                  not-yet-consumed word was silently overwritten with an invalid
//                  (or, worse, the next) value the cycle after en_i dropped. The
//                  output registers now hold under the same en_i clock-enable as
//                  the rest of the design's pipeline stages.
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module pixel_pad_inserter #(
    parameter IMAGE_WIDTH = 32,       // Input feature-map width (never padded)
    parameter IMAGE_HEIGHT = 32,      // Input feature-map height (real rows)
    parameter PIXEL_WIDTH = 8,        // Input pixel width
    parameter PAD_ROWS_BEFORE = 1,    // Zero rows to insert before the first real row
    parameter PAD_ROWS_AFTER = 0      // Zero rows to insert after the last real row
    ) (
    input wire clk_i,
    input wire rst_n_i,
    input wire en_i,                              // Consumer will accept this cycle's word
    input wire start_i,                           // Frame start request
    input wire [PIXEL_WIDTH-1:0] pixel_in_i,      // Input pixel data
    input wire pixel_valid_i,                     // Input pixel valid (deasserted = stall)
    output wire [PIXEL_WIDTH-1:0] padded_pixel_o, // Output pixel data (with row padding)
    output wire padded_pixel_valid_o,             // Output pixel valid (deasserted = stall)
    output wire ready_o,                          // Ready signal (to the host)
    output wire real_pixel_o,                     // 1 = real image pixel, 0 = padding row
    output wire last_pixel_o                      // Last position of the padded stream
    );

    // Parameters
    localparam PADDED_HEIGHT = IMAGE_HEIGHT + PAD_ROWS_BEFORE + PAD_ROWS_AFTER;

    localparam ROW_BITS = ($clog2(PADDED_HEIGHT) < 1) ? 1 : $clog2(PADDED_HEIGHT); // Row counter width
    localparam COL_BITS = ($clog2(IMAGE_WIDTH)   < 1) ? 1 : $clog2(IMAGE_WIDTH);   // Column counter width

    // Current state
    reg [ROW_BITS-1:0] row_q;    // Row counter for the padded raster
    reg [COL_BITS-1:0] col_q;    // Column counter (columns are never padded)
    reg                active_q; // Checks whether the module is busy emitting a padded frame or not

    reg [PIXEL_WIDTH-1:0] padded_pixel_q;
    reg                   padded_pixel_valid_q;
    reg                   real_pixel_q;
    reg                   last_pixel_q;

    // Next state
    reg [ROW_BITS-1:0]    row_d;
    reg [COL_BITS-1:0]    col_d;
    reg                   active_d;

    // Signals to decode the current position
    wire is_real_row = (row_q >= PAD_ROWS_BEFORE) && (row_q < (IMAGE_HEIGHT + PAD_ROWS_BEFORE)); // Checks if the current row is a real row
    wire last_row    = (row_q == (PADDED_HEIGHT - 1)); // Checks if the current row is the last row
    wire last_col    = (col_q == (IMAGE_WIDTH - 1));   // Checks if the current column is the last column

    // Handshake signals
    assign ready_o = active_q && en_i && is_real_row; // Ready to accept a host pixel when active, enabled, and on a real row
    wire advance   = active_q && en_i && (is_real_row ? pixel_valid_i : 1'b1); // Advance when active/enabled and (a real row's pixel is valid, or we're on a padding row)

    // Indicates if the current position is the last position of the padded stream
    wire last_pixel = advance && last_row && last_col;

    always @(*) begin : next_state
        // Default values
        row_d    = row_q;
        col_d    = col_q;
        active_d = active_q;

        if (start_i) begin
            row_d    = {ROW_BITS{1'b0}};    // Reset row counter
            col_d    = {COL_BITS{1'b0}};    // Reset column counter
            active_d = 1'b1;                // Activate the module
        end else if (advance) begin
            if (last_col) begin
                col_d                  = {COL_BITS{1'b0}};    // Reset column counter
                if (last_row) active_d = 1'b0;                // Deactivate the module if it's the last row
                else          row_d    = row_q + 1'b1;        // Increment row counter
            end else begin
                col_d                  = col_q + 1'b1;        // Increment column counter
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            row_q                <= {ROW_BITS{1'b0}};
            col_q                <= {COL_BITS{1'b0}};
            active_q             <= 1'b0;
            padded_pixel_q       <= {PIXEL_WIDTH{1'b0}};
            padded_pixel_valid_q <= 1'b0;
            real_pixel_q         <= 1'b0;
            last_pixel_q         <= 1'b0;
        end else begin
            row_q    <= row_d;
            col_q    <= col_d;
            active_q <= active_d;
            // The four output registers only update while the consumer is
            // taking this cycle's word (en_i): a pending, not-yet-consumed
            // word must never be clobbered while the consumer is stalled.
            if (en_i) begin
                padded_pixel_q       <= is_real_row ? pixel_in_i : {PIXEL_WIDTH{1'b0}};
                padded_pixel_valid_q <= advance;
                real_pixel_q         <= advance && is_real_row;
                last_pixel_q         <= last_pixel;
            end
        end
    end

    // Output assignment
    assign padded_pixel_o       = padded_pixel_q;
    assign padded_pixel_valid_o = padded_pixel_valid_q;
    assign real_pixel_o         = real_pixel_q;
    assign last_pixel_o         = last_pixel_q;

endmodule
