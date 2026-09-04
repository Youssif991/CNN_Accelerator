`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - MAC Array
// Module Name: mac_array
// Tool Versions: Vivado 2025.2
// Description: Array of NxN dsp_mult_r4 instances computing the per-tap
//              products (unsigned pixel x signed kernel coefficient). Each tap
//              maps to a DSP48E1 whose P register is the MAC pipeline stage 1;
//              en_i (the pipeline freeze, = !output_stall in the top) clocks
//              the product registers so a stalled result is never overwritten.
//
// Dependencies: dsp_mult_r4 (src/multiplier/dsp_mult_r4.v)
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
    input  wire clk_i,  // Product register clock
    input  wire en_i,  // Product register enable, = !output_stall in the top
    input  wire [N*N*PIXEL_WIDTH-1:0] window_i,   // flattened NxN window (row-major)
    input  wire [N*N*COEFF_WIDTH-1:0] kernel_i,   // flattened NxN kernel (row-major)
    output wire [N*N*PROD_WIDTH-1:0]  products_o  // flattened NxN products (row-major)
);

    genvar g;
    generate
        for (g = 0; g < N*N; g = g + 1) begin : gen_mac_taps
            dsp_mult_r4 #(
                .PIXEL_WIDTH(PIXEL_WIDTH),
                .COEFF_WIDTH(COEFF_WIDTH),
                .PROD_WIDTH (PROD_WIDTH)
            ) u_dsp_mult_r4 (
                .clk_i  (clk_i),
                .en_i   (en_i),
                .pixel_i(window_i[PIXEL_WIDTH*g +: PIXEL_WIDTH]),
                .coeff_i(kernel_i[COEFF_WIDTH*g +: COEFF_WIDTH]),
                .prod_o (products_o[PROD_WIDTH*g +: PROD_WIDTH])
            );
        end
    endgenerate

endmodule
