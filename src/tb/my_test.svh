`ifndef MY_TEST_SVH
`define MY_TEST_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution base test
// Class Name: my_test
// Tool Versions: Questa 2021
// Description: Base UVM test for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

class my_test #(
    `CONV_PARAMS_DECL
) extends uvm_test;

    `uvm_component_param_utils(my_test#(`CONV_PARAMS_LIST))

    virtual conv_intf#(`CONV_PARAMS_LIST) conv_vif;
    conv_env#(`CONV_PARAMS_LIST)          env_inst;

    function new(string name = "my_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_inst = conv_env#(`CONV_PARAMS_LIST)::type_id::create("env_inst", this);
        if(!uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::get(this, "", "conv_vif", conv_vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not defined! Simulation aborted!")
        end
        uvm_config_db#(virtual conv_intf#(`CONV_PARAMS_LIST))::set(this, "env_inst", "conv_vif", conv_vif);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        conv_seq#(`CONV_PARAMS_LIST) seq;
        phase.raise_objection(this);

        seq = conv_seq#(`CONV_PARAMS_LIST)::type_id::create("seq");
        seq.start(env_inst.agent_inst.conv_sequencer_inst);

        phase.phase_done.set_drain_time(this, 1000ns);
        phase.drop_objection(this);
    endtask
endclass

`endif