`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/12/2026
// Design Name: CNN Convolution Accelerator - Zero-Padding Stream Inserter
// Module Name: pixel_pad_inserter
// Tool Versions: Vivado 2025.2
// Description: Sits between the host's real pixel stream and the rest of the
//              datapath (conv_fsm, pixel_counter, line_buffer_bank), presenting
//              a synthetic, padded raster covering PADDED_WIDTH x PADDED_HEIGHT
//              instead of the real IMAGE_WIDTH x IMAGE_HEIGHT. Real pixels pass
//              through unchanged; positions inside the PAD_BEFORE/PAD_AFTER
//              margin on either axis are synthesized as zero, with no data
//              requested from the host for those cycles (ready_o only asserts
//              for real positions). real_pixel_o tags each output word so a
//              downstream consumer can distinguish real image data from
//              padding. All outputs are registered together (one cycle behind
//              the accepted pixel) so they stay latency-matched with each
//              other as they're pipelined further downstream.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module pixel_pad_inserter #(
    parameter IMAGE_WIDTH = 32,                   // Input feature-map width
    parameter IMAGE_HEIGHT = 32,                  // Input feature-map height
    parameter PIXEL_WIDTH = 8,                    // Input pixel width
    parameter PAD_BEFORE = 1,                     // Number of padding pixels to insert before the first pixel
    parameter PAD_AFTER = 1                       // Number of padding pixels to insert after the last pixel
    ) (
    input wire clk_i,
    input wire rst_n_i,
    input wire en_i,                              // Enable the pixel pad inserter
    input wire start_i,                           // Frame start request
    input wire [PIXEL_WIDTH-1:0] pixel_in_i,      // Input pixel data
    input wire pixel_valid_i,                     // Input pixel valid (deasserted = stall)
    output wire [PIXEL_WIDTH-1:0] padded_pixel_o, // Output pixel data (with padding)
    output wire padded_pixel_valid_o,             // Output pixel valid (deasserted = stall)
    output wire ready_o,                          // Ready signal
    output wire real_pixel_o,                     // Indicates if the output pixel is a real pixel (1) or a padding pixel (0)
    output wire last_pixel_o                      // Indicates if the output pixel is the last real pixel in the frame
    );

    // Parameters
    localparam PADDED_WIDTH  = IMAGE_WIDTH + PAD_BEFORE + PAD_AFTER; // Total width after padding
    localparam PADDED_HEIGHT = IMAGE_HEIGHT + PAD_BEFORE + PAD_AFTER; // Total height after padding

    localparam ROW_BITS = ($clog2(PADDED_HEIGHT) < 1) ? 1 : $clog2(PADDED_HEIGHT); // Row Counter Width
    localparam COL_BITS = ($clog2(PADDED_WIDTH)  < 1) ? 1 : $clog2(PADDED_WIDTH);  // Column Counter Width

    // Current state
    reg [ROW_BITS-1:0] row_q;    // Row counter for padded image
    reg [COL_BITS-1:0] col_q;    // Column counter for padded image
    reg                active_q; // Checks whether the module is busy emitting a padded frame or not

    reg [PIXEL_WIDTH-1:0] padded_pixel_q;
    reg                   padded_pixel_valid_q;
    reg                   real_pixel_q;
    reg                   last_pixel_q;

    // Next state
    reg [ROW_BITS-1:0]    row_d;
    reg [COL_BITS-1:0]    col_d;
    reg                   active_d;

    reg [PIXEL_WIDTH-1:0] padded_pixel_d;
    reg                   padded_pixel_valid_d;
    reg                   real_pixel_d;
    reg                   last_pixel_d;

    // Signals to decode the current position
    wire is_real_row = (row_q >= PAD_BEFORE) && (row_q < (IMAGE_HEIGHT + PAD_BEFORE)); // Checks if the current row is a real row
    wire is_real_col = (col_q >= PAD_BEFORE) && (col_q < (IMAGE_WIDTH + PAD_BEFORE)); // Checks if the current column is a real column
    wire is_real     = is_real_row && is_real_col; // Checks if the current pixel is a real pixel or a padded one
    wire last_row    = (row_q == (PADDED_HEIGHT - 1)); // Checks if the current row is the last row
    wire last_col    = (col_q == (PADDED_WIDTH - 1)); // Checks if the current column is the last column



    // Handshake signals
    assign ready_o = active_q && en_i && is_real; // Ready to accept input pixels when the module is active, enabled, and the current pixel is real
    wire advance   = active_q && en_i && (is_real ? pixel_valid_i : 1'b1); // Advance the counters when the module is active, enabled, and either the current pixel is real and valid or the current pixel is padded

    // Indicates if the current pixel is the last pixel in the frame
    wire last_pixel = advance && is_real &&
                    (row_q == (IMAGE_HEIGHT + PAD_BEFORE - 1)) &&
                    (col_q == (IMAGE_WIDTH  + PAD_BEFORE - 1));

    always @(*) begin: next_state
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
            col_d                   = {COL_BITS{1'b0}};    // Reset column counter
            if (last_row)  active_d = 1'b0;               // Deactivate the module if it's the last row
            else           row_d    = row_q + 1'b1;      // Increment row counter
        end else begin
            col_d                   = col_q + 1'b1;      // Increment column counter
        end
    end
    end

    always@(*) begin: output_state
    padded_pixel_valid_d = advance;
    padded_pixel_d       = is_real ? pixel_in_i : {PIXEL_WIDTH{1'b0}};    // Output the input pixel if it's real, otherwise output zero
    real_pixel_d         = advance && is_real;                            // Output whether the current pixel is real or padded
    last_pixel_d         = last_pixel;                                    // Output whether the current pixel is the last pixel in the frame
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
            row_q                <= row_d;
            col_q                <= col_d;
            active_q             <= active_d;
            padded_pixel_q       <= padded_pixel_d;
            padded_pixel_valid_q <= padded_pixel_valid_d;
            real_pixel_q         <= real_pixel_d;
            last_pixel_q         <= last_pixel_d;
        end
    end

    // Output assignment
    assign padded_pixel_o       = padded_pixel_q;
    assign padded_pixel_valid_o = padded_pixel_valid_q;
    assign real_pixel_o         = real_pixel_q;
    assign last_pixel_o         = last_pixel_q;

endmodule
