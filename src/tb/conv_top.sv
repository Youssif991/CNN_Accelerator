//******************************************************************************
// Engineer : Marwan
// Create Date: 08/27/2026
// Design Name: UVM Convolution Testbench Top
// Module Name: conv_top
// Tool Versions: Questa 2021
// Description: Top-level testbench module for the convolution accelerator.
//              Instantiates the DUT (accelerator_top) and the UVM interface
//              (conv_intf) with parameters sourced from conv_params_pkg,
//              generates clock and reset, and passes the virtual interface to
//              the UVM test via config_db. All parameter values reference
//              conv_params_pkg (the single source of truth) to ensure the
//              interface and DUT always use identical dimensions.
// Dependencies: conv_pack.svh, conv_params_pkg.svh, conv_intf.svh
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//******************************************************************************

`include "conv_pack.svh"
`include "conv_params_pkg.svh"
`include "conv_intf.svh"

module conv_top();
    import conv_pack::*;
    import uvm_pkg::*;
    import conv_params_pkg::*;

    // -------------------------------------------------------------------
    // Testbench-side copy of the accelerator_top parameters. These are
    // just aliases onto conv_params_pkg's localparams (the single source
    // of truth) - change a dimension in CONV_PARAMS_PKG.SVH only; it flows
    // into both the interface and the DUT instance below, so the two can
    // never disagree.
    // -------------------------------------------------------------------
    localparam int N            = conv_params_pkg::N;
    localparam int N_Kernel     = conv_params_pkg::N_Kernel;
    localparam int IMAGE_WIDTH  = conv_params_pkg::IMAGE_WIDTH;
    localparam int IMAGE_HEIGHT = conv_params_pkg::IMAGE_HEIGHT;
    localparam int PIXEL_WIDTH  = conv_params_pkg::PIXEL_WIDTH;
    localparam int COEFF_WIDTH  = conv_params_pkg::COEFF_WIDTH;
    localparam int OUT_WIDTH    = conv_params_pkg::OUT_WIDTH;
    localparam int ROUND_ENABLE = conv_params_pkg::ROUND_ENABLE;
    localparam int FRAC_BITS    = conv_params_pkg::FRAC_BITS;
    localparam int PIPE_STAGES  = conv_params_pkg::PIPE_STAGES;

    // 1. DUT reset handle
    bit rst_n_i;
    initial begin
        rst_n_i = 1'b0;
        #20 rst_n_i = 1'b1;
    end

    // 2. Clock Generation
    bit clk_i;
    always #10 clk_i = ~clk_i;

    conv_intf #(
        .N(N),
        .N_Kernel(N_Kernel),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .ROUND_ENABLE(ROUND_ENABLE),
        .PIPE_STAGES(PIPE_STAGES)
    ) intf (clk_i, rst_n_i);

    accelerator_top #(
        .N(N),
        .N_Kernel(N_Kernel),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .ROUND_ENABLE(ROUND_ENABLE),
        .FRAC_BITS(FRAC_BITS),
        .PIPE_STAGES(PIPE_STAGES)
    ) u_accelerator_top (
        .clk_i            (intf.clk),
        .rst_n_i          (intf.rst_n),
        .start_i          (intf.start_i),
        .pixel_in_i       (intf.pixel_in_i),
        .pixel_valid_i    (intf.pixel_valid_i),
        .kernel_wr_valid_i(intf.kernel_wr_valid_i),
        .kernel_wr_data_i (intf.kernel_wr_data_i),
        .relu_en_i        (intf.relu_en_i),
        .busy_o           (intf.busy_o),
        .done_o           (intf.done_o),
        .state_o          (intf.state_o),
        .result_valid_o   (intf.result_valid_o),
        .result_o         (intf.result_o),
        .result_tlast_o   (intf.result_tlast_o),
        .result_ready_i   (intf.result_ready_i),
        .ready_o          (intf.ready_o)
    );

    // 5. Test Execution
    initial begin
    uvm_config_db#(virtual conv_intf#(
        N, N_Kernel, IMAGE_WIDTH, IMAGE_HEIGHT, PIXEL_WIDTH, COEFF_WIDTH, OUT_WIDTH,
        ROUND_ENABLE, FRAC_BITS, PIPE_STAGES
    ))::set(null, "uvm_test_top", "conv_vif", intf);

    // Run the non-parameterized test name registered in factory
    run_test("conv_test");
end
endmodule
