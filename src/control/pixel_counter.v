`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Control - Pixel Position Counter
// Module Name: pixel_counter
// Tool Versions: Vivado 2025.2
// Description: Counts accepted input pixels (en_i, gated with the pixel
//              stream valid in the top) from 0..IMAGE_WIDTH*IMAGE_HEIGHT-1
//              in row-major order, wraps back to zero, and pulses last_o
//              while the final pixel is accepted. The count is the frame
//              position reference for the controller: the FSM derives the
//              window block completion, the fill length, and the frame end
//              from it, so a deasserted stream valid stalls the count and
//              the whole pipeline stays synchronized.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module pixel_counter #(
    parameter IMAGE_WIDTH = 32,  // Input feature-map width
    parameter IMAGE_HEIGHT = 32,  // Input feature-map height
    parameter ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT)
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire en_i,  // Count enable
    input wire rst_count_i,  // Restart the count at zero
    output wire [ADDR_WIDTH-1:0] addr_o,  // Row-major pixel index (stream position)
    output wire last_o  // Pulse while the final pixel is accepted
);

    localparam TOTAL = IMAGE_WIDTH * IMAGE_HEIGHT;

    // Pixel count (current state)
    reg [ADDR_WIDTH-1:0] count_q;
    // Pixel count (next state)
    reg [ADDR_WIDTH-1:0] count_d;

    // Next-state
    always @(*) begin : next_state
        if (rst_count_i) begin
            count_d = 0;
        end else if (en_i) begin
            count_d = (count_q == TOTAL-1) ? 0 : count_q + 1;
        end else begin
            count_d = count_q;
        end
    end

    // State update
    always @(posedge clk_i or negedge rst_n_i) begin : state
        if (!rst_n_i) begin
            count_q <= 0;
        end else begin
            count_q <= count_d;
        end
    end

    // Output decode
    assign addr_o = count_q;
    assign last_o = en_i && (count_q == TOTAL-1);

endmodule
