`include "conv_pack.svh"
`include "conv_params.svh"
`include "conv_intf.svh"

module conv_top();
    import conv_pack::*;
    import uvm_pkg::*;

    // -------------------------------------------------------------------
    // Testbench-side copy of the accelerator_top parameters. Change these
    // (and only these) to match whatever DUT configuration you want to
    // exercise; they flow into both the interface and the DUT instance
    // below, so the two can never disagree.
    // -------------------------------------------------------------------
    localparam int N            = 5;
    localparam int IMAGE_WIDTH  = 8;
    localparam int IMAGE_HEIGHT = 8;
    localparam int PIXEL_WIDTH  = 8;
    localparam int COEFF_WIDTH  = 8;
    localparam int OUT_WIDTH    = 16;
    localparam int ROUND_ENABLE = 1;
    localparam int FRAC_BITS    = 4;

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
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .ROUND_ENABLE(ROUND_ENABLE)
    ) intf (clk_i, rst_n_i);

    accelerator_top #(
        .N(N),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .ROUND_ENABLE(ROUND_ENABLE),
        .FRAC_BITS(FRAC_BITS)
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
        N, IMAGE_WIDTH, IMAGE_HEIGHT, PIXEL_WIDTH, COEFF_WIDTH, OUT_WIDTH,
        ROUND_ENABLE, FRAC_BITS
    ))::set(null, "uvm_test_top", "conv_vif", intf);

    // Run the non-parameterized test name registered in factory
    run_test("conv_test");
end
endmodule
