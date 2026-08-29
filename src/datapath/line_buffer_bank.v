`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Line Buffer Bank
// Module Name: line_buffer_bank
// Tool Versions: Vivado 2025.2
// Description: Instantiates (N-1) line buffers to delay the N-1 rows above
//              the current row for NxN sliding-window generation. Reset-free:
//              the buffers are primed with the first rows during the FILL
//              phase before any output is produced.
//
// Dependencies: line_buffer (line_buffer.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module line_buffer_bank #(
    parameter N = 3,
    parameter IMAGE_WIDTH = 32,
    parameter PIXEL_WIDTH = 8
) (
    input wire clk_i,
    input wire shift_valid_i,
    input wire [PIXEL_WIDTH-1:0] pixel_in_i,
    output wire [N*PIXEL_WIDTH-1:0] row_streams_o
);

    // row_chain[r] = the pixel stream delayed by r rows; r=0 is the current
    // pixel, r=N-1 is delayed by N-1 rows.
    wire [PIXEL_WIDTH-1:0] row_chain [0:N-1];

    assign row_chain[0] = pixel_in_i;

    genvar g;
    generate
        // Chained line buffers: each instance adds one more row of delay.
        for (g = 1; g < N; g = g + 1) begin : gen_line_buffers
            line_buffer #(
                .IMAGE_WIDTH(IMAGE_WIDTH),
                .PIXEL_WIDTH(PIXEL_WIDTH)
            ) u_line_buffer (
                .clk_i        (clk_i),
                .shift_valid_i(shift_valid_i),
                .pixel_in_i   (row_chain[g-1]),
                .pixel_out_o  (row_chain[g])
            );
        end

        // Flatten the row streams, row-major (slice r = window row r stream).
        for (g = 0; g < N; g = g + 1) begin : gen_row_out
            assign row_streams_o[g*PIXEL_WIDTH +: PIXEL_WIDTH] = row_chain[g];
        end
    endgenerate

endmodule
