`ifndef CONV_PARAMS_SVH
`define CONV_PARAMS_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution parameters
// Class Name: conv_params
// Tool Versions: Questa 2021
// Description: Parameter definitions for convolution accelerator
// Dependencies: None
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

// -----------------------------------------------------------------------
// Single source of truth for the accelerator_top parameter set.
// `CONV_PARAMS_DECL  -> use when DECLARING a parameterized class/interface
// `CONV_PARAMS_LIST  -> use when REFERENCING a specialization, e.g.
//                        conv_seq_item#(`CONV_PARAMS_LIST)
// -----------------------------------------------------------------------

`define CONV_PARAMS_DECL \
    parameter int N              = 5,  \
    parameter int IMAGE_WIDTH    = 8, \
    parameter int IMAGE_HEIGHT   = 8, \
    parameter int PIXEL_WIDTH    = 8,  \
    parameter int COEFF_WIDTH    = 8,  \
    parameter int OUT_WIDTH      = 16, \
    parameter int ROUND_ENABLE   = 1,  \
    parameter int FRAC_BITS      = 4,  \
    parameter int PIPE_STAGES    = 2,  \
    parameter int PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT), \
    parameter int PROD_WIDTH     = PIXEL_WIDTH + COEFF_WIDTH + 2,      \
    parameter int SUM_WIDTH      = PROD_WIDTH + $clog2(N*N)

`define CONV_PARAMS_LIST \
    N, IMAGE_WIDTH, IMAGE_HEIGHT, PIXEL_WIDTH, COEFF_WIDTH, OUT_WIDTH, ROUND_ENABLE, FRAC_BITS, PIPE_STAGES, PIX_ADDR_WIDTH, PROD_WIDTH, SUM_WIDTH

`endif
