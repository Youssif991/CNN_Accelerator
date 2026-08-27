`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Kernel Register Bank
// Module Name: kernel_reg_bank
// Tool Versions: Vivado 2025.2
// Description: NxN signed coefficient registers holding the programmable
//              kernel; provides the write port for kernel loading.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module kernel_reg_bank #(
    parameter N = 3,  // Kernel Size
    parameter COEFF_WIDTH = 8
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire load_valid_i,  // The Write Enable Signal
    input wire [$clog2(N*N)-1:0] load_addr_i,  // The address to write to
    input wire [COEFF_WIDTH-1:0] load_data_i,  // The data to write
    output wire [N*N*COEFF_WIDTH-1:0] kernel_o  // The kernel output
);

    // Kernel coefficients (current state)
    reg signed [COEFF_WIDTH-1:0] kernel_q[0:N*N-1];
    // Kernel coefficients (next-state)
    reg signed [COEFF_WIDTH-1:0] kernel_d[0:N*N-1];

    integer i;  // Loop index

    // Next-state
    always @(*) begin : next_state
        for (i = 0; i < N * N; i = i + 1) begin
            kernel_d[i] = kernel_q[i];  // Here we assign the default value
        end
        if (load_valid_i && (load_addr_i < N * N)) begin
            kernel_d[load_addr_i] = load_data_i; // Now we override the default value while making sure we do not go out of bounds
        end
    end

    // State update
    always @(posedge clk_i or negedge rst_n_i) begin : state
        if (!rst_n_i) begin
            for (i = 0; i < N * N; i = i + 1) begin
                kernel_q[i] <= 0;  // Reset all kernel values
            end
        end else begin
            for (i = 0; i < N * N; i = i + 1) begin
                kernel_q[i] <= kernel_d[i];  // Assign the next state
            end
        end
    end

    // Combinational read
    genvar g;
    generate
        for (g = 0; g < N * N; g = g + 1) begin : gen_kernel_out
            assign kernel_o[COEFF_WIDTH*g+:COEFF_WIDTH] = kernel_q[g]; // Flatten the kernel then assign the values to it
        end
    endgenerate

endmodule
