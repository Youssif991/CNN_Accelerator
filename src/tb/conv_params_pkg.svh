`ifndef CONV_PARAMS_PKG_SVH
`define CONV_PARAMS_PKG_SVH

//******************************************************************************
// Engineer : Marwan
// Create Date: 08/27/2026
// Design Name: uvm convolution parameters package
// Class Name: conv_params_pkg
// Tool Versions: Questa 2021
// Description: Single source of truth for the accelerator_top parameter set.
//
//              This is the ONLY place the actual literal values live.
//              Every other testbench file that needs one of these numbers
//              (conv_params.svh's CONV_PARAMS_DECL defaults, conv_test.svh's
//              base-class specialization, conv_top.sv's localparams)
//              references conv_params_pkg::<name> instead of re-typing a
//              literal, so changing a dimension here is the only edit
//              needed anywhere in the testbench.
//
//              Compile-order requirement: this package must be compiled
//              BEFORE anything that references conv_params_pkg:: (that
//              includes conv_params.svh, conv_pack.svh and conv_top.sv).
//              Make sure your filelist / compile order lists this file
//              first.
// Dependencies: None
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

package conv_params_pkg;
    localparam int N              = 3;
    localparam int N_Kernel       = 1;
    localparam int IMAGE_WIDTH    = 64;
    localparam int IMAGE_HEIGHT   = 64;
    localparam int PIXEL_WIDTH    = 8;
    localparam int COEFF_WIDTH    = 8;
    localparam int OUT_WIDTH      = 16;
    localparam int ROUND_ENABLE   = 1;
    localparam int FRAC_BITS      = 4;
    localparam int PIPE_STAGES    = N*N + 2; // mac_chain's N^2 DSP multiply-adders + sat_round's 2 stages 
    localparam int PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT);
    localparam int PROD_WIDTH     = PIXEL_WIDTH + COEFF_WIDTH + 2;
    localparam int SUM_WIDTH      = PROD_WIDTH + $clog2(N*N);
endpackage

`endif
