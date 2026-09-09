`ifndef CONV_DRV_SVH
`define CONV_DRV_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution driver
// Class Name: conv_drv
// Tool Versions: Questa 2021
// Description: UVM driver for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

class conv_drv #(
    `CONV_PARAMS_DECL
) extends uvm_driver #(conv_seq_item#(`CONV_PARAMS_LIST));

    `uvm_component_param_utils(conv_drv#(`CONV_PARAMS_LIST))

    virtual conv_intf#(`CONV_PARAMS_LIST) conv_vif;
    conv_seq_item#(`CONV_PARAMS_LIST)     conv_item;

    extern function new(string name = "conv_drv", uvm_component parent = null);
    extern function void build_phase(uvm_phase phase);
    extern function void connect_phase(uvm_phase phase);
    extern task run_phase(uvm_phase phase);
endclass

function conv_drv ::new(string name = "conv_drv", uvm_component parent = null);
    super.new(name, parent);
endfunction

function void conv_drv ::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::get(this, "", "conv_vif", conv_vif)) begin
        `uvm_fatal("NOVIF", "Virtual interface not defined! Simulation aborted!")
    end
endfunction

function void conv_drv::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
endfunction

task conv_drv ::run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
        seq_item_port.get_next_item(conv_item);
        @(conv_vif.drv_cb);
        conv_vif.drv_cb.start_i           <= conv_item.start_i;
        conv_vif.drv_cb.pixel_in_i        <= conv_item.pixel_in_i;
        conv_vif.drv_cb.pixel_valid_i     <= conv_item.pixel_valid_i;
        conv_vif.drv_cb.kernel_wr_valid_i <= conv_item.kernel_wr_valid_i;
        conv_vif.drv_cb.kernel_wr_data_i  <= conv_item.kernel_wr_data_i;
        conv_vif.drv_cb.relu_en_i         <= conv_item.relu_en_i;
        conv_vif.drv_cb.result_ready_i    <= conv_item.result_ready_i;

        seq_item_port.item_done();
    end
endtask

`endif
