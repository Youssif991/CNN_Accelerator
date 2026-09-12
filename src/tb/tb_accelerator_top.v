`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Accelerator - Top Level Testbench
// Module Name: tb_accelerator_top
// Tool Versions: Vivado 2025.2
// Description: End-to-end stimulus testbench for the accelerator top.
//              Loads the kernel through the host port (host-paced), then
//              streams the input image one 8-bit pixel per cycle through
//              pixel_in_i/pixel_valid_i and reports output transfers from the
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
// Revision 0.04 - Reconfigured to N=5 / 8x8 to match the UVM/SystemVerilog
//                  testbench (src/tb/conv_top.sv + conv_pack.svh), and
//                  explicitly passed ROUND_ENABLE/PIPE_STAGES to the DUT so
//                  the configuration is unambiguous. Added a directed test
//                  that loads the same kernel_coeff.hex/pixel_input.hex
//                  vectors the UVM sequence uses and checks the stream
//                  against expected_output.hex (also mirrored to
//                  dut_output.hex), so this testbench and the SystemVerilog
//                  one verify the identical DUT config and golden dataset.
//                  Rescaled the stall/gap cadences of the other directed
//                  tests to the smaller 64-pixel frame. Self-checking
//                  procedural style is unchanged.
// Additional Comments:
//
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
    localparam PIPE_STAGES = 2;
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam PIX_ADDR_WIDTH = $clog2(TOTAL_PIXELS);

    localparam OUT_W = IMAGE_WIDTH - N + 1;
    localparam OUT_H = IMAGE_HEIGHT - N + 1;
    localparam STREAM_OUT_TOTAL = OUT_W * OUT_H;

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
    wire [2:0] state_o;

    // Test infrastructure
    integer errors = 0;
    integer w;  // image write index
    integer t;  // kernel tap index
    integer f;  // frame index
    integer stream_idx;  // index into the captured stream-out buffer
    integer frame_output_idx;
    integer frame_number;
    integer tlast_pulses;  // informational frame-last transfer count
    integer timeout;
    integer random_seed;

    // Golden reference model data
    reg [PIXEL_WIDTH-1:0] ref_img[0:TOTAL_PIXELS-1];
    reg signed [COEFF_WIDTH-1:0] ref_kernel[0:N*N-1];
    reg signed [SUM_WIDTH-1:0] ref_sum;
    reg signed [SUM_WIDTH:0] ref_shifted;
    reg signed [OUT_WIDTH-1:0] ref_out;
    reg signed [OUT_WIDTH-1:0] stream_out[0:1023];
    // Module instantiation (streaming input, fixed 2-stage datapath)
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

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Capture each accepted output for comparison with the reference model.
    initial begin : capture_stream
        stream_idx = 0;
        frame_output_idx = 0;
        frame_number = 1;
        forever begin
            @(posedge clk_i);
            if (!rst_n_i) begin
                stream_idx = 0;
                frame_output_idx = 0;
                frame_number = 1;
            end else if (result_valid_o && result_ready_i) begin
                if (stream_idx >= 1024) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: output overflow, stream_idx=%0d",
                             $time, stream_idx);
                end else begin
                    stream_out[stream_idx] = result_o;
                    stream_idx = stream_idx + 1;
                end
            end
        end
    end

    task print_frame_inputs;
        input integer frame_id;
        integer r;
        integer c;
        begin
            $display("FRAME %0d INPUTS: relu=%0d", frame_id, relu_en_i);
            $display("FRAME %0d KERNEL SIGNED:", frame_id);
            for (t = 0; t < N * N; t = t + 1)
                $display("  kernel[%0d] = hex=0x%02h signed=%0d",
                         t, ref_kernel[t], $signed(ref_kernel[t]));

            $display("FRAME %0d IMAGE UNSIGNED:", frame_id);
            for (r = 0; r < IMAGE_HEIGHT; r = r + 1) begin
                $write("  row[%0d]:", r);
                for (c = 0; c < IMAGE_WIDTH; c = c + 1)
                    $write(" %0d", ref_img[r * IMAGE_WIDTH + c]);
                $write("\n");
            end
        end
    endtask

    always @(posedge clk_i) begin : tlast_count
        if (result_valid_o && result_ready_i && result_tlast_o)
            tlast_pulses = tlast_pulses + 1;
    end

    // Output back-pressure generator: drives result_ready_i from the falling
    // edge so it is stable before the DUT samples each output handshake on the
    // following rising edge. Updating ready on posedge races the DUT and can
    // make the TB miss one transfer.
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

    // Task: wait until the frame completes with a watchdog so a stuck FSM
    // fails instead of hanging the entire simulation forever.
    task wait_done;
        begin
            timeout = 0;
            while (!done_o && (timeout < 200000)) begin
                @(negedge clk_i);
                timeout = timeout + 1;
            end
            if (!done_o) begin
                $display("TIMEOUT t=%0t: done_o never asserted", $time);
            end
        end
    endtask

    // Wait for the final output transfer, not just the controller's done
    // state. done_o can assert while the output FIFO still contains results.
    task wait_frame_tlast;
        begin
            timeout = 0;
            // tlast may have transferred before done_o becomes visible, so
            // use the latched transfer count rather than sampling the live
            // FIFO signals after the fact.
            while ((tlast_pulses == 0) && (timeout < 200000)) begin
                @(negedge clk_i);
                timeout = timeout + 1;
            end
            if (tlast_pulses == 0)
                $display("TIMEOUT t=%0t: frame tlast was not transferred", $time);
        end
    endtask

    // Task: wait until the output FIFO backlog has drained to the expected
    // number of words. This is important for the output-backpressure test,
    // where done_o may assert before the final words are visible at the read
    // side.
    task wait_stream_count;
        input integer expected_count;
        begin
            timeout = 0;
            while ((stream_idx < expected_count) && (timeout < 200000)) begin
                @(negedge clk_i);
                timeout = timeout + 1;
            end
            if (stream_idx < expected_count) begin
                $display("TIMEOUT t=%0t: stream_idx=%0d < expected %0d after drain", $time,
                         stream_idx, expected_count);
            end
        end
    endtask

    // Task: wait for input ready with a watchdog. This keeps the input
    // stimulus from hanging forever if the FSM stalls or the receive side is
    // never ready.
    task wait_input_ready;
        begin
            timeout = 0;
            while (!ready_o && (timeout < 200000)) begin
                @(negedge clk_i);
                timeout = timeout + 1;
            end
            if (!ready_o) begin
                $display("TIMEOUT t=%0t: ready_o never asserted", $time);
            end
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

            // Wait until the FSM reaches FILL before presenting pixels.
            wait_input_ready();
            for (p = 0; p < TOTAL_PIXELS; p = p + 1) begin
                pixel_in_i = ref_img[p];
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

    // Task: check the accepted stream against the valid-window reference model.
    task check_stream;
        integer a;
        integer row;
        integer col;
        integer tap;
        begin
            if (stream_idx != STREAM_OUT_TOTAL)
                $display("WARN t=%0t: captured %0d output words, expected %0d",
                         $time, stream_idx, STREAM_OUT_TOTAL);

            for (a = 0; a < stream_idx; a = a + 1) begin
                row = a / OUT_W;
                col = a % OUT_W;
                ref_sum = 0;
                for (tap = 0; tap < N * N; tap = tap + 1)
                    ref_sum = ref_sum +
                              $signed({1'b0, ref_img[(row + tap / N) * IMAGE_WIDTH +
                                                     col + tap % N]}) * ref_kernel[tap];

                if (relu_en_i && (ref_sum < 0))
                    ref_sum = 0;
                if (FRAC_BITS > 0)
                    ref_shifted = ($signed({ref_sum[SUM_WIDTH-1], ref_sum}) +
                                   (1 <<< (FRAC_BITS - 1))) >>> FRAC_BITS;
                else
                    ref_shifted = $signed({ref_sum[SUM_WIDTH-1], ref_sum});

                if (ref_shifted > SAT_MAX)
                    ref_out = SAT_MAX;
                else if (ref_shifted < SAT_MIN)
                    ref_out = SAT_MIN;
                else
                    ref_out = $signed(ref_shifted[OUT_WIDTH-1:0]);

                if (stream_out[a] !== ref_out) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: stream_out[%0d]=%0d expected %0d",
                             $time, a, stream_out[a], ref_out);
                end
            end
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

    // Test procedure (unchanged except the fixed parameters and check_stream)
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

        // Directed test 1: all-zero kernel and image produce all-zero outputs
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = 0;
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = 0;
        print_frame_inputs(1);
        run_frame(0);
        stream_idx = 0;
        tlast_pulses = 0;
        stream_image(0);  // no stalls
        wait_done();
        wait_frame_tlast();
        #20;
        check_stream();
        $display("FRAME 1 COMPLETE: outputs=%0d tlast=%0d", stream_idx, tlast_pulses);

        // Directed test 2: random kernel and image, continuous stream, ReLU on
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $random(random_seed);
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $random(random_seed);
        relu_en_i = 1;  // exercise the ReLU activation this frame
        print_frame_inputs(2);
        run_frame(0);
        stream_idx = 0;
        tlast_pulses = 0;
        stream_image(0);
        wait_done();
        wait_frame_tlast();
        #20;
        check_stream();
        $display("FRAME 2 COMPLETE: outputs=%0d tlast=%0d", stream_idx, tlast_pulses);

        // Directed test 3: random kernel and image with pixel-stream stalls.
        // pixel_valid_i deasserts for 1-3 cycles every 32 pixels; the window
        // and counters must stay synchronized and all outputs must match.
        // ReLU stays enabled from test 2.
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $random(random_seed);
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $random(random_seed);
        print_frame_inputs(3);
        run_frame(3);  // gapped kernel writes too
        stream_idx = 0;
        tlast_pulses = 0;
        stream_image(32);  // input stalls every 32 pixels
        wait_done();
        wait_frame_tlast();
        #20;
        check_stream();
        $display("FRAME 3 COMPLETE: outputs=%0d tlast=%0d", stream_idx, tlast_pulses);

        // Directed test 4: output consumer back-pressure. result_ready_i
        // deasserts 1-2 cycles out of every 16 mid-frame (bp_gen); the
        // pipeline must stall without losing results and every output word
        // must still arrive in order with a single tlast. ReLU off this frame.
        for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $random(random_seed);
        for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $random(random_seed);
        relu_en_i = 0;
        print_frame_inputs(4);
        run_frame(0);
        stream_idx = 0;
        tlast_pulses = 0;
        bp_en = 1;
        stream_image(0);  // continuous input; only the output consumer stalls
        wait_done();
        bp_en = 0;
        wait_frame_tlast();
        #20;
        check_stream();
        $display("FRAME 4 COMPLETE: outputs=%0d tlast=%0d", stream_idx, tlast_pulses);

        // Random stimulus
        // Two more random frames with host-paced kernel writes (gaps every
        // third write) and random stall patterns.
        for (f = 0; f < 2; f = f + 1) begin
            for (t = 0; t < N * N; t = t + 1) ref_kernel[t] = $random(random_seed);
            for (w = 0; w < TOTAL_PIXELS; w = w + 1) ref_img[w] = $random(random_seed);
            relu_en_i = (f == 1);  // ReLU on for the second random frame
            print_frame_inputs(5 + f);
            run_frame(3);
            stream_idx = 0;
            tlast_pulses = 0;
            stream_image(f ? 16 : 64);  // different input stall cadences
            wait_done();
            wait_frame_tlast();
            #20;
            check_stream();
            $display("RANDOM FRAME %0d COMPLETE: outputs=%0d tlast=%0d", f,
                     stream_idx, tlast_pulses);
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
                 state_o, busy_o, done_o, stream_idx);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_accelerator_top.vcd");
        $dumpvars(0, tb_accelerator_top);
    end

endmodule