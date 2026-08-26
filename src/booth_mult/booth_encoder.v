`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/25/2026
// Design Name: Booth encoder
// Module Name: booth_encoder
// Tool Versions: Vivado 2025.2
// Description: Radix-4 Booth encoder. Takes an overlapping 3-bit group of the
//              multiplier (y[2i+1], y[2i], y[2i-1]) and recodes it into a
//              signed digit in {-2,-1,0,+1,+2}, expressed as neg/is_two/is_one
//              control signals for the downstream partial-product selector.
// Dependencies: none (leaf module)
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module booth_encoder (
    input  wire [2:0] data_i,
    output reg        neg_o,
    output reg        is_one_o,
    output reg        is_two_o
);

    always @(*) begin
        case (data_i)
            3'b000:  {neg_o, is_two_o, is_one_o} = 3'b000;  //  0
            3'b001:  {neg_o, is_two_o, is_one_o} = 3'b001;  // +1
            3'b010:  {neg_o, is_two_o, is_one_o} = 3'b001;  // +1
            3'b011:  {neg_o, is_two_o, is_one_o} = 3'b010;  // +2
            3'b100:  {neg_o, is_two_o, is_one_o} = 3'b110;  // -2
            3'b101:  {neg_o, is_two_o, is_one_o} = 3'b101;  // -1
            3'b110:  {neg_o, is_two_o, is_one_o} = 3'b101;  // -1
            3'b111:  {neg_o, is_two_o, is_one_o} = 3'b000;  //  0
            default: {neg_o, is_two_o, is_one_o} = 3'b000;
        endcase
    end

endmodule
