`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/24/2026
// Design Name: Radix-4 Booth Multiplier
// Module Name: booth_mult_r4
// Tool Versions: Vivado 2025.2
// Description: Radix-4 Booth multiplier. Multiplies an unsigned pixel by a
//              signed kernel coefficient, producing a signed product of
//              width PROD_WIDTH = PIXEL_WIDTH + COEFF_WIDTH + 2 (18 bits
//              with the default 8-bit operands), ready for the convolution
//              MAC array. The pixel is radix-4 recoded by the encoder, the
//              coefficient is the multiplicand for the partial-product
//              selector, and the 5 partial-product rows feed the compressor
//              and the final carry-propagate adder.
//
// Dependencies: booth_encoder (booth_encoder.v)
//               booth_pp_selector (booth_pp_selector.v)
//               booth_pp_compressor (booth_pp_compressor.v)
//               booth_final_adder (booth_final_adder.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module booth_mult_r4 #(
    parameter PIXEL_WIDTH = 8,
    parameter COEFF_WIDTH = 8,
    parameter PROD_WIDTH  = PIXEL_WIDTH + COEFF_WIDTH + 2
) (
    input  wire [PIXEL_WIDTH-1:0]        pixel_i,  // The Pixel value
    input  wire signed [COEFF_WIDTH-1:0] coeff_i,  // The coefficient to multiply by
    output wire signed [PROD_WIDTH-1:0]  prod_o    // The product output
);

    // Parameters
    localparam NUM_GROUPS = 5; // Number of groups of the booth's algorithm
    localparam X_EXT_WIDTH = COEFF_WIDTH + 2; // Extended width of the coefficient
    localparam Y_EXT_WIDTH = PIXEL_WIDTH + 2; // Extended width of the pixel

    // Wires for internal connections
    wire signed [X_EXT_WIDTH-1:0] x_ext = {
        {2{coeff_i[COEFF_WIDTH-1]}}, coeff_i
    };  // Sign extend the coefficient, and also will be the input to the selector

    wire [Y_EXT_WIDTH-1:0] y_ext = {
        2'b00, pixel_i
    };  // Here I zero-extended the y because the pixel is unsigned and booth needs an even width
    wire [Y_EXT_WIDTH:0] y_prime = {
        y_ext, 1'b0
    };  // Now for the booth algorithm to work right we put the extra y[-1] index

    wire [2:0] data_i[NUM_GROUPS-1:0];  // Inputs data to the encoder
    wire is_one_i[NUM_GROUPS-1:0];  // The multiply by one flag output for the encoder
    wire is_two_i[NUM_GROUPS-1:0];  // The multiply by two flag output for the encoder
    wire is_neg_i[NUM_GROUPS-1:0];  // The negative flag output for the encoder
    wire [X_EXT_WIDTH-1:0] partial_product_o[NUM_GROUPS-1:0];  // Output of the partial product
    wire [PROD_WIDTH-1:0] row[NUM_GROUPS-1:0];  // Rows from the output of the partial product
    wire [PROD_WIDTH-1:0] sum_final;  // The final sum that will come out of the compressor
    wire [PROD_WIDTH-1:0] carry_final;  // The final carry that will come out of the compressor

    genvar i;  // The generate loop variable

    generate
        for (i = 0; i < NUM_GROUPS; i = i + 1) begin : gen_pp_rows
            // Now we assign the data input for each group
            assign data_i[i] = y_prime[2*i+2 : 2*i];

            booth_encoder u_encoder (
                .data_i  (data_i[i]),
                .neg_o   (is_neg_i[i]),
                .is_one_o(is_one_i[i]),
                .is_two_o(is_two_i[i])
            );  // Instantiate the encoder for each group

            booth_pp_selector #(
                .WIDTH(X_EXT_WIDTH)
            ) u_partial_product_sel (
                .x_ext_i          (x_ext),
                .neg_i            (is_neg_i[i]),
                .is_one_i         (is_one_i[i]),
                .is_two_i         (is_two_i[i]),
                .partial_product_o(partial_product_o[i])
            );  // Instantiate the partial product for each group

            wire [PROD_WIDTH-1:0] pp_ext;
            assign pp_ext = {{(PROD_WIDTH - X_EXT_WIDTH){partial_product_o[i][X_EXT_WIDTH-1]}},
                             partial_product_o[i]};
            assign row[i] = pp_ext << (2 * i);
            // So this step is just sign extending the partial product first
            // for the correct product width then shifting it to the right position
        end
    endgenerate

    booth_pp_compressor #(
        .WIDTH(PROD_WIDTH)
    ) u_partial_product_compressor (
        .row0_i (row[0]),
        .row1_i (row[1]),
        .row2_i (row[2]),
        .row3_i (row[3]),
        .row4_i (row[4]),
        .sum_o  (sum_final),
        .carry_o(carry_final)
    );  // Instantiate the partial product compressor

    booth_final_adder #(
        .WIDTH(PROD_WIDTH)
    ) u_final_adder (
        .sum_i     (sum_final),
        .carry_i   (carry_final),
        .product_o (prod_o)
    );  // Instantiate the final adder and finally we get that product value

endmodule
