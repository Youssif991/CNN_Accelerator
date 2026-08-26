`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/25/2026
// Design Name: Radix-4 Booth Final Adder
// Module Name: final_adder
// Tool Versions: Vivado 2025.2
// Description: Final carry-propagate adder for the Booth multiplier. Combines
//              the sum/carry row pair produced by the CSA compressor tree
//              into the resolved two's-complement product.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module final_adder #(
    parameter WIDTH = 18
) (
    input  wire [WIDTH-1:0] sum_i,
    input  wire [WIDTH-1:0] carry_i,
    output wire [WIDTH-1:0] product_o
);

  assign product_o = sum_i + carry_i;

endmodule