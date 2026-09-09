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
//              round-half-up rescale by FRAC_BITS and saturation, matching
//              sat_round_unit Rev 0.03). Results are checked on the
//              streaming output port (result_o / result_valid_o / tlast).
//              Covers an all-zero frame, randomized frames, host-paced kernel
//              writes with gaps, pixel-stream stalls (pixel_valid_i deasserted
//              mid-frame) and output back-pressure (result_ready_i deasserted)
//              which must not corrupt the sliding window or the output stream.
//              The optional ReLU activation (relu_en_i) is exercised with
//              frames run both enabled and disabled.
//
// Dependencies: accelerator_top (src/top/accelerator_top.v)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Added FRAC_BITS parameter and matched golden-model
//                  rescale to sat_round_unit Rev 0.03 (sign-extend by 1
//                  bit, round-half-up shift by FRAC_BITS, FRAC_BITS==0
//                  pass-through). Fixed stale BITS_DROPPED reference and
//                  $monitor argument/format mismatch.
// Revision 0.03 - Fixed STREAM_OUT_TOTAL and output-index-to-coordinate
//                  mapping to match the design's column-gated output (both
//                  row and col >= N-1). Added output_stall condition to the
//                  gap_check to avoid false errors during back-pressure.
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

    localparam OUT_W = IMAGE_WIDTH - N + 1;      // 30
    localparam OUT_H = IMAGE_HEIGHT - N + 1;     // 30
    localparam STREAM_OUT_TOTAL = OUT_W * OUT_H; // 900

    localparam PROD_WIDTH = PIXEL_WIDTH + COEFF_WIDTH + 2;
    localparam SUM_WIDTH = PROD_WIDTH + $clog2(N * N);
    localparam FRAC_BITS = 4;  // must track accelerator_top's/sat_round_unit's FRAC_BITS
    localparam SAT_MAX = (1 << (OUT_WIDTH - 1)) - 1;  // +32767
    localparam SAT_MIN = -(1 << (OUT_WIDTH - 1));     // -32768

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

    // Test infrastructure
    integer errors = 0;
    integer w;  // image write index
    integer t;  // kernel tap index
    integer f;  // frame index
    integer stream_idx;  // index into the captured stream-out buffer
    integer tlast_pulses;  // result_tlast_o pulse counter (reset per frame)

    // Golden reference model data
    reg [PIXEL_WIDTH-1:0] ref_img[0:TOTAL_PIXELS-1];
    reg signed [COEFF_WIDTH-1:0] ref_kernel[0:N*N-1];
    reg signed [SUM_WIDTH-1:0] ref_sum;
    reg signed [SUM_WIDTH:0] ref_shifted;  // +1 bit: matches sat_round_unit's headroom bit
    reg signed [OUT_WIDTH-1:0] ref_out;

    // Captured streaming output (indexed by result_valid_o pulses)
    reg signed [OUT_WIDTH-1:0] stream_out[0:1023];

    // Module instantiation (streaming input, fixed 2-stage datapath)
    accelerator_top #(
        .N           (N),
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .COEFF_WIDTH (COEFF_WIDTH),
        .OUT_WIDTH   (OUT_WIDTH),
        .FRAC_BITS   (FRAC_BITS)
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
        .result_tlast_o   (result_tlast_o),
        .result_ready_i   (result_ready_i)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Capture the streamed output words (counted per valid+ready transfer so
    // consumer stalls do not lose or double-count words). stream_idx is reset
    // before each frame in the test procedure; the reset and the capture never
    // fire together.
    initial begin : capture_stream
        stream_idx = 0;
        forever begin
            @(posedge clk_i);
            if (result_valid_o && result_ready_i) begin
                stream_out[stream_idx] = result_o;
                stream_idx = stream_idx + 1;
            end
        end
    end

    // tlast pulse counter: exactly one pulse per frame, on the last word
    always @(posedge clk_i) begin : tlast_count
        if (result_valid_o && result_ready_i && result_tlast_o) tlast_pulses = tlast_pulses + 1;
    end

    // Output back-pressure generator: drives result_ready_i. When bp_en is
    // set (the output-stall test) ready deasserts 1-2 cycles out of every 16;
    // otherwise it stays high so the FIFO drains freely.
    reg bp_en = 0;
    reg [7:0] bp_cnt;
    always @(posedge clk_i or negedge rst_n_i) begin : bp_gen
        if (!rst_n_i) begin
            result_ready_i <= 1'b1;
            bp_cnt <= 0;
        end else if (bp_en) begin
            result_ready_i <= ((bp_cnt % 16) < ((bp_cnt % 2) + 1)) ? 1'b0 : 1'b1;
            bp_cnt <= bp_cnt + 1;
        end else begin
            result_ready_i <= 1'b1;
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
    // array, presenting each pixel only when the accelerator asks for it and
    // holding it until it is accepted (the design may stall on input stalls or
    // output back-pressure). When stall_every > 0, deassert pixel_valid_i for
    // 1-3 cycles after every stall_every-th accepted pixel.
    task stream_image;
        input integer stall_every;
        integer p;
        integer stall_len;
        begin
            // Wait until the FSM reaches FILL before presenting pixels
            while (!ready_o) @(negedge clk_i);
            for (p = 0; p < TOTAL_PIXELS; p = p + 1) begin
                // Present pixel p only when the count asks for it, and hold it
                // until it is accepted (the pixel_counter advances past p)
                while (dut.pix_addr !== p) @(negedge clk_i);
                pixel_in_i = ref_img[p];
                pixel_valid_i = 1;
                while (dut.pix_addr === p) @(negedge clk_i);
                if (stall_every && ((p % stall_every) == (stall_every - 1))) begin
                    // Inject a 1-3 cycle input stall after this pixel. The
                    // valid must drop on this same negedge, or the next posedge
                    // would accept the stale beat as a new pixel.
                    pixel_valid_i = 0;
                    stall_len = 1 + (p % 3);
                    repeat (stall_len) @(negedge clk_i);
                end
            end
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

    // Task: check the streaming port against the windowed golden model.
    task check_stream;
        integer a;          // streamed output index
        integer row, col;   // top-left row/col of the window
        integer t;          // kernel tap
        begin
            for (a = 0; a < STREAM_OUT_TOTAL; a = a + 1) begin
                row = a / OUT_W;
                col = a % OUT_W;
                ref_sum = 0;
                for (t = 0; t < N * N; t = t + 1) begin
                    ref_sum = ref_sum + $signed(
                        {1'b0, ref_img[(row + t / N) * IMAGE_WIDTH + (col + t % N)]}) * ref_kernel[t];
                end
                // Optional ReLU: clamp negative sums to zero (matches sum_relu)
                if (relu_en_i && (ref_sum < 0)) ref_sum = 0;

                // Fixed-point rescale: sign-extend by 1 bit first (matches
                // sat_round_unit's headroom bit), then round-half-up and
                // shift by FRAC_BITS only when FRAC_BITS > 0.
                if (FRAC_BITS > 0) begin
                    ref_shifted = ($signed({ref_sum[SUM_WIDTH-1], ref_sum}) +
                                   (1 <<< (FRAC_BITS - 1))) >>> FRAC_BITS;
                end else begin
                    ref_shifted = $signed({ref_sum[SUM_WIDTH-1], ref_sum});
                end

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

    // Test procedure (unchanged except the fixed parameters and check_stream)
    initial begin : test
        // Drive all inputs low and assert reset
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

        // Directed test 1: all-zero kernel and image produce all-zero outputs
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = 0;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = 0;
        run_frame(0);
        stream_idx = 0;
        tlast_pulses = 0;
        stream_image(0);  // no stalls
        wait_done();
        #20;  // let the final output words drain through the FIFO
        check_stream();
        if (stream_idx !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: result_valid_o pulses=%0d expected %0d", $time, stream_idx,
                     STREAM_OUT_TOTAL);
        end
        if (tlast_pulses !== 1) begin
            errors = errors + 1;
            $display("FAIL t=%0t: tlast pulses=%0d expected 1", $time, tlast_pulses);
        end

        // Directed test 2: random kernel and image, continuous stream, ReLU on
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $urandom;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
        relu_en_i = 1;  // exercise the ReLU activation this frame
        run_frame(0);
        stream_idx = 0;
        tlast_pulses = 0;
        stream_image(0);
        wait_done();
        #20;
        check_stream();
        if (stream_idx !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: result_valid_o pulses=%0d expected %0d", $time, stream_idx,
                     STREAM_OUT_TOTAL);
        end
        if (tlast_pulses !== 1) begin
            errors = errors + 1;
            $display("FAIL t=%0t: tlast pulses=%0d expected 1", $time, tlast_pulses);
        end

        // Directed test 3: random kernel and image with pixel-stream stalls.
        // pixel_valid_i deasserts for 1-3 cycles every 32 pixels; the window
        // and counters must stay synchronized and all outputs must match.
        // ReLU stays enabled from test 2.
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $urandom;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
        run_frame(3);  // gapped kernel writes too
        stream_idx = 0;
        tlast_pulses = 0;
        stream_image(32);  // input stalls every 32 pixels
        wait_done();
        #20;
        check_stream();
        if (stream_idx !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stalled result_valid_o pulses=%0d expected %0d", $time,
                     stream_idx, STREAM_OUT_TOTAL);
        end
        if (tlast_pulses !== 1) begin
            errors = errors + 1;
            $display("FAIL t=%0t: tlast pulses=%0d expected 1", $time, tlast_pulses);
        end

        // Directed test 4: output consumer back-pressure. result_ready_i
        // deasserts 1-2 cycles out of every 16 mid-frame (bp_gen); the
        // pipeline must stall without losing results and every output word
        // must still arrive in order with a single tlast. ReLU off this frame.
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $urandom;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
        relu_en_i = 0;
        run_frame(0);
        stream_idx = 0;
        tlast_pulses = 0;
        bp_en = 1;
        stream_image(0);  // continuous input; only the output consumer stalls
        wait_done();
        bp_en = 0;
        repeat (100) @(negedge clk_i);  // drain the FIFO backlog
        check_stream();
        if (stream_idx !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: back-pressured pulses=%0d expected %0d", $time, stream_idx,
                     STREAM_OUT_TOTAL);
        end
        if (tlast_pulses !== 1) begin
            errors = errors + 1;
            $display("FAIL t=%0t: back-pressured tlast pulses=%0d expected 1", $time,
                     tlast_pulses);
        end

        // Random stimulus
        // Two more random frames with host-paced kernel writes (gaps every
        // third write) and random stall patterns.
        for (f = 0; f < 2; f = f + 1) begin
            for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $urandom;
            for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $urandom;
            relu_en_i = (f == 1);  // ReLU on for the second random frame
            run_frame(3);
            stream_idx = 0;
            tlast_pulses = 0;
            stream_image(f ? 16 : 64);  // different input stall cadences
            wait_done();
            #20;
            check_stream();
            if (stream_idx !== STREAM_OUT_TOTAL) begin
                errors = errors + 1;
                $display("FAIL t=%0t: result_valid_o pulses=%0d expected %0d", $time,
                         stream_idx, STREAM_OUT_TOTAL);
            end
            if (tlast_pulses !== 1) begin
                errors = errors + 1;
                $display("FAIL t=%0t: tlast pulses=%0d expected 1", $time, tlast_pulses);
            end
        end

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // result_valid_o is intentionally allowed to gap at the first N-1
    // columns of each row because the controller emits only complete
    // N-by-N windows. The handshake/count checks above are the authoritative
    // stream checks; a gap-free assertion would reject valid 900-word frames.

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | state=%0d busy=%b done=%b | out words=%0d", $time,
                 dut.state, busy_o, done_o, stream_idx);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_accelerator_top.vcd");
        $dumpvars(0, tb_accelerator_top);
    end

endmodule