`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/25/2026
// Design Name: Radix-4 Booth Carry-Save Adder
// Module Name: carry_save_adder
// Tool Versions: Vivado 2025.2
// Description: 3:2 carry-save compressor (a bank of full adders). Computes
//              sum and carry independently per bit column, with no carry
//              propagation between columns - that propagation is deferred
//              to whatever final adder consumes sum_o/carry_o.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module carry_save_adder #(
    parameter WIDTH = 18
) (
    input  wire [WIDTH-1:0] a_i,
    input  wire [WIDTH-1:0] b_i,
    input  wire [WIDTH-1:0] c_i,
    output wire [WIDTH-1:0] sum_o,
    output wire [WIDTH-1:0] carry_o
);
    assign sum_o   = a_i ^ b_i ^ c_i;
    assign carry_o = (a_i & b_i) | (b_i & c_i) | (a_i & c_i);
endmodule