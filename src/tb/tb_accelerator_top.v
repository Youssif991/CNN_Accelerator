`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Accelerator - Top Level Testbench
// Module Name: tb_accelerator_top
// Tool Versions: Vivado 2025.2
// Description: End-to-end self-checking testbench for the accelerator top.
//              Loads the kernel and input image through the host ports,
//              runs a frame, reads the output memory back, and compares
//              every result against an independent triple-loop convolution
//              golden model (with round-half-up and saturation). Covers an
//              all-zero frame, randomized frames, host-paced kernel writes
//              with gaps, and input double buffering with a host write
//              issued during the compute pass.
//
// Dependencies: accelerator_top (src/top/accelerator_top.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_accelerator_top;

    // Parameters
    localparam N = 3;
    localparam IMAGE_WIDTH = 32;
    localparam IMAGE_HEIGHT = 32;
    localparam PIXEL_WIDTH = 8;
    localparam COEFF_WIDTH = 8;
    localparam OUT_WIDTH = 16;
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam PIX_ADDR_WIDTH = $clog2(TOTAL_PIXELS);
    localparam OUT_IMAGE_WIDTH = IMAGE_WIDTH - N + 1;
    localparam OUT_IMAGE_HEIGHT = IMAGE_HEIGHT - N + 1;
    localparam OUT_TOTAL = OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT;
    localparam OUT_ADDR_WIDTH = $clog2(OUT_TOTAL);
    localparam PROD_WIDTH = PIXEL_WIDTH + COEFF_WIDTH + 2;
    localparam SUM_WIDTH = PROD_WIDTH + $clog2(N*N);
    localparam BITS_DROPPED = SUM_WIDTH - OUT_WIDTH;
    localparam SAT_MAX = (1 << (OUT_WIDTH-1)) - 1;  // +32767
    localparam SAT_MIN = -(1 << (OUT_WIDTH-1));  // -32768

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg start_i;
    reg buf_sel_i;
    reg kernel_wr_valid_i;
    reg [COEFF_WIDTH-1:0] kernel_wr_data_i;
    reg img_wr_valid_i;
    reg [PIX_ADDR_WIDTH:0] img_wr_addr_i;
    reg [PIXEL_WIDTH-1:0] img_wr_data_i;
    reg [OUT_ADDR_WIDTH-1:0] res_rd_addr_i;
    wire busy_o;
    wire done_o;
    wire [2:0] state_o;
    wire [OUT_WIDTH-1:0] res_rd_data_o;

    // Test infrastructure
    integer errors = 0;
    integer w;  // image write index
    integer t;  // kernel tap index
    integer f;  // frame / buffer index

    // Golden reference model data
    reg [PIXEL_WIDTH-1:0] ref_img [0:2*TOTAL_PIXELS-1];  // 2x double-buffered
    reg signed [COEFF_WIDTH-1:0] ref_kernel [0:N*N-1];
    reg signed [SUM_WIDTH-1:0] ref_sum;
    reg signed [SUM_WIDTH-1:0] ref_shifted;
    reg signed [OUT_WIDTH-1:0] ref_out;

    // Module instantiation
    accelerator_top #(
        .N            (N),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .PIXEL_WIDTH  (PIXEL_WIDTH),
        .COEFF_WIDTH  (COEFF_WIDTH),
        .OUT_WIDTH    (OUT_WIDTH)
    ) dut (
        .clk_i            (clk_i),
        .rst_n_i          (rst_n_i),
        .start_i          (start_i),
        .buf_sel_i        (buf_sel_i),
        .kernel_wr_valid_i(kernel_wr_valid_i),
        .kernel_wr_data_i (kernel_wr_data_i),
        .img_wr_valid_i   (img_wr_valid_i),
        .img_wr_addr_i    (img_wr_addr_i),
        .img_wr_data_i    (img_wr_data_i),
        .res_rd_addr_i    (res_rd_addr_i),
        .busy_o           (busy_o),
        .done_o           (done_o),
        .state_o          (state_o),
        .res_rd_data_o    (res_rd_data_o)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Task: write one pixel into the input buffer (host-paced pulse)
    task write_pixel;
        input [PIX_ADDR_WIDTH:0] addr;
        input [PIXEL_WIDTH-1:0] data;
        begin
            img_wr_addr_i = addr;
            img_wr_data_i = data;
            img_wr_valid_i = 1;
            @(negedge clk_i);
            img_wr_valid_i = 0;
        end
    endtask

    // Task: write one kernel coefficient (host-paced pulse)
    task write_kernel;
        input [COEFF_WIDTH-1:0] coef;
        begin
            kernel_wr_data_i = coef;
            kernel_wr_valid_i = 1;
            @(negedge clk_i);
            kernel_wr_valid_i = 0;
        end
    endtask

    // Task: wait until the frame completes
    task wait_done;
        begin
            while (!done_o) @(negedge clk_i);
        end
    endtask

    // Task: load the full image of one buffer from the reference array
    task load_image;
        input integer b;
        begin
            for (w = 0; w < TOTAL_PIXELS; w = w + 1) begin
                write_pixel({b[0], w[PIX_ADDR_WIDTH-1:0]}, ref_img[b*TOTAL_PIXELS + w]);
            end
        end
    endtask

    // Task: start a frame and write the kernel with optional gaps
    task run_frame;
        input integer gap_writes;
        begin
            start_i = 1;
            @(negedge clk_i);
            start_i = 0;
            for (t = 0; t < N*N; t = t + 1) begin
                write_kernel(ref_kernel[t]);
                if (gap_writes && ((t % gap_writes) == (gap_writes - 1))) @(negedge clk_i);
            end
        end
    endtask

    // Task: read back all outputs of one frame and compare with the golden
    // triple-loop convolution model
    task check_outputs;
        input integer b;
        integer a;  // output address
        integer r;  // output row
        integer c;  // output col
        begin
            for (a = 0; a < OUT_TOTAL; a = a + 1) begin
                r = a / OUT_IMAGE_WIDTH;
                c = a % OUT_IMAGE_WIDTH;
                ref_sum = 0;
                for (t = 0; t < N*N; t = t + 1) begin
                    ref_sum = ref_sum + $signed({1'b0, ref_img[b*TOTAL_PIXELS +
                        (r + t/N)*IMAGE_WIDTH + c + t%N]}) * ref_kernel[t];
                end
                ref_shifted = ref_sum + (1 << (BITS_DROPPED-1));
                ref_shifted = ref_shifted >>> BITS_DROPPED;
                if (ref_shifted > SAT_MAX) begin
                    ref_out = SAT_MAX;
                end else if (ref_shifted < SAT_MIN) begin
                    ref_out = SAT_MIN;
                end else begin
                    ref_out = $signed(ref_shifted[OUT_WIDTH-1:0]);
                end
                res_rd_addr_i = a;
                @(negedge clk_i);
                @(negedge clk_i);
                if (res_rd_data_o !== ref_out) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: out[%0d] b=%0d = %0d expected %0d", $time, a, b,
                             res_rd_data_o, ref_out);
                end
            end
        end
    endtask

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        start_i = 0;
        buf_sel_i = 0;
        kernel_wr_valid_i = 0;
        kernel_wr_data_i = 0;
        img_wr_valid_i = 0;
        img_wr_addr_i = 0;
        img_wr_data_i = 0;
        res_rd_addr_i = 0;
        rst_n_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;
        @(negedge clk_i);

        // Directed test 1: all-zero kernel and image produce all-zero outputs
        for (t = 0; t < N*N; t = t + 1) ref_kernel[t] = 0;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) begin
            ref_img[w] = 0;
            ref_img[TOTAL_PIXELS + w] = 0;
        end
        load_image(0);
        buf_sel_i = 0;
        run_frame(0);
        wait_done();
        check_outputs(0);

        // Directed test 2: random kernel and image on buffer 0
        for (t = 0; t < N*N; t = t + 1) ref_kernel[t] = $urandom;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
        load_image(0);
        buf_sel_i = 0;
        run_frame(0);
        wait_done();
        check_outputs(0);

        // Directed test 3: input double buffering.
        // Load buffer 1, compute on it, and write a fresh image into buffer 0
        // during the compute pass; then compute buffer 0 and verify both.
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[TOTAL_PIXELS + w] = $urandom;
        load_image(1);
        buf_sel_i = 1;
        run_frame(0);
        // Write the next frame's image into buffer 0 while frame 1 computes
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) begin
            write_pixel({1'b0, w[PIX_ADDR_WIDTH-1:0]}, ref_img[w]);
        end
        wait_done();
        check_outputs(1);
        // Now compute the newly loaded buffer 0
        buf_sel_i = 0;
        run_frame(0);
        wait_done();
        check_outputs(0);

        // Random stimulus
        // Two more random frames with host-paced kernel writes (gaps every
        // third write) alternating buffers.
        for (f = 0; f < 2; f = f + 1) begin
            for (t = 0; t < N*N; t = t + 1) ref_kernel[t] = $urandom;
            for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[f*TOTAL_PIXELS + w] = $urandom;
            load_image(f);
            buf_sel_i = f[0];
            run_frame(3);
            wait_done();
            check_outputs(f);
        end

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | state=%0d busy=%b done=%b | res_rd_addr=%0d res_rd_data=%0d", $time,
                 state_o, busy_o, done_o, res_rd_addr_i, res_rd_data_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_accelerator_top.vcd");
        $dumpvars(0, tb_accelerator_top);
    end

endmodule
