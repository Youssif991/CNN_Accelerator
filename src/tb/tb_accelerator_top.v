`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Accelerator - Top Level Stimulus
// Module Name: tb_accelerator_top
// Tool Versions: Vivado 2025.2
// Description: Pure stimulus driver for accelerator_top. Loads the kernel
//              through the host port (host-paced), then streams the input
//              image one 8-bit pixel per cycle through pixel_in_i /
//              pixel_valid_i. Exercises:
//                - all-zero frame
//                - randomized frames
//                - host-paced kernel writes with gaps
//                - pixel-stream stalls (pixel_valid_i deasserted mid-frame)
//                - output back-pressure (result_ready_i deasserted)
//                - ReLU on and off
//              No data checking is performed here; this TB only drives the
//              DUT. Waveforms are dumped for offline inspection.
//
// Dependencies: accelerator_top (src/top/accelerator_top.v)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.05 - Stripped to a pure driver: removed capture, golden model,
//                  print helpers, checks, error counters and verdict.
//////////////////////////////////////////////////////////////////////////////////

module tb_accelerator_top;

    // Parameters - matched 1:1 to src/tb/conv_top.sv's DUT configuration so
    // this Verilog testbench and the UVM/SystemVerilog testbench exercise
    // the identical accelerator_top instance.
    localparam N = 3;
    localparam IMAGE_WIDTH = 32;
    localparam IMAGE_HEIGHT = 32;
    localparam PIXEL_WIDTH = 8;
    localparam COEFF_WIDTH = 8;
    localparam OUT_WIDTH = 16;
    localparam ROUND_ENABLE = 1;
    localparam PIPE_STAGES = 11;
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam FRAC_BITS = 4;  // must track accelerator_top's FRAC_BITS

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg start_i;
    reg pixel_valid_i;
    reg [PIXEL_WIDTH-1:0] pixel_in_i;
    reg kernel_wr_valid_i;
    reg [COEFF_WIDTH-1:0] kernel_wr_data_i;
    reg relu_en_i;
    wire busy_o;
    wire done_o;
    wire ready_o;
    reg result_ready_i;
    wire result_valid_o;
    wire [OUT_WIDTH-1:0] result_o;
    wire result_tlast_o;
    wire [1:0] state_o;

    // Stimulus data
    integer w;  // image write index
    integer t;  // kernel tap index
    integer f;  // frame index
    integer random_seed;

    reg [PIXEL_WIDTH-1:0] stim_img[0:TOTAL_PIXELS-1];
    reg signed [COEFF_WIDTH-1:0] stim_kernel[0:N*N-1];

    // Module instantiation
    accelerator_top #(
        .N           (N),
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .COEFF_WIDTH (COEFF_WIDTH),
        .OUT_WIDTH   (OUT_WIDTH),
        .FRAC_BITS   (FRAC_BITS),
        .PIPE_STAGES (PIPE_STAGES),
        .ROUND_ENABLE(ROUND_ENABLE)
    ) dut (
        .clk_i            (clk_i),
        .rst_n_i          (rst_n_i),
        .start_i          (start_i),
        .pixel_in_i       (pixel_in_i),
        .pixel_valid_i    (pixel_valid_i),
        .kernel_wr_valid_i(kernel_wr_valid_i),
        .kernel_wr_data_i (kernel_wr_data_i),
        .relu_en_i        (relu_en_i),
        .busy_o           (busy_o),
        .done_o           (done_o),
        .ready_o          (ready_o),
        .result_valid_o   (result_valid_o),
        .result_o         (result_o),
        .state_o          (state_o),
        .result_tlast_o   (result_tlast_o),
        .result_ready_i   (result_ready_i)
    );

    // Clock generation: free-running 8 ns period (125 MHz)
    initial begin : clock
        clk_i = 0;
        forever #4 clk_i = ~clk_i;
    end

    // Output back-pressure generator: drives result_ready_i from the falling
    // edge so it is stable before the DUT samples each output handshake on the
    // following rising edge. Updating ready on posedge races the DUT.
    reg bp_en = 0;
    reg [7:0] bp_cnt;
    always @(negedge clk_i or negedge rst_n_i) begin : bp_gen
        if (!rst_n_i) begin
            result_ready_i <= 1'b1;
            bp_cnt <= 0;
        end else if (bp_en) begin
            result_ready_i <= ((bp_cnt % 16) < ((bp_cnt % 2) + 1)) ? 1'b0 : 1'b1;
            bp_cnt <= bp_cnt + 1;
        end else begin
            result_ready_i <= 1'b1;
            bp_cnt <= 0;
        end
    end

    // Task: write one kernel coefficient (host-paced pulse)
    task write_kernel;
        input [COEFF_WIDTH-1:0] coef;
        begin
            @(negedge clk_i);
            kernel_wr_data_i  = coef;
            kernel_wr_valid_i = 1;
            @(negedge clk_i);
            kernel_wr_valid_i = 0;
        end
    endtask

    // Task: wait for input ready (no timeout; this is a driver, not a checker)
    task wait_input_ready;
        begin
            while (!ready_o) @(negedge clk_i);
        end
    endtask

    // Task: wait for done
    task wait_done;
        begin
            while (!done_o) @(negedge clk_i);
        end
    endtask

    // Task: stream the input image using the public ready/valid interface.
    task stream_image;
        input integer stall_every;
        integer p;
        integer stall_len;
        begin
            pixel_valid_i = 0;
            pixel_in_i = 0;

            wait_input_ready();
            for (p = 0; p < TOTAL_PIXELS; p = p + 1) begin
                pixel_in_i = stim_img[p];
                pixel_valid_i = 1;
                wait_input_ready();
                @(negedge clk_i);
                pixel_valid_i = 0;

                if (stall_every && ((p % stall_every) == (stall_every - 1))) begin
                    stall_len = 1 + (p % 3);
                    repeat (stall_len) @(negedge clk_i);
                end
            end
            pixel_valid_i = 0;
            pixel_in_i = 0;
        end
    endtask

    // Task: start a frame and write the kernel with optional gaps
    task run_frame;
        input integer gap_writes;
        begin
            @(negedge clk_i);
            start_i = 1;
            @(negedge clk_i);
            start_i = 0;
            for (t = 0; t < N * N; t = t + 1) begin
                write_kernel(stim_kernel[t]);
                if (gap_writes && ((t % gap_writes) == (gap_writes - 1))) @(negedge clk_i);
            end
        end
    endtask

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        random_seed = 32'h1234_5678;
        random_seed = $random(random_seed);
        start_i = 0;
        pixel_valid_i = 0;
        pixel_in_i = 0;
        kernel_wr_valid_i = 0;
        kernel_wr_data_i = 0;
        relu_en_i = 0;
        rst_n_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;
        @(negedge clk_i);

        // Frame 1: all-zero kernel and image
        for (t = 0; t < N * N; t = t + 1) stim_kernel[t] = 0;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) stim_img[w] = 0;
        run_frame(0);
        stream_image(0);
        wait_done();
        #20;

        // Frame 2: random kernel and image, continuous stream, ReLU on
        for (t = 0; t < N * N; t = t + 1) stim_kernel[t] = $random(random_seed);
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) stim_img[w] = $random(random_seed);
        relu_en_i = 1;
        run_frame(0);
        stream_image(0);
        wait_done();
        #20;

        // Frame 3: random kernel and image with pixel-stream stalls,
        // gapped kernel writes. ReLU stays enabled.
        for (t = 0; t < N * N; t = t + 1) stim_kernel[t] = $random(random_seed);
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) stim_img[w] = $random(random_seed);
        run_frame(3);
        stream_image(32);
        wait_done();
        #20;

        // Frame 4: output consumer back-pressure, ReLU off
        for (t = 0; t < N * N; t = t + 1) stim_kernel[t] = $random(random_seed);
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) stim_img[w] = $random(random_seed);
        relu_en_i = 0;
        run_frame(0);
        bp_en = 1;
        stream_image(0);
        wait_done();
        bp_en = 0;
        #20;

        // Frames 5-6: random kernels and images, gapped kernel writes,
        // different input stall cadences. ReLU on for the second one.
        for (f = 0; f < 2; f = f + 1) begin
            for (t = 0; t < N * N; t = t + 1) stim_kernel[t] = $random(random_seed);
            for (w = 0; w < TOTAL_PIXELS; w = w + 1) stim_img[w] = $random(random_seed);
            relu_en_i = (f == 1);
            run_frame(3);
            stream_image(f ? 16 : 64);
            wait_done();
            #20;
        end

        #20;
        $finish;
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_accelerator_top.vcd");
        $dumpvars(0, tb_accelerator_top);
    end

endmodule