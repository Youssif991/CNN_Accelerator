`ifndef CONV_AGENT_SVH
`define CONV_AGENT_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution agent
// Class Name: conv_agent
// Tool Versions: Questa 2021
// Description: UVM agent for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

class conv_agent #(
    `CONV_PARAMS_DECL
) extends uvm_agent;

    `uvm_component_param_utils(conv_agent#(`CONV_PARAMS_LIST))

    virtual conv_intf#(`CONV_PARAMS_LIST) conv_vif;
    conv_drv#(`CONV_PARAMS_LIST)          conv_driver_inst;
    conv_sequencer#(`CONV_PARAMS_LIST)    conv_sequencer_inst;
    conv_mon#(`CONV_PARAMS_LIST)          conv_monitor_inst;

    typedef conv_seq_item#(`CONV_PARAMS_LIST) conv_item;

    uvm_analysis_port #(conv_item) agent_ap;

    extern function new(string name = "conv_agent", uvm_component parent = null);
    extern function void build_phase(uvm_phase phase);
    extern function void connect_phase(uvm_phase phase);
endclass

function conv_agent::new(string name = "conv_agent", uvm_component parent = null);
    super.new(name, parent);
    agent_ap = new("agent_ap", this);
endfunction

function void conv_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    //-------component creation----------------
    conv_driver_inst    = conv_drv#(`CONV_PARAMS_LIST)::type_id::create("conv_driver_inst", this);
    conv_sequencer_inst = conv_sequencer#(`CONV_PARAMS_LIST)::type_id::create("conv_sequencer_inst", this);
    conv_monitor_inst   = conv_mon#(`CONV_PARAMS_LIST)::type_id::create("conv_monitor_inst", this);

    //---------interface binding----------------------
    if(!uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::get(this, "", "conv_vif", conv_vif)) begin
        `uvm_fatal("NOVIF", "Virtual interface not defined! Simulation aborted!")
    end
    uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::set(this, "conv_driver_inst", "conv_vif", conv_vif);
    uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::set(this, "conv_monitor_inst", "conv_vif", conv_vif);

endfunction

function void conv_agent::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    conv_driver_inst.seq_item_port.connect(conv_sequencer_inst.seq_item_export);
    conv_monitor_inst.mon_ap.connect(agent_ap);
endfunction

`endif
