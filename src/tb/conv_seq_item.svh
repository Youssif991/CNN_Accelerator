`ifndef CONV_SEQ_ITEM_SVH
`define CONV_SEQ_ITEM_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution sequence item
// Class Name: conv_seq_item
// Tool Versions: Questa 2021
// Description: UVM sequence item for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

class conv_seq_item #(
    `CONV_PARAMS_DECL
) extends uvm_sequence_item;

    `uvm_object_param_utils(conv_seq_item#(`CONV_PARAMS_LIST))

    bit                   rst_n_i;
    bit                   start_i;
    bit [PIXEL_WIDTH-1:0] pixel_in_i;
    bit                   pixel_valid_i;
    bit                   kernel_wr_valid_i;
    bit [COEFF_WIDTH-1:0] kernel_wr_data_i;
    bit                   relu_en_i;
    bit                   result_ready_i;

    bit                   busy_o;
    bit                   done_o;
    bit [2:0]             state_o;
    bit                   result_valid_o;
    bit [OUT_WIDTH-1:0]   result_o;
    bit                   result_tlast_o;
    bit                   ready_o;

    function new(string name = "conv_seq_item");
        super.new(name);
    endfunction

endclass

`endif