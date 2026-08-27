`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Accelerator - Top Level
// Module Name: accelerator_top
// Tool Versions: Vivado 2025.2
// Description: Top level integrating the convolution datapath (line-buffer
//              bank, window array, MAC array, adder tree, saturate/round),
//              the frame controller, and the address generators with the
//              input and output feature-map memories. The host loads the
//              kernel (host-paced, one coefficient per valid pulse) and the
//              input image (2x double-buffered distributed RAM with a
//              registered read matching the block-RAM inference), then
//              pulses start_i; the accelerator streams one output pixel per
//              cycle and the host reads the results back through the output
//              block-RAM read port. The MAC-to-result chain is pipelined
//              (PIPE_STAGES register stages) to raise Fmax; the result-valid
//              flag shifts with the data.
//
// Dependencies: conv_fsm (src/control/conv_fsm.v)
//               addr_gen_in (src/control/addr_gen_in.v)
//               addr_gen_out (src/control/addr_gen_out.v)
//               line_buffer_bank (src/datapath/line_buffer_bank.v)
//               window_array (src/datapath/window_array.v)
//               kernel_reg_bank (src/datapath/kernel_reg_bank.v)
//               mac_array (src/datapath/mac_array.v)
//               adder_tree (src/datapath/adder_tree.v)
//               sat_round_unit (src/datapath/sat_round_unit.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module accelerator_top #(
    parameter N = 3,  // Kernel size (N >= 2)
    parameter IMAGE_WIDTH = 32,  // Input feature-map width
    parameter IMAGE_HEIGHT = 32,  // Input feature-map height
    parameter PIXEL_WIDTH = 8,  // Input pixel width (unsigned)
    parameter COEFF_WIDTH = 8,  // Kernel coefficient width (signed)
    parameter OUT_WIDTH = 16,  // Output pixel width (signed)
    parameter ROUND_ENABLE = 1,  // Round-half-up before truncation
    parameter PIPE_STAGES = 3,  // Pipeline stages after the window array
    parameter PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT),
    parameter OUT_IMAGE_WIDTH = IMAGE_WIDTH - N + 1,
    parameter OUT_IMAGE_HEIGHT = IMAGE_HEIGHT - N + 1,
    parameter OUT_ADDR_WIDTH = $clog2(OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT),
    parameter PROD_WIDTH = PIXEL_WIDTH + COEFF_WIDTH + 2,
    parameter SUM_WIDTH = PROD_WIDTH + $clog2(N*N)
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire start_i,  // Frame start pulse (1 cycle)
    input wire buf_sel_i,  // Input buffer to convolve (latched at frame start)
    input wire kernel_wr_valid_i,  // Kernel coefficient write valid (host-paced)
    input wire [COEFF_WIDTH-1:0] kernel_wr_data_i,  // Kernel coefficient data
    input wire img_wr_valid_i,  // Input image write valid
    input wire [PIX_ADDR_WIDTH:0] img_wr_addr_i,  // Input write address {buf, pixel}
    input wire [PIXEL_WIDTH-1:0] img_wr_data_i,  // Input pixel data
    input wire [OUT_ADDR_WIDTH-1:0] res_rd_addr_i,  // Output read address
    output wire busy_o,  // Frame in progress
    output wire done_o,  // Frame complete
    output wire [2:0] state_o,  // FSM state (observability)
    output wire [OUT_WIDTH-1:0] res_rd_data_o  // Output read data
);

    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam OUT_TOTAL = OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT;

    // Control-unit interconnect
    wire [PIX_ADDR_WIDTH-1:0] pix_addr;
    wire pix_last;
    wire [OUT_ADDR_WIDTH-1:0] out_addr;
    wire kernel_we;
    wire [$clog2(N*N)-1:0] kernel_addr;
    wire shift_valid;
    wire mem_rd_en;
    wire result_valid;
    wire rst_count;
    wire rd_buf;

    // Datapath interconnect
    wire [N*PIXEL_WIDTH-1:0] row_streams;
    wire [N*PIXEL_WIDTH-1:0] window_data;  // row-remapped stream feeds
    wire [N*N*PIXEL_WIDTH-1:0] window;
    wire [N*N*COEFF_WIDTH-1:0] kernel;
    wire [N*N*PROD_WIDTH-1:0] products;
    wire signed [SUM_WIDTH-1:0] conv_sum;
    wire signed [OUT_WIDTH-1:0] result;
    wire [PIXEL_WIDTH-1:0] img_rd_data;

    // Pipeline interconnect (registers between the combinational blocks)
    wire [N*N*PROD_WIDTH-1:0] products_to_tree;
    wire signed [SUM_WIDTH-1:0] sum_to_sat;
    wire result_valid_p;  // result valid shifted with the pipeline data

    // Pipeline stage 1: register the MAC products
    generate
        if (PIPE_STAGES >= 1) begin : gen_pipe_products
            reg [N*N*PROD_WIDTH-1:0] products_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) products_p1 <= 0;
                else products_p1 <= products;
            end
            assign products_to_tree = products_p1;
        end else begin : gen_no_pipe_products
            assign products_to_tree = products;
        end
    endgenerate

    // Pipeline stage 2: register the adder-tree sum
    generate
        if (PIPE_STAGES >= 2) begin : gen_pipe_sum
            reg signed [SUM_WIDTH-1:0] sum_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) sum_p1 <= 0;
                else sum_p1 <= conv_sum;
            end
            assign sum_to_sat = sum_p1;
        end else begin : gen_no_pipe_sum
            assign sum_to_sat = conv_sum;
        end
    endgenerate

    // Pipeline valid: shifts with the data through the pipeline stages
    generate
        if (PIPE_STAGES == 1) begin : gen_pipe_valid1
            reg valid_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) valid_p1 <= 1'b0;
                else valid_p1 <= result_valid;
            end
            assign result_valid_p = valid_p1;
        end else if (PIPE_STAGES >= 2) begin : gen_pipe_validn
            reg [PIPE_STAGES-1:0] valid_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) valid_p1 <= 0;
                else valid_p1 <= {valid_p1[PIPE_STAGES-2:0], result_valid};
            end
            assign result_valid_p = valid_p1[PIPE_STAGES-1];
        end else begin : gen_no_pipe_valid
            assign result_valid_p = result_valid;
        end
    endgenerate

    // Input image storage: 2x double-buffered distributed RAM. The read is
    // explicitly registered (models the block-RAM read latency) so the RTL
    // matches the synthesized memory exactly; the read adds one stage to the
    // datapath pipeline (PIPE_STAGES includes it).
    reg [PIXEL_WIDTH-1:0] img_mem [0:2*TOTAL_PIXELS-1];

    always @(posedge clk_i) begin : img_write
        if (img_wr_valid_i) img_mem[img_wr_addr_i] <= img_wr_data_i;
    end

    reg [PIXEL_WIDTH-1:0] img_rd_q;

    always @(posedge clk_i or negedge rst_n_i) begin : img_read
        if (!rst_n_i) img_rd_q <= 0;
        else img_rd_q <= img_mem[{rd_buf, pix_addr}];
    end

    assign img_rd_data = img_rd_q;

    // Output storage: 1 block RAM (simple dual-port, registered read)
    reg [OUT_WIDTH-1:0] res_mem [0:OUT_TOTAL-1];
    reg [OUT_WIDTH-1:0] res_rd_data_q;

    always @(posedge clk_i) begin : res_write
        if (result_valid_p) res_mem[out_addr] <= result;
    end

    always @(posedge clk_i) begin : res_read
        res_rd_data_q <= res_mem[res_rd_addr_i];
    end

    assign res_rd_data_o = res_rd_data_q;

    // Frame controller
    conv_fsm #(
        .N             (N),
        .IMAGE_WIDTH   (IMAGE_WIDTH),
        .IMAGE_HEIGHT  (IMAGE_HEIGHT),
        .COEFF_WIDTH   (COEFF_WIDTH),
        .PIPE_STAGES   (PIPE_STAGES),
        .PIX_ADDR_WIDTH(PIX_ADDR_WIDTH),
        .STATE_WIDTH   (3)
    ) u_fsm (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .start_i         (start_i),
        .buf_sel_i       (buf_sel_i),
        .kernel_wr_valid_i(kernel_wr_valid_i),
        .kernel_data_i   (kernel_wr_data_i),
        .pix_addr_i      (pix_addr),
        .pix_last_i      (pix_last),
        .kernel_we_o     (kernel_we),
        .kernel_addr_o   (kernel_addr),
        .shift_valid_o   (shift_valid),
        .mem_rd_en_o     (mem_rd_en),
        .result_valid_o  (result_valid),
        .rst_count_o     (rst_count),
        .rd_buf_o        (rd_buf),
        .busy_o          (busy_o),
        .done_o          (done_o),
        .state_o         (state_o)
    );

    // Address generators
    addr_gen_in #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH  (PIX_ADDR_WIDTH)
    ) u_in (
        .clk_i       (clk_i),
        .rst_n_i     (rst_n_i),
        .en_i        (shift_valid),
        .rst_count_i (rst_count),
        .addr_o      (pix_addr),
        .last_o      (pix_last)
    );

    addr_gen_out #(
        .OUT_IMAGE_WIDTH (OUT_IMAGE_WIDTH),
        .OUT_IMAGE_HEIGHT(OUT_IMAGE_HEIGHT),
        .ADDR_WIDTH      (OUT_ADDR_WIDTH)
    ) u_out (
        .clk_i       (clk_i),
        .rst_n_i     (rst_n_i),
        .en_i        (result_valid_p),
        .rst_count_i (rst_count),
        .addr_o      (out_addr),
        .last_o      ()
    );

    // Datapath
    line_buffer_bank #(
        .N            (N),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .PIXEL_WIDTH  (PIXEL_WIDTH)
    ) u_line_buffer_bank (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .shift_valid_i (shift_valid),
        .pixel_in_i    (img_rd_data),
        .row_streams_o (row_streams)
    );

    // The window row 0 must hold the oldest row of the patch, so window row
    // g feeds from the stream delayed (N-1-g) rows (row_streams index N-1-g).
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : gen_row_map
            assign window_data[g*PIXEL_WIDTH +: PIXEL_WIDTH] =
                row_streams[(N-1-g)*PIXEL_WIDTH +: PIXEL_WIDTH];
        end
    endgenerate

    window_array #(
        .N           (N),
        .PIXEL_WIDTH (PIXEL_WIDTH)
    ) u_window_array (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .shift_valid_i (shift_valid),
        .data_row_i    (window_data),
        .window_o      (window)
    );

    kernel_reg_bank #(
        .N           (N),
        .COEFF_WIDTH (COEFF_WIDTH)
    ) u_kernel_reg_bank (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .load_valid_i (kernel_wr_valid_i && kernel_we),
        .load_addr_i  (kernel_addr),
        .load_data_i  (kernel_wr_data_i),
        .kernel_o     (kernel)
    );

    mac_array #(
        .N            (N),
        .PIXEL_WIDTH  (PIXEL_WIDTH),
        .COEFF_WIDTH  (COEFF_WIDTH),
        .PROD_WIDTH   (PROD_WIDTH)
    ) u_mac_array (
        .window_i    (window),
        .kernel_i    (kernel),
        .products_o  (products)
    );

    adder_tree #(
        .N          (N),
        .PROD_WIDTH (PROD_WIDTH),
        .SUM_WIDTH  (SUM_WIDTH)
    ) u_adder_tree (
        .products_i (products_to_tree),
        .sum_o      (conv_sum)
    );

    sat_round_unit #(
        .SUM_WIDTH    (SUM_WIDTH),
        .OUT_WIDTH    (OUT_WIDTH),
        .ROUND_ENABLE (ROUND_ENABLE)
    ) u_sat_round_unit (
        .sum_i    (sum_to_sat),
        .result_o (result)
    );

endmodule
