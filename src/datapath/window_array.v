`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Window Array
// Module Name: window_array
// Tool Versions: Vivado 2025.2
// Description: NxN register array forming the sliding convolution window;
//              shifts in the incoming pixel stream and presents the window
//              to the MAC array.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module window_array #(
    parameter N = 3,
    parameter PIXEL_WIDTH = 8
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire shift_valid_i,
    input wire [N*PIXEL_WIDTH-1:0] data_row_i,
    output wire [N*N*PIXEL_WIDTH-1:0] window_o
);

    // Current window state
    reg [PIXEL_WIDTH-1:0] window_q [0:N-1][0:N-1];

    // Next window state
    reg [PIXEL_WIDTH-1:0] window_d [0:N-1][0:N-1];

    // Loop variables
    integer i;
    integer j;

    // Next-state
    always @(*) begin : next_state
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                window_d[i][j] = window_q[i][j];  // default: hold
            end
        end
        if (shift_valid_i) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N - 1; j = j + 1) begin
                    window_d[i][j] = window_q[i][j+1];  // shift the row left
                end
                window_d[i][N-1] = data_row_i[i*PIXEL_WIDTH +: PIXEL_WIDTH];  // new column pixel
            end
        end
    end

    // State update
    always @(posedge clk_i or negedge rst_n_i) begin : state
        if (!rst_n_i) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    window_q[i][j] <= 0;
                end
            end
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    window_q[i][j] <= window_d[i][j];
                end
            end
        end
    end

    // Combinational read
    genvar g;
    generate
        for (g = 0; g < N * N; g = g + 1) begin : gen_window_out
            assign window_o[PIXEL_WIDTH*g +: PIXEL_WIDTH] = window_q[g / N][g % N];
        end
    endgenerate

endmodule
