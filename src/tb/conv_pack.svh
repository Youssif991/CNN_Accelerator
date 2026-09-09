`ifndef CONV_PACK_SVH
`define CONV_PACK_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution package
// Class Name: conv_pack
// Tool Versions: Questa 2021
// Description: UVM package for convolution accelerator verification
// Dependencies: All conv_*.svh files
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

package conv_pack;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "conv_params.svh"
    `include "conv_seq_item.svh"
    `include "conv_seq.svh"
    `include "conv_sequencer.svh"
    `include "conv_drv.svh"
    `include "conv_mon.svh"
    `include "conv_agent.svh"
    `include "conv_scoreboard.svh"
    `include "conv_env.svh"
    `include "my_test.svh"
    `include "conv_test.svh"
endpackage

`endif
