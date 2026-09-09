`ifndef CONV_SEQUENCER_SVH
`define CONV_SEQUENCER_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution sequencer
// Class Name: conv_sequencer
// Tool Versions: Questa 2021
// Description: UVM sequencer for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

class conv_sequencer #(
    `CONV_PARAMS_DECL
) extends uvm_sequencer #(conv_seq_item#(`CONV_PARAMS_LIST));

    `uvm_component_param_utils(conv_sequencer#(`CONV_PARAMS_LIST))

    function new(string name = "conv_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif