`ifndef CONV_PARAMS_SVH
`define CONV_PARAMS_SVH

//******************************************************************************
// Engineer : Marwan
// Create Date: 08/27/2026
// Design Name: uvm convolution parameters
// Class Name: conv_params
// Tool Versions: Questa 2021
// Description: Parameter-declaration macros for the convolution testbench.
// Dependencies: conv_params_pkg.svh
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - CONV_PARAMS_DECL defaults now reference conv_params_pkg
//                  (the single source of truth) instead of hardcoded
//                  literals, so the values only need to change in one
//                  place (conv_params_pkg.svh).
// Additional Comments:
//******************************************************************************

// -----------------------------------------------------------------------
// Single source of truth for the accelerator_top parameter set.
//
// conv_params_pkg holds the ACTUAL literal values. Every other file that
// needs one of these numbers (conv_top.sv's localparams, conv_test.svh's
// base-class specialization, etc.) should reference conv_params_pkg::<name>
// instead of re-typing a literal, so changing a dimension here is the only
// edit needed anywhere in the testbench.
//
// `CONV_PARAMS_DECL  -> use when DECLARING a parameterized class/interface
//                        (its defaults come from conv_params_pkg, not
//                        from hardcoded numbers)
// `CONV_PARAMS_LIST  -> use when REFERENCING a specialization, e.g.
//                        conv_seq_item#(`CONV_PARAMS_LIST)
// -----------------------------------------------------------------------

`define CONV_PARAMS_DECL \
    parameter int N              = conv_params_pkg::N,              \
    parameter int N_Kernel       = conv_params_pkg::N_Kernel,       \
    parameter int IMAGE_WIDTH    = conv_params_pkg::IMAGE_WIDTH,    \
    parameter int IMAGE_HEIGHT   = conv_params_pkg::IMAGE_HEIGHT,   \
    parameter int PIXEL_WIDTH    = conv_params_pkg::PIXEL_WIDTH,    \
    parameter int COEFF_WIDTH    = conv_params_pkg::COEFF_WIDTH,    \
    parameter int OUT_WIDTH      = conv_params_pkg::OUT_WIDTH,      \
    parameter int ROUND_ENABLE   = conv_params_pkg::ROUND_ENABLE,   \
    parameter int FRAC_BITS      = conv_params_pkg::FRAC_BITS,      \
    parameter int PIPE_STAGES    = conv_params_pkg::PIPE_STAGES,    \
    parameter int PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT), \
    parameter int PROD_WIDTH     = PIXEL_WIDTH + COEFF_WIDTH + 2,      \
    parameter int SUM_WIDTH      = PROD_WIDTH + $clog2(N*N)

`define CONV_PARAMS_LIST \
    N, N_Kernel, IMAGE_WIDTH, IMAGE_HEIGHT, PIXEL_WIDTH, COEFF_WIDTH, OUT_WIDTH, ROUND_ENABLE, FRAC_BITS, PIPE_STAGES, PIX_ADDR_WIDTH, PROD_WIDTH, SUM_WIDTH

`endif
