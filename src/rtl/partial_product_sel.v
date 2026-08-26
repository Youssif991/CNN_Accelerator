`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: MM/DD/YYYY
// Design Name: Partial Product Selector
// Module Name: partial_product_sel
// Tool Versions: Vivado 2025.2
// Description: LUT-based partial product selector. Given the Booth digit controls from
// booth_encoder, selects 0, +X, +2X, -X, or -2X as a combinational case statement.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module partial_product_sel #(
    parameter WIDTH = 9
) (
    input  wire [WIDTH-1:0] x_ext_i,
    input  wire             neg_i,
    input  wire             is_one_i,
    input  wire             is_two_i,
    output reg  [WIDTH-1:0] partial_product_o
);

    always @(*) begin
        case ({
            is_two_i, is_one_i
        })
            2'b00:   partial_product_o = {WIDTH{1'b0}};  // 0
            2'b01:   partial_product_o = x_ext_i;  // 1x
            2'b10:   partial_product_o = x_ext_i << 1;  // 2x (left shift; wraps mod 2^WIDTH)
            default: partial_product_o = {WIDTH{1'b0}};
        endcase

        if (neg_i) partial_product_o = (~partial_product_o) + 1'b1;  // two's-complement negate
    end
endmodule
