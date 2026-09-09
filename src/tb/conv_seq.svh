`ifndef CONV_SEQ_SVH
`define CONV_SEQ_SVH

//******************************************************************************
// Engineer : Marwan 
// Create Date: 08/27/2026
// Design Name: uvm convolution sequence
// Class Name: conv_seq
// Tool Versions: Questa 2021
// Description: UVM sequence for convolution accelerator verification
// Dependencies: conv_params.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_params.svh"


class conv_seq #(
    `CONV_PARAMS_DECL
) extends uvm_sequence #(conv_seq_item#(`CONV_PARAMS_LIST));

    `uvm_object_param_utils(conv_seq#(`CONV_PARAMS_LIST))

    typedef conv_seq_item#(`CONV_PARAMS_LIST) conv_item;

    function new(string name = "conv_seq");
        super.new(name);
    endfunction

    extern task idle_cycle(int n = 1, bit result_ready = 1'b1);
    extern task get_ready(bit start = 1'b1 , bit wr_kernel_enable = 1'b1 ,  bit result_ready = 1'b1 , bit relu_en = 1'b0);
    extern task load_cycle(bit [COEFF_WIDTH-1:0] data = 'd0, bit result_ready = 1'b1, bit kernel_wr_valid = 1'b1 , bit relu_en = 1'b0 );
    extern task fill_cycle(bit [PIXEL_WIDTH-1:0] data = 'd0, bit result_ready = 1'b1 , bit relu_en = 1'b0);
    extern task store_cycle(bit result_ready = 1'b1 , bit relu_en = 1'b0);
    extern task body();

endclass

task conv_seq::idle_cycle(int n = 1, bit result_ready = 1'b1);
    conv_item item;
    repeat(n) begin
        item = conv_item::type_id::create("item");
        start_item(item);
        item.start_i           = 0;
        item.pixel_valid_i     = 0;
        item.pixel_in_i        = 'b0;
        item.kernel_wr_valid_i = 0;
        item.kernel_wr_data_i  = 'b0;
        item.relu_en_i         = 0;
        item.result_ready_i    = result_ready;
        finish_item(item);
    end
endtask

task conv_seq::get_ready(bit start = 1'b1 , bit wr_kernel_enable = 1'b1 ,  bit result_ready = 1'b1 , bit relu_en = 1'b0);
    conv_item item;
    item = conv_item::type_id::create("item");
    start_item(item);
    item.start_i           = start;
    item.pixel_valid_i     = 0;
    item.pixel_in_i        = 'b0;
    item.kernel_wr_valid_i = wr_kernel_enable;
    item.kernel_wr_data_i  = 'd0;
    item.relu_en_i         = relu_en;
    item.result_ready_i    = result_ready;
    finish_item(item);
endtask


task  conv_seq::load_cycle(bit [COEFF_WIDTH-1:0] data = 'd0, bit result_ready = 1'b1 ,bit kernel_wr_valid = 1'b1 ,  bit relu_en = 1'b0);
    conv_item item;
    item = conv_item::type_id::create("item");
    start_item(item);
    item.start_i           = 1;
    item.pixel_valid_i     = 0;
    item.pixel_in_i        = 'b0;
    item.kernel_wr_valid_i = kernel_wr_valid;
    item.kernel_wr_data_i  = data;
    item.relu_en_i         = relu_en;
    item.result_ready_i    = result_ready;
    finish_item(item);
endtask


task  conv_seq::fill_cycle(bit [PIXEL_WIDTH-1:0] data = 'd0, bit result_ready = 1'b1 ,  bit relu_en = 1'b0);
    conv_item item;
    item = conv_item::type_id::create("item");
    start_item(item);
    item.start_i           = 0;
    item.pixel_valid_i     = 1;
    item.pixel_in_i        = data;
    item.kernel_wr_valid_i = 0;
    item.kernel_wr_data_i  = 'b0;
    item.relu_en_i         = relu_en;
    item.result_ready_i    = result_ready;
    finish_item(item);
endtask

task  conv_seq::store_cycle(bit result_ready = 1'b1 ,  bit relu_en = 1'b0);
    conv_item item;
    item = conv_item::type_id::create("item");
    start_item(item);
    item.start_i           = 0;
    item.pixel_valid_i     = 0;
    item.pixel_in_i        = 'b0;
    item.kernel_wr_valid_i = 0;
    item.kernel_wr_data_i  = 'b0;
    item.relu_en_i         = relu_en;
    item.result_ready_i    = result_ready;
    finish_item(item);
endtask

task conv_seq::body();
    bit [COEFF_WIDTH-1:0] kernel_data [0:N*N-1];
    bit [PIXEL_WIDTH-1:0] pixel_data  [0:IMAGE_HEIGHT*IMAGE_WIDTH-1];
    bit result_ready;
    bit relu_en = 1'b1;

    $readmemh("src/tb/kernel_coeff.hex", kernel_data);
    $readmemh("src/tb/pixel_input.hex", pixel_data);

    // Load kernel coefficients
    idle_cycle( 2 , 1'b1);
    get_ready(1'b1 , 1'b0 , relu_en);

    for (int i = 0; i < N*N; i++) begin
        load_cycle(kernel_data[i] , 1'b1 , 1'b1 , relu_en);
    end
    
    // Fill and compute
    for (int i = 0; i < IMAGE_HEIGHT * IMAGE_WIDTH; i++) begin
        fill_cycle(pixel_data[i] , 1'b1 , relu_en);
    end
    
    // Store results
    for (int i = 0; i < IMAGE_HEIGHT * IMAGE_WIDTH; i++) begin
        store_cycle(1'b1 , relu_en);
    end
endtask

`endif