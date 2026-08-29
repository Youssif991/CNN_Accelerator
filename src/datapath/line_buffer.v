`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Line Buffer
// Module Name: line_buffer
// Tool Versions: Vivado 2025.2
// Description: Row buffer that delays one row of the input feature map;
//              feeds the sliding-window generator. Reset-free by design:
//              SRLC32Es have no reset pin (an async reset forces extra
//              flip-flops out of the SRL chain), and the frame controller
//              produces no outputs during FILL, so the (N-1) row of priming
//              shifts overwrite the whole buffer before the first output.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module line_buffer #(
    parameter IMAGE_WIDTH = 32,
    parameter PIXEL_WIDTH = 8
) (
    input  wire                   clk_i,
    input  wire                   shift_valid_i,  // shift enable
    input  wire [PIXEL_WIDTH-1:0] pixel_in_i,     // the incoming pixel
    output wire [PIXEL_WIDTH-1:0] pixel_out_o     // the pixel from one row ago
);

    // Line storage
    reg [PIXEL_WIDTH-1:0] line_q[0:IMAGE_WIDTH-1];

    integer i;  // Loop index

    // State update (no reset: the fill phase primes the buffer)
    always @(posedge clk_i) begin : state
        if (shift_valid_i) begin
            for (i = IMAGE_WIDTH - 1; i > 0; i = i - 1) line_q[i] <= line_q[i-1];
            line_q[0] <= pixel_in_i;
        end
    end

    // Combinational read: the oldest pixel is the delayed row output
    assign pixel_out_o = line_q[IMAGE_WIDTH-1];

endmodule
