`ifndef CONV_MON_SVH
`define CONV_MON_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution monitor
// Class Name: conv_mon
// Tool Versions: Questa 2021
// Description: UVM monitor for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

class conv_mon #(
    `CONV_PARAMS_DECL
) extends uvm_monitor;

    `uvm_component_param_utils(conv_mon#(`CONV_PARAMS_LIST))

    virtual conv_intf#(`CONV_PARAMS_LIST) conv_vif;
    conv_seq_item#(`CONV_PARAMS_LIST)     conv_item;

    uvm_analysis_port #(conv_seq_item#(`CONV_PARAMS_LIST)) mon_ap;

    extern function new(string name = "conv_mon", uvm_component parent = null);
    extern function void build_phase(uvm_phase phase);
    extern function void connect_phase(uvm_phase phase);
    extern task run_phase(uvm_phase phase);
endclass

function conv_mon::new(string name = "conv_mon", uvm_component parent = null);
    super.new(name, parent);
    mon_ap = new("mon_ap", this);
endfunction

function void conv_mon::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::get(this, "", "conv_vif", conv_vif)) begin
        `uvm_fatal("NOVIF", "Virtual interface not defined! Simulation aborted!")
    end
endfunction

function void conv_mon::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
endfunction

task conv_mon::run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
        @(conv_vif.mon_cb);
        conv_item = conv_seq_item#(`CONV_PARAMS_LIST)::type_id::create("conv_item");
        conv_item.rst_n_i           = conv_vif.mon_cb.rst_n;
        conv_item.start_i           = conv_vif.mon_cb.start_i;
        conv_item.pixel_in_i        = conv_vif.mon_cb.pixel_in_i;
        conv_item.pixel_valid_i     = conv_vif.mon_cb.pixel_valid_i;
        conv_item.kernel_wr_valid_i = conv_vif.mon_cb.kernel_wr_valid_i;
        conv_item.kernel_wr_data_i  = conv_vif.mon_cb.kernel_wr_data_i;
        conv_item.relu_en_i         = conv_vif.mon_cb.relu_en_i;
        conv_item.result_ready_i    = conv_vif.mon_cb.result_ready_i;

        conv_item.busy_o         = conv_vif.mon_cb.busy_o;
        conv_item.done_o         = conv_vif.mon_cb.done_o;
        conv_item.state_o        = conv_vif.mon_cb.state_o;
        conv_item.result_valid_o = conv_vif.mon_cb.result_valid_o;
        conv_item.result_o       = conv_vif.mon_cb.result_o;
        conv_item.result_tlast_o = conv_vif.mon_cb.result_tlast_o;
        conv_item.ready_o        = conv_vif.mon_cb.ready_o;

        mon_ap.write(conv_item);
    end
endtask

`endif
