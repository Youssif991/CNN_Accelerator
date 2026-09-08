`ifndef CONV_SCOREBOARD_SVH
`define CONV_SCOREBOARD_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution scoreboard
// Class Name: conv_scoreboard
// Tool Versions: Questa 2021
// Description: UVM scoreboard for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"

class conv_scoreboard #(
    `CONV_PARAMS_DECL
) extends uvm_scoreboard;

    `uvm_component_param_utils(conv_scoreboard#(`CONV_PARAMS_LIST))

    uvm_analysis_imp #(conv_seq_item#(`CONV_PARAMS_LIST),
                       conv_scoreboard#(`CONV_PARAMS_LIST)) score_ap;

    typedef conv_seq_item#(`CONV_PARAMS_LIST) conv_item;


    bit signed [OUT_WIDTH-1:0] expected_results[$];

    int kernel_count;
    int pixel_count;
    int output_count;
    int error_count;

    extern function new(string name = "conv_scoreboard",
                        uvm_component parent = null);
    extern function void build_phase(uvm_phase phase);
    extern function void write(conv_item item);
    extern function void check_phase(uvm_phase phase);
    extern function void load_expected_results();
    extern function void report_phase(uvm_phase phase);

endclass

function conv_scoreboard::new(
    string name = "conv_scoreboard",
    uvm_component parent = null
);
    super.new(name, parent);
endfunction

function void conv_scoreboard::build_phase(uvm_phase phase);
    super.build_phase(phase);

    score_ap = new("score_ap", this);
    kernel_count = 0;
    pixel_count  = 0;
    output_count = 0;
    error_count  = 0;

    load_expected_results();
endfunction

function void conv_scoreboard::load_expected_results();
    integer file_id;
    integer scan_status;
    integer unsigned file_value;
    bit signed [OUT_WIDTH-1:0] expected_value;

    file_id = $fopen("expected_output.hex", "r");

    if (file_id == 0) begin
        `uvm_fatal("GOLDEN_FILE",
                   "Cannot open expected_output.hex. Check the simulator working directory.")
    end

    while (!$feof(file_id)) begin
        scan_status = $fscanf(file_id, "%h\n", file_value);

        if (scan_status == 1) begin
            expected_value = file_value[OUT_WIDTH-1:0];
            expected_results.push_back(expected_value);
        end
    end

    $fclose(file_id);

    `uvm_info("GOLDEN_FILE",
              $sformatf("Loaded %0d expected results", expected_results.size()),
              UVM_LOW)
endfunction

function void conv_scoreboard::write(
    conv_item item
);
    bit signed [OUT_WIDTH-1:0] expected_value;
    bit signed [OUT_WIDTH-1:0] actual_value;
    int signed coefficient_value;

    // Active-low asynchronous reset.
    if (!item.rst_n_i) begin
        expected_results.delete();
        load_expected_results();
        kernel_count = 0;
        pixel_count  = 0;
        output_count = 0;
        return;
    end

    // The sequence and MATLAB must use the same coefficient order.
    if (item.kernel_wr_valid_i) begin
        kernel_count++;
    end

    // Count only accepted/valid input pixels.
    if (item.pixel_valid_i) begin
        pixel_count++;
    end

    // Compare only when the DUT output handshake occurs.
    if (item.result_valid_o && item.result_ready_i) begin
        if (expected_results.size() == 0) begin
            `uvm_error("SCOREBOARD",
                       "DUT produced an output but expected_results is empty")
            error_count++;
        end else begin
            expected_value = expected_results.pop_front();
            actual_value   = item.result_o;

            if (actual_value !== expected_value) begin
                `uvm_error("SCOREBOARD",
                    $sformatf("Mismatch at output %0d: DUT=%0d, MATLAB=%0d",
                              output_count, actual_value, expected_value))
                error_count++;
            end else begin
                `uvm_info("SCOREBOARD",
                    $sformatf("MATCH output %0d: %0d",
                              output_count, actual_value), UVM_MEDIUM)
            end

            output_count++;
        end
    end
endfunction

function void conv_scoreboard::check_phase(uvm_phase phase);
    super.check_phase(phase);

    if (expected_results.size() != 0) begin
        `uvm_error("SCOREBOARD",
            $sformatf("%0d expected outputs were not produced by the DUT",
                      expected_results.size()))
    end

    if (error_count == 0 && expected_results.size() == 0) begin
        `uvm_info("SCOREBOARD",
                  $sformatf("MATLAB comparison PASSED: %0d outputs checked",
                            output_count), UVM_NONE)
    end
endfunction

function void conv_scoreboard::report_phase(uvm_phase phase);
    super.report_phase(phase);

    if(error_count == 0) begin
        `uvm_info("SCOREBOARD",
                  $sformatf("ALL TEST PASSED WITH 0 ERRORS",
                            output_count), UVM_NONE)
    end

    else 
        `uvm_error("SCOREBOARD", $sformatf("%0d TEST FAILED", error_count))
endfunction

`endif
