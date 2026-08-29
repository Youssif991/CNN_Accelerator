`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Accelerator - Top Level Testbench
// Module Name: tb_accelerator_top
// Tool Versions: Vivado 2025.2
// Description: End-to-end self-checking testbench for the accelerator top.
//              Loads the kernel through the host port (host-paced), then
//              streams the input image one 8-bit pixel per cycle through
//              pixel_in_i/pixel_valid_i and compares every output against an
//              independent triple-loop convolution golden model (with
//              round-half-up and saturation). Results are checked on both the
//              streaming output port (result_o/result_valid_o) and the output
//              memory readback. Covers an all-zero frame, randomized frames,
//              host-paced kernel writes with gaps, and pixel-stream stalls
//              (pixel_valid_i deasserted mid-frame) which must not corrupt the
//              sliding window or the output stream.
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
    localparam PIPE_STAGES = 2;  // must match the accelerator top default
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam PIX_ADDR_WIDTH = $clog2(TOTAL_PIXELS);
    localparam OUT_IMAGE_WIDTH = IMAGE_WIDTH - N + 1;
    localparam OUT_IMAGE_HEIGHT = IMAGE_HEIGHT - N + 1;
    localparam OUT_TOTAL = OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT;
    localparam OUT_ADDR_WIDTH = $clog2(OUT_TOTAL);
    // Streamed outputs per frame: every accepted pixel past the fill rows
    // (includes the N-1 border windows per row that the memory check skips)
    localparam STREAM_OUT_TOTAL = IMAGE_WIDTH * (IMAGE_HEIGHT - N + 1) - (N - 1);
    localparam PROD_WIDTH = PIXEL_WIDTH + COEFF_WIDTH + 2;
    localparam SUM_WIDTH = PROD_WIDTH + $clog2(N * N);
    localparam BITS_DROPPED = SUM_WIDTH - OUT_WIDTH;
    localparam SAT_MAX = (1 << (OUT_WIDTH - 1)) - 1;  // +32767
    localparam SAT_MIN = -(1 << (OUT_WIDTH - 1));  // -32768

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg start_i;
    reg pixel_valid_i;
    reg [PIXEL_WIDTH-1:0] pixel_in_i;
    reg kernel_wr_valid_i;
    reg [COEFF_WIDTH-1:0] kernel_wr_data_i;
    reg [OUT_ADDR_WIDTH-1:0] res_rd_addr_i;
    wire busy_o;
    wire done_o;
    wire [2:0] state_o;
    wire [OUT_WIDTH-1:0] res_rd_data_o;
    wire result_valid_o;
    wire [OUT_WIDTH-1:0] result_o;

    // Test infrastructure
    integer errors = 0;
    integer w;  // image write index
    integer t;  // kernel tap index
    integer f;  // frame index
    integer stream_idx;  // index into the captured stream-out buffer

    // Golden reference model data
    reg [PIXEL_WIDTH-1:0] ref_img[0:TOTAL_PIXELS-1];
    reg signed [COEFF_WIDTH-1:0] ref_kernel[0:N*N-1];
    reg signed [SUM_WIDTH-1:0] ref_sum;
    reg signed [SUM_WIDTH-1:0] ref_shifted;
    reg signed [OUT_WIDTH-1:0] ref_out;

    // Captured streaming output (indexed by result_valid_o pulses)
    reg signed [OUT_WIDTH-1:0] stream_out[0:1023];

    // Module instantiation (defaults: streaming input, PIPE_STAGES=2)
    accelerator_top #(
        .N           (N),
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .COEFF_WIDTH (COEFF_WIDTH),
        .OUT_WIDTH   (OUT_WIDTH),
        .PIPE_STAGES (PIPE_STAGES)
    ) dut (
        .clk_i            (clk_i),
        .rst_n_i          (rst_n_i),
        .start_i          (start_i),
        .pixel_in_i       (pixel_in_i),
        .pixel_valid_i    (pixel_valid_i),
        .kernel_wr_valid_i(kernel_wr_valid_i),
        .kernel_wr_data_i (kernel_wr_data_i),
        .res_rd_addr_i    (res_rd_addr_i),
        .busy_o           (busy_o),
        .done_o           (done_o),
        .state_o          (state_o),
        .res_rd_data_o    (res_rd_data_o),
        .result_valid_o   (result_valid_o),
        .result_o         (result_o)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Capture the streaming output in order of the valid pulses. stream_idx
    // also serves as the result_valid_o pulse counter (reset before each frame
    // in the test procedure; the reset and the capture never fire together).
    initial begin : capture_stream
        stream_idx = 0;
        forever begin
            @(posedge clk_i);
            if (result_valid_o) begin
                stream_out[stream_idx] = result_o;
                stream_idx = stream_idx + 1;
            end
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

    // Task: wait until the frame completes
    task wait_done;
        begin
            while (!done_o) @(negedge clk_i);
        end
    endtask

    // Task: stream the input image, one pixel per cycle, from the reference
    // array. When stall_every > 0, deassert pixel_valid_i for 1-3 cycles
    // after every stall_every-th pixel to exercise the stall handling.
    task stream_image;
        input integer stall_every;
        integer p;
        integer stall_len;
        begin
            // Wait until the FSM reaches FILL before presenting pixels
            while (state_o !== 2) @(negedge clk_i);
            for (p = 0; p < TOTAL_PIXELS; p = p + 1) begin
                @(negedge clk_i);
                pixel_in_i = ref_img[p];
                pixel_valid_i = 1;
                if (stall_every && ((p % stall_every) == (stall_every - 1))) begin
                    // Inject a 1-3 cycle stall after this pixel is accepted
                    stall_len = 1 + (p % 3);
                    repeat (stall_len) begin
                        @(negedge clk_i);
                        pixel_valid_i = 0;
                    end
                end
            end
            @(negedge clk_i);
            pixel_valid_i = 0;
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
                write_kernel(ref_kernel[t]);
                if (gap_writes && ((t % gap_writes) == (gap_writes - 1))) @(negedge clk_i);
            end
        end
    endtask

    // Task: check the streaming port against the flat-window golden. The
    // streaming valid covers every accepted pixel past the fill, so output a
    // is the convolution of the window = the last 3 pixels of each of the 3
    // row streams: cell (i,j) = stream[a + i*W + j]. Border windows (column
    // < N-1) naturally read the previous row's tail, exactly like the shift
    // register does.
    task check_stream;
        integer a;  // streamed output index
        integer t;  // kernel tap
        begin
            for (a = 0; a < STREAM_OUT_TOTAL; a = a + 1) begin
                ref_sum = 0;
                for (t = 0; t < N * N; t = t + 1) begin
                    ref_sum = ref_sum + $signed(
                        {1'b0, ref_img[a + (t / N) * IMAGE_WIDTH + t % N]}) * ref_kernel[t];
                end
                ref_shifted = ref_sum + (1 << (BITS_DROPPED - 1));
                ref_shifted = ref_shifted >>> BITS_DROPPED;
                if (ref_shifted > SAT_MAX) begin
                    ref_out = SAT_MAX;
                end else if (ref_shifted < SAT_MIN) begin
                    ref_out = SAT_MIN;
                end else begin
                    ref_out = $signed(ref_shifted[OUT_WIDTH-1:0]);
                end
                if (stream_out[a] !== ref_out) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: stream_out[%0d] = %0d expected %0d", $time, a,
                             stream_out[a], ref_out);
                end
            end
        end
    endtask

    // Task: read back all outputs of one frame and compare with the golden
    // triple-loop convolution model (in-image outputs only).
    task check_memory;
        integer a;  // output address
        integer r;  // output row
        integer c;  // output col
        begin
            for (a = 0; a < OUT_TOTAL; a = a + 1) begin
                r = a / OUT_IMAGE_WIDTH;
                c = a % OUT_IMAGE_WIDTH;
                ref_sum = 0;
                for (t = 0; t < N * N; t = t + 1) begin
                    ref_sum = ref_sum + $signed(
                        {1'b0, ref_img[(r + t / N) * IMAGE_WIDTH + c + t % N]}) * ref_kernel[t];
                end
                ref_shifted = ref_sum + (1 << (BITS_DROPPED - 1));
                ref_shifted = ref_shifted >>> BITS_DROPPED;
                if (ref_shifted > SAT_MAX) begin
                    ref_out = SAT_MAX;
                end else if (ref_shifted < SAT_MIN) begin
                    ref_out = SAT_MIN;
                end else begin
                    ref_out = $signed(ref_shifted[OUT_WIDTH-1:0]);
                end
                // Memory readback check
                @(negedge clk_i);
                res_rd_addr_i = a;
                @(negedge clk_i);
                @(negedge clk_i);
                if (res_rd_data_o !== ref_out) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: out[%0d] = %0d expected %0d", $time, a,
                             res_rd_data_o, ref_out);
                end
            end
        end
    endtask

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        start_i = 0;
        pixel_valid_i = 0;
        pixel_in_i = 0;
        kernel_wr_valid_i = 0;
        kernel_wr_data_i = 0;
        res_rd_addr_i = 0;
        rst_n_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;
        @(negedge clk_i);

        // Directed test 1: all-zero kernel and image produce all-zero outputs
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = 0;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = 0;
        run_frame(0);
        stream_idx = 0;
        stream_image(0);  // no stalls
        wait_done();
        #20;  // settle so the final output writes land before readback
        check_stream();
        check_memory();
        if (stream_idx !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: result_valid_o pulses=%0d expected %0d", $time, stream_idx,
                     STREAM_OUT_TOTAL);
        end

        // Directed test 2: random kernel and image, continuous stream
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $urandom;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
        run_frame(0);
        stream_idx = 0;
        stream_image(0);
        wait_done();
        #20;
        check_stream();
        check_memory();
        if (stream_idx !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: result_valid_o pulses=%0d expected %0d", $time, stream_idx,
                     STREAM_OUT_TOTAL);
        end

        // Directed test 3: random kernel and image with pixel-stream stalls.
        // pixel_valid_i deasserts for 1-3 cycles every 32 pixels; the window
        // and counters must stay synchronized and all outputs must match.
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $urandom;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
        run_frame(3);  // gapped kernel writes too
        stream_idx = 0;
        stream_image(32);  // stalls every 32 pixels
        wait_done();
        #20;
        check_stream();
        check_memory();
        if (stream_idx !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stalled result_valid_o pulses=%0d expected %0d", $time,
                     stream_idx, STREAM_OUT_TOTAL);
        end

        // Random stimulus
        // Two more random frames with host-paced kernel writes (gaps every
        // third write) and random stall patterns.
        for (f = 0; f < 2; f = f + 1) begin
            for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $urandom;
            for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
            run_frame(3);
            stream_idx = 0;
            stream_image(f ? 16 : 64);  // different stall cadences
            wait_done();
            #20;
            check_stream();
            check_memory();
            if (stream_idx !== STREAM_OUT_TOTAL) begin
                errors = errors + 1;
                $display("FAIL t=%0t: result_valid_o pulses=%0d expected %0d", $time,
                         stream_idx, STREAM_OUT_TOTAL);
            end
        end

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Bonus check: in a sustained stream (pixel_valid high every cycle) the
    // output valid must never deassert for two or more consecutive cycles
    // inside COMPUTE, after the initial pipeline fill. The check arms only
    // once the input has been continuously valid for PIPE_STAGES+1 cycles,
    // so the pipeline-fill latency at frame start and after a stall
    // (allowed initial/recovery latency) is not counted.
    always @(posedge clk_i) begin : gap_check
        reg [3:0] low_cnt;
        reg [3:0] valid_streak;
        reg seen_valid;
        if (!rst_n_i) begin
            low_cnt = 0;
            valid_streak = 0;
            seen_valid = 0;
        end else begin
            if (state_o == 2) seen_valid = 0;  // re-arm at each frame fill
            if (result_valid_o) seen_valid = 1;
            if (pixel_valid_i) valid_streak = valid_streak + 1;
            else valid_streak = 0;
            if (seen_valid && (state_o == 3) && pixel_valid_i && !result_valid_o &&
                (valid_streak > PIPE_STAGES + 1)) begin
                low_cnt = low_cnt + 1;
                if (low_cnt >= 2) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: result_valid_o deasserted %0d cycles mid-stream",
                             $time, low_cnt);
                end
            end else begin
                low_cnt = 0;
            end
        end
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
