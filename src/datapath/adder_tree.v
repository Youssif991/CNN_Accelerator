`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Adder Tree
// Module Name: adder_tree
// Tool Versions: Vivado 2025.2
// Description: Pipelined adder tree summing the NxN MAC products into the
//              convolution result for one output pixel. Currently a
//              combinational sum (synthesis balances it into a tree); a
//              pipeline stage can be added later to raise Fmax.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module adder_tree #(
    parameter N = 3,
    parameter PROD_WIDTH = 18,
    parameter SUM_WIDTH  = PROD_WIDTH + $clog2(N*N)
) (
    input  wire [N*N*PROD_WIDTH-1:0] products_i,  // flattened NxN products
    output wire signed [SUM_WIDTH-1:0] sum_o      // signed sum of all products
);

    // Running sum
    reg signed [SUM_WIDTH-1:0] sum_acc;

    integer k;  // tap loop counter

    always @(*) begin : sum_all
        sum_acc = {SUM_WIDTH{1'b0}};
        for (k = 0; k < N*N; k = k + 1) begin
            sum_acc = sum_acc + $signed(products_i[PROD_WIDTH*k +: PROD_WIDTH]);
        end
    end

    assign sum_o = sum_acc;

endmodule
