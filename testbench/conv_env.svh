`ifndef CONV_ENV_SVH
`define CONV_ENV_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution environment
// Class Name: conv_env
// Tool Versions: Questa 2021
// Description: UVM environment for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

class conv_env #(
    `CONV_PARAMS_DECL
) extends uvm_env;

    `uvm_component_param_utils(conv_env#(`CONV_PARAMS_LIST))

    virtual conv_intf#(`CONV_PARAMS_LIST) conv_vif;

    conv_scoreboard#(`CONV_PARAMS_LIST) scoreboard_inst;
    conv_agent#(`CONV_PARAMS_LIST)      agent_inst;

    extern function new(string name = "conv_env", uvm_component parent);
    extern function void build_phase(uvm_phase phase);
    extern function void connect_phase(uvm_phase phase);
    extern task run_phase(uvm_phase phase);
endclass

function conv_env ::new(string name = "conv_env", uvm_component parent);
    super.new(name, parent);
endfunction

function void conv_env ::build_phase(uvm_phase phase);
    super.build_phase(phase);
    scoreboard_inst = conv_scoreboard#(`CONV_PARAMS_LIST)::type_id::create("scoreboard_inst", this);
    agent_inst      = conv_agent#(`CONV_PARAMS_LIST)::type_id::create("agent_inst", this);

    if(!uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::get(this, "", "conv_vif", conv_vif)) begin
        `uvm_fatal("NOVIF", "Virtual interface not defined! Simulation aborted!")
    end

    uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::set(this, "agent_inst", "conv_vif", conv_vif);
endfunction

function void conv_env ::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent_inst.agent_ap.connect(scoreboard_inst.score_ap);
endfunction

task conv_env ::run_phase(uvm_phase phase);
    super.run_phase(phase);
endtask

`endif
