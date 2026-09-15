`ifndef CONV_TEST_SVH
`define CONV_TEST_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution test
// Class Name: conv_test
// Tool Versions: Questa 2021
// Description: UVM test for convolution accelerator verification
// Dependencies: my_test.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

// Extend the parameterized base test and pass the design parameters

class conv_test extends my_test #(
    .N(3),
    .IMAGE_WIDTH(8),
    .IMAGE_HEIGHT(8),
    .PIXEL_WIDTH(8),
    .COEFF_WIDTH(8),
    .OUT_WIDTH(16),
    .ROUND_ENABLE(1),
    .FRAC_BITS(4),
    .PIPE_STAGES(11)
);


/*

    .N(conv_params_pkg::N),
    .IMAGE_WIDTH(conv_params_pkg::IMAGE_WIDTH),
    .IMAGE_HEIGHT(conv_params_pkg::IMAGE_HEIGHT),
    .PIXEL_WIDTH(conv_params_pkg::PIXEL_WIDTH),
    .COEFF_WIDTH(conv_params_pkg::COEFF_WIDTH),
    .OUT_WIDTH(conv_params_pkg::OUT_WIDTH),
    .ROUND_ENABLE(conv_params_pkg::ROUND_ENABLE),
    .FRAC_BITS(conv_params_pkg::FRAC_BITS),
    .PIPE_STAGES(conv_params_pkg::PIPE_STAGES)
);
*/


    // Register this non-parameterized specialization with the factory
    `uvm_component_utils(conv_test)

    function new(string name = "conv_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif