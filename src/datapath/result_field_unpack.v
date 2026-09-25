`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/22/2026
// Design Name: CNN Convolution Datapath - Result Field Unpack
// Module Name: result_field_unpack
// Tool Versions: Vivado 2025.2
// Description: Splits the output FIFO's {last, kernel_idx, result} read word
//              back into the top level's individual result_valid_o/result_o/
//              result_kernel_idx_o/result_tlast_o ports.
//
//              Extracted verbatim out of accelerator_top (previously these
//              four bit-slice assigns lived directly in the top module). Same
//              slicing, just moved into its own leaf module and instantiated
//              from the top. No functional change.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created (extracted from accelerator_top).
//////////////////////////////////////////////////////////////////////////////////

module result_field_unpack #(
    parameter OUT_WIDTH  = 16,
    parameter KIDX_WIDTH = 1
) (
    input  wire                          fifo_rd_valid_i,
    input  wire [OUT_WIDTH+KIDX_WIDTH:0] fifo_rd_data_i,      // {last, kernel_idx, result}
    output wire                          result_valid_o,
    output wire [OUT_WIDTH-1:0]          result_o,
    output wire [KIDX_WIDTH-1:0]         result_kernel_idx_o,
    output wire                          result_tlast_o
);

    assign result_valid_o      = fifo_rd_valid_i;
    assign result_o            = fifo_rd_data_i[OUT_WIDTH-1:0];
    assign result_kernel_idx_o = fifo_rd_data_i[OUT_WIDTH +: KIDX_WIDTH];
    assign result_tlast_o      = fifo_rd_data_i[OUT_WIDTH+KIDX_WIDTH];

endmodule
