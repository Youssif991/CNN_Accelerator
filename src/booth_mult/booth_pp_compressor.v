`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/25/2026
// Design Name: Radix-4 Booth Partial Product Compressor
// Module Name: booth_pp_compressor
// Tool Versions: Vivado 2025.2
// Description: Carry-save reduction tree. Reduces the 5 shifted/sign-
//              extended partial product rows down to 2 rows (sum, carry)
//              using 3 chained 3:2 carry-save compression stages, built from
//              the carry_save_adder module.
//
// Dependencies: booth_pp_selector (booth_pp_selector.v) - produces the
//               row0_i..row4_i inputs this module consumes
//               carry_save_adder (carry_save_adder.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module booth_pp_compressor #(
    parameter WIDTH = 18
) (
    input  wire [WIDTH-1:0] row0_i,
    input  wire [WIDTH-1:0] row1_i,
    input  wire [WIDTH-1:0] row2_i,
    input  wire [WIDTH-1:0] row3_i,
    input  wire [WIDTH-1:0] row4_i,
    output wire [WIDTH-1:0] sum_o,
    output wire [WIDTH-1:0] carry_o
);
    // Stage 1
    wire [WIDTH-1:0] sum1, carry1;
    carry_save_adder #(
        .WIDTH(WIDTH)
    ) u_csa_s1 (
        .a_i(row0_i),
        .b_i(row1_i),
        .c_i(row2_i),
        .sum_o(sum1),
        .carry_o(carry1)
    );
    wire [WIDTH-1:0] carry1_sh = carry1 << 1;
    // Stage 2
    wire [WIDTH-1:0] sum2, carry2;
    carry_save_adder #(
        .WIDTH(WIDTH)
    ) u_csa_s2 (
        .a_i(sum1),
        .b_i(carry1_sh),
        .c_i(row3_i),
        .sum_o(sum2),
        .carry_o(carry2)
    );
    wire [WIDTH-1:0] carry2_sh = carry2 << 1;
    // Stage 3
    wire [WIDTH-1:0] carry3;
    carry_save_adder #(
        .WIDTH(WIDTH)
    ) u_csa_s3 (
        .a_i(sum2),
        .b_i(carry2_sh),
        .c_i(row4_i),
        .sum_o(sum_o),
        .carry_o(carry3)
    );
    assign carry_o = carry3 << 1;
endmodule
