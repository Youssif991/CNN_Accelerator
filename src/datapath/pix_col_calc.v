`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/22/2026
// Design Name: CNN Convolution Datapath - Pixel Column Calculator
// Module Name: pixel_col_calc
// Tool Versions: Vivado 2025.2
// Description: Derives the column (within a row) of the pixel pixel_counter
//              is currently presenting, from the flat row-major pix_addr_i.
//              row_buffer_bank uses this to place its taps and to zero them
//              at the image's left/right borders.
//
//              Extracted verbatim out of accelerator_top (previously
//              "assign pix_col = pix_addr % IMAGE_WIDTH;" lived directly in
//              the top module). Same equation, just moved into its own leaf
//              module and instantiated from the top. No functional change.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created (extracted from accelerator_top).
//////////////////////////////////////////////////////////////////////////////////

module pixel_col_calc #(
    parameter IMAGE_WIDTH    = 32,
    parameter PIX_ADDR_WIDTH = 9
) (
    input  wire [PIX_ADDR_WIDTH-1:0]      pix_addr_i,
    output wire [$clog2(IMAGE_WIDTH)-1:0] pix_col_o
);

    assign pix_col_o = pix_addr_i % IMAGE_WIDTH;

endmodule
