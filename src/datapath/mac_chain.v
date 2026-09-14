`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/14/2026
// Design Name: CNN Convolution Datapath - DSP MAC Chain
// Module Name: mac_chain
// Tool Versions: Vivado 2025.2
// Description: NxN multiply-accumulate chain: one registered multiply-add per
//              tap, the shape Vivado maps to a single DSP48E1 (the multiplier
//              feeding the block's own adder, the running sum on its C input).
//              The reduction therefore costs no LUTs and no extra DSP blocks.
//
//              Each tap's operands are skewed by the tap's position in the chain,
//              so all N*N taps of one window meet the sum in step. See README.md
//              (Design notes) for why that skew is required and what it costs.
//
//              en_i is the pipeline freeze (typically !output_stall).
//
// Dependencies: none (leaf module, DSP48E1 inference)
//
// Revision:
//   0.01 - File Created.
//////////////////////////////////////////////////////////////////////////////////

module mac_chain #(
    parameter N = 3,  // Kernel size
    parameter PIXEL_WIDTH = 8,  // Unsigned pixel width
    parameter COEFF_WIDTH = 8,  // Signed coefficient width
    parameter PROD_WIDTH = PIXEL_WIDTH + COEFF_WIDTH + 2,  // Product width
    parameter SUM_WIDTH = PROD_WIDTH + $clog2(N*N)  // Convolution sum width
) (
    input  wire clk_i,
    input  wire rst_n_i,
    input  wire en_i,  // Chain enable (pipeline freeze when low)
    input  wire [N*N*PIXEL_WIDTH-1:0] window_i,  // Flattened NxN window, row-major
    input  wire [N*N*COEFF_WIDTH-1:0] kernel_i,  // Flattened NxN kernel, row-major
    output wire signed [SUM_WIDTH-1:0] sum_o  // Convolution sum
);

    localparam TAPS = N * N;

    // Skewed operand pairs: tap g's pixel and coefficient delayed by g cycles.
    // That skew is what makes the chain a pipeline rather than a sum of taps from
    // different windows.
    wire [PIXEL_WIDTH-1:0] pixel_skewed[0:TAPS-1];
    wire [COEFF_WIDTH-1:0] coeff_skewed[0:TAPS-1];

    genvar g;
    generate
        for (g = 0; g < TAPS; g = g + 1) begin : gen_skew
            // Depth is at least 1 so the declarations are always legal; tap 0
            // bypasses its register and takes the window bits directly.
            localparam DEPTH = (g < 1) ? 1 : g;

            wire [PIXEL_WIDTH-1:0] pixel_in = window_i[PIXEL_WIDTH*g +: PIXEL_WIDTH];
            wire [COEFF_WIDTH-1:0] coeff_in = kernel_i[COEFF_WIDTH*g +: COEFF_WIDTH];

            reg [PIXEL_WIDTH-1:0] pixel_q[0:DEPTH-1];
            reg [COEFF_WIDTH-1:0] coeff_q[0:DEPTH-1];

            integer s;
            always @(posedge clk_i) begin : skew
                if (en_i) begin
                    pixel_q[0] <= pixel_in;
                    coeff_q[0] <= coeff_in;
                    for (s = 1; s < DEPTH; s = s + 1) begin
                        pixel_q[s] <= pixel_q[s-1];
                        coeff_q[s] <= coeff_q[s-1];
                    end
                end
            end

            assign pixel_skewed[g] = (g == 0) ? pixel_in : pixel_q[DEPTH-1];
            assign coeff_skewed[g] = (g == 0) ? coeff_in : coeff_q[DEPTH-1];
        end
    endgenerate

    // Per-tap products, computed from the skewed operands. The operands are
    // padded to the DSP48E1 multiplier shape (a non-negative pixel on the 25-bit
    // A operand, the sign-extended coefficient on the 18-bit B operand) and
    // use_dsp forces the map.
    wire signed [SUM_WIDTH-1:0] tap_product[0:TAPS-1];

    genvar t;
    generate
        for (t = 0; t < TAPS; t = t + 1) begin : gen_tap
            wire signed [24:0] a_op = {{(25 - PIXEL_WIDTH) {1'b0}}, pixel_skewed[t]};
            wire signed [17:0] b_op = {{(18 - COEFF_WIDTH) {coeff_skewed[t][COEFF_WIDTH-1]}},
                                       coeff_skewed[t]};
            (* use_dsp = "yes" *) wire signed [42:0] product = a_op * b_op;

            assign tap_product[t] = product[SUM_WIDTH-1:0];
        end
    endgenerate

    // Accumulate chain: stage 0 is tap 0's product and each later stage adds one
    // more tap of the same window. Every stage maps to one DSP48E1 whose adder
    // consumes the running sum on its C input, so the reduction never leaves the
    // DSP columns.
    reg signed [SUM_WIDTH-1:0] acc_q[0:TAPS-1];

    integer k;
    always @(posedge clk_i or negedge rst_n_i) begin : chain
        if (!rst_n_i) begin
            for (k = 0; k < TAPS; k = k + 1) acc_q[k] <= {SUM_WIDTH{1'b0}};
        end else if (en_i) begin
            acc_q[0] <= tap_product[0];
            for (k = 1; k < TAPS; k = k + 1) acc_q[k] <= acc_q[k-1] + tap_product[k];
        end
    end

    assign sum_o = acc_q[TAPS-1];

endmodule
