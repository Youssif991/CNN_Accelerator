`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/04/2026
// Design Name: CNN Convolution Datapath - DSP Multiplier
// Module Name: dsp_mult_r4
// Tool Versions: Vivado 2025.2
// Description: DSP48E1 multiplier for the convolution MAC array. Multiplies
//              an unsigned pixel by a signed kernel coefficient and produces
//              the signed product on the next clock edge. The operands
//              are padded to the DSP48E1 multiplier shape (a non-negative
//              pixel on the 25-bit A operand, the sign-extended coefficient on
//              the 18-bit B operand) and the (* use_dsp = "yes" *) attribute
//              forces synthesis to map each instance to a single DSP48E1
//              (Vivado would otherwise constant-fold the padding back to a
//              small LUT multiply). The output register is the MAC pipeline
//              stage 1: it replaces the explicit products_p1 register of the
//              LUT path, so the total pipeline depth (and the valid alignment)
//              is unchanged. The register is clock-enabled (en_i) so it belongs
//              to the same freeze domain as the other pipeline stages: when
//              the output consumer stalls (en_i low) the product holds and no
//              result is lost. The register has no reset on purpose: a
//              DSP48E1 P register has no asynchronous reset, and the
//              result-valid flag gates every consumer until real results flow,
//              so an uninitialized product is never observed (same reasoning
//              as the reset-free line buffers).
//
// Dependencies: none (leaf module, DSP48E1 inference)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module dsp_mult_r4 #(
    parameter PIXEL_WIDTH = 8,  // Unsigned pixel width
    parameter COEFF_WIDTH = 8,  // Signed coefficient width
    parameter PROD_WIDTH  = PIXEL_WIDTH + COEFF_WIDTH + 2
) (
    input wire clk_i,  // Product register clock
    input wire en_i,  // Clock enable (pipeline freeze: hold the product while low)
    input wire [PIXEL_WIDTH-1:0] pixel_i,  // The Pixel value (unsigned)
    input wire signed [COEFF_WIDTH-1:0] coeff_i,  // The coefficient to multiply by
    output wire signed [PROD_WIDTH-1:0] prod_o  // The product output (registered)
);
.
    wire signed [24:0] a_op = {{(25 - PIXEL_WIDTH) {1'b0}}, pixel_i};
    wire signed [17:0] b_op = {{(18 - COEFF_WIDTH) {coeff_i[COEFF_WIDTH-1]}}, coeff_i};
    (* use_dsp = "yes" *) wire signed [42:0] product = a_op * b_op;

    reg signed [PROD_WIDTH-1:0] prod_q;
    always @(posedge clk_i) begin : product_reg
        if (en_i) prod_q <= product[PROD_WIDTH-1:0];
    end

    assign prod_o = prod_q;

endmodule
