`ifndef CONV_INTF_SVH
`define CONV_INTF_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution interface
// Class Name: conv_intf
// Tool Versions: Questa 2021
// Description: Virtual interface for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

interface conv_intf #(
    `CONV_PARAMS_DECL
) (input bit clk, input bit rst_n);

    logic                   start_i;
    logic [PIXEL_WIDTH-1:0] pixel_in_i;
    logic                   pixel_valid_i;
    logic                   kernel_wr_valid_i;
    logic [COEFF_WIDTH-1:0] kernel_wr_data_i;
    logic                   relu_en_i;
    logic                   result_ready_i;

    logic                   busy_o;
    logic                   done_o;
    logic [2:0]             state_o;
    logic                   result_valid_o;
    logic [OUT_WIDTH-1:0]   result_o;
    logic                   result_tlast_o;
    logic                   ready_o;

    clocking mon_cb @(posedge clk);
        input rst_n;
        input start_i;
        input pixel_in_i;
        input pixel_valid_i;
        input kernel_wr_valid_i;
        input kernel_wr_data_i;
        input relu_en_i;
        input result_ready_i;

        input busy_o;
        input done_o;
        input state_o;
        input result_valid_o;
        input result_o;
        input result_tlast_o;
        input ready_o;
    endclocking

    clocking drv_cb @(posedge clk);
        //output rst_n;
        output start_i;
        output pixel_in_i;
        output pixel_valid_i;
        output kernel_wr_valid_i;
        output kernel_wr_data_i;
        output relu_en_i;
        output result_ready_i;
    endclocking

endinterface

`endif
