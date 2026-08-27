`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - MAC Array
// Module Name: mac_array
// Tool Versions: Vivado 2025.2
// Description: Array of NxN booth_mult_r4 instances computing the per-tap
//              products (unsigned pixel x signed kernel coefficient). The
//              multiplier instances are drop-in compatible with a DSP-based
//              variant.
//
// Dependencies: booth_mult_r4 (src/booth_mult/booth_mult_r4.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module mac_array #(
    parameter N = 3,
    parameter PIXEL_WIDTH = 8,
    parameter COEFF_WIDTH = 8,
    parameter PROD_WIDTH  = PIXEL_WIDTH + COEFF_WIDTH + 2
) (
    input  wire [N*N*PIXEL_WIDTH-1:0] window_i,   // flattened NxN window (row-major)
    input  wire [N*N*COEFF_WIDTH-1:0] kernel_i,   // flattened NxN kernel (row-major)
    output wire [N*N*PROD_WIDTH-1:0]  products_o  // flattened NxN products (row-major)
);

    genvar g;
    generate
        for (g = 0; g < N*N; g = g + 1) begin : gen_mac_taps
            booth_mult_r4 #(
                .PIXEL_WIDTH(PIXEL_WIDTH),
                .COEFF_WIDTH(COEFF_WIDTH),
                .PROD_WIDTH (PROD_WIDTH)
            ) u_booth_mult_r4 (
                .pixel_i(window_i[PIXEL_WIDTH*g +: PIXEL_WIDTH]),
                .coeff_i(kernel_i[COEFF_WIDTH*g +: COEFF_WIDTH]),
                .prod_o (products_o[PROD_WIDTH*g +: PROD_WIDTH])
            );
        end
    endgenerate

endmodule
