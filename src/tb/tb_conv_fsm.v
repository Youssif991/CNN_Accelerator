`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Control - Conv FSM Testbench
// Module Name: tb_conv_fsm
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the convolution frame controller
//              wired together with the input pixel counter (the control unit
//              as integrated in the accelerator top). IMAGE_HEIGHT here is the
//              *padded* row count (real rows + N-1 leading zero-padding rows),
//              matching conv_fsm's contract now that pixel_pad_inserter/
//              window_array handle zero-padding upstream. A golden reference
//              models the frame phases with its own shift counter (independent
//              of the DUT's counter); the checker compares every FSM output
//              (including the new row_start_o/stream_start_o) on negedge.
//              Covers reset, a full frame with exact cycle counts, a second
//              frame, pixel-stream stalls (pixel_valid_i deasserted), output
//              back-pressure (output_stall_i), and randomized start-request
//              stimulus.
//
// Dependencies: conv_fsm (src/control/conv_fsm.v)
//               pixel_counter (src/control/pixel_counter.v)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Removed the FILL state and the column gate from the golden
//                  reference (matches conv_fsm Rev 0.03): IMAGE_HEIGHT is now
//                  the padded row count, block_valid is row-only, and
//                  row_start_o/stream_start_o are checked every cycle.
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_conv_fsm;

    // Parameters
    localparam N = 3;
    localparam IMAGE_WIDTH = 32;
    localparam PAD_ROWS_BEFORE = N - 1;
    localparam IMAGE_HEIGHT = 32 + PAD_ROWS_BEFORE;  // padded row count (real 32 + N-1 pad rows)
    localparam COEFF_WIDTH = 8;
    localparam PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT);
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    // Streamed outputs per frame: one per real image pixel (rows past the
    // N-1 padding-row prefix), gap-free thanks to the row-start window flush.
    localparam STREAM_OUT_TOTAL = (IMAGE_HEIGHT - N + 1) * IMAGE_WIDTH;
    localparam STATE_WIDTH = 2;
    localparam NUM_TESTS = 300;  // random stimulus cycles

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg start_i;
    reg pixel_valid_i;
    reg output_stall_i;
    reg kernel_wr_valid_i;
    reg [COEFF_WIDTH-1:0] kernel_data_i;
    wire kernel_we_o;
    wire [$clog2(N*N)-1:0] kernel_addr_o;
    wire shift_valid_o;
    wire row_start_o;
    wire stream_start_o;
    wire ready_o;
    wire result_valid_o;
    wire rst_count_o;
    wire busy_o;
    wire done_o;
    wire [STATE_WIDTH-1:0] state_o;

    // Address-generator interconnect (as wired in the accelerator top)
    wire [PIX_ADDR_WIDTH-1:0] pix_addr;
    wire pix_last;

    // Test infrastructure
    integer i;  // test loop counter
    integer errors = 0;
    integer load_count;  // accepted kernel writes per frame
    integer shift_count;  // shift-valid cycles per frame
    integer valid_count;  // result-valid pulses per frame
    integer kernel_wr_count;  // kernel write pulses issued per frame
    integer gap_cnt;  // cycle counter for the gapped-load test
    reg seen_done;
    reg second_frame_started;

    // Module instantiation
    conv_fsm #(
        .N             (N),
        .IMAGE_WIDTH   (IMAGE_WIDTH),
        .IMAGE_HEIGHT  (IMAGE_HEIGHT),
        .COEFF_WIDTH   (COEFF_WIDTH),
        .PIX_ADDR_WIDTH(PIX_ADDR_WIDTH),
        .STATE_WIDTH   (STATE_WIDTH)
    ) dut (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .start_i       (start_i),
        .pixel_valid_i (pixel_valid_i),
        .output_stall_i(output_stall_i),
        .kernel_wr_valid_i(kernel_wr_valid_i),
        .kernel_data_i (kernel_data_i),
        .pix_addr_i    (pix_addr),
        .pix_last_i    (pix_last),
        .kernel_we_o   (kernel_we_o),
        .kernel_addr_o (kernel_addr_o),
        .shift_valid_o (shift_valid_o),
        .row_start_o   (row_start_o),
        .stream_start_o(stream_start_o),
        .ready_o       (ready_o),
        .result_valid_o(result_valid_o),
        .rst_count_o   (rst_count_o),
        .busy_o        (busy_o),
        .done_o        (done_o),
        .state_o       (state_o)
    );

    pixel_counter #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH  (PIX_ADDR_WIDTH)
    ) u_in (
        .clk_i       (clk_i),
        .rst_n_i     (rst_n_i),
        .en_i        (shift_valid_o),
        .rst_count_i (rst_count_o),
        .addr_o      (pix_addr),
        .last_o      (pix_last)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Golden reference: independent cycle-based phase model.
    // Tracks the frame phases with its own shift counter (not the DUT's
    // address generators), so counter or FSM bugs cannot be copied.
    localparam PH_IDLE = 0;
    localparam PH_LOAD = 1;
    localparam PH_COMPUTE = 2;
    localparam PH_DONE = 3;

    reg [STATE_WIDTH-1:0] ref_phase_q;
    reg [PIX_ADDR_WIDTH-1:0] ref_shifts_q;  // pixels shifted so far
    reg [$clog2(N*N)-1:0] ref_load_q;  // kernel load index
    reg [1:0] ref_exit_q;  // compute-exit countdown
    reg expected_result_valid;

    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            ref_phase_q <= PH_IDLE;
            ref_shifts_q <= 0;
            ref_load_q <= 0;
            ref_exit_q <= 0;
            expected_result_valid <= 1'b0;
        end else begin
            // Default: no result this cycle unless PH_COMPUTE overrides it
            // below (mirrors the DUT's result_valid_d = 1'b0 default before
            // its case statement).
            expected_result_valid <= 1'b0;

            // Shift counter: restart at frame start, count only accepted pixels
            // (a deasserted pixel_valid_i stalls the stream without shifting)
            if (rst_count_o) begin
                ref_shifts_q <= 0;
            end else if ((ref_phase_q == PH_COMPUTE) && pixel_valid_i && !output_stall_i) begin
                // Wraps exactly like the real pixel_counter: the 2-cycle exit
                // drain keeps shifting (pixel_valid_i stays high) past the
                // last real pixel, so this must wrap back to 0 too, or
                // block_valid would incorrectly stay true during the drain.
                ref_shifts_q <= (ref_shifts_q == TOTAL_PIXELS-1) ? 0 : ref_shifts_q + 1;
            end

            case (ref_phase_q)
                // Wait for a frame-start request
                PH_IDLE: begin
                    if (start_i) ref_phase_q <= PH_LOAD;
                end
                // Load the N*N kernel coefficients, one per host write
                PH_LOAD: begin
                    if (kernel_wr_valid_i) begin
                        ref_load_q <= (ref_load_q == N*N-1) ? 0 : ref_load_q + 1;
                        if (ref_load_q == N*N-1) ref_phase_q <= PH_COMPUTE;
                    end
                end
                // Shift the padded stream and produce one output pixel per cycle
                PH_COMPUTE: begin
                    if (output_stall_i) begin
                        expected_result_valid <= expected_result_valid;  // hold (matches result_valid_d = result_valid_q)
                    end else begin
                        expected_result_valid <= ref_block_valid && pixel_valid_i;
                        if (ref_shifts_q == TOTAL_PIXELS-1) begin
                            ref_exit_q <= 2;
                        end else if (ref_exit_q > 0) begin
                            ref_exit_q <= ref_exit_q - 1;
                            if (ref_exit_q == 1) ref_phase_q <= PH_DONE;
                        end
                    end
                end
                // Hold the done flag, then re-arm for the next frame
                PH_DONE: ref_phase_q <= PH_IDLE;
                default: ref_phase_q <= PH_IDLE;
            endcase
        end
    end

    // Reference block-valid: row-only gate, using the padded row count. Every
    // column past the N-1 padding-row prefix is already a correct,
    // zero-padded window thanks to window_array's row-start flush.
    wire ref_block_valid = ((ref_shifts_q / IMAGE_WIDTH) >= N-1);

    // Expected Moore outputs (combinational from the reference phase).
    // shift_valid is gated by the pixel stream: a deasserted valid stalls
    // the datapath (line buffers, window, address counters).
    wire expected_kernel_we = (ref_phase_q == PH_LOAD);
    wire expected_ready = (ref_phase_q == PH_COMPUTE) && !output_stall_i;
    wire expected_shift_valid = (ref_phase_q == PH_COMPUTE) && pixel_valid_i && !output_stall_i;
    wire expected_row_start = expected_shift_valid && ((ref_shifts_q % IMAGE_WIDTH) == 0);
    wire expected_stream_start = (ref_phase_q == PH_LOAD) && kernel_wr_valid_i &&
                                  (ref_load_q == N*N-1);
    wire expected_rst_count = (ref_phase_q == PH_LOAD);
    wire expected_busy = (ref_phase_q == PH_LOAD) || (ref_phase_q == PH_COMPUTE);
    wire expected_done = (ref_phase_q == PH_DONE);

    // Checker
    // Compares every control output on negedge, after the posedge capture
    // has settled.
    always @(negedge clk_i) begin : check
        if (rst_n_i) begin
            if (state_o !== ref_phase_q) begin
                errors = errors + 1;
                $display("FAIL t=%0t: state=%0d expected=%0d", $time, state_o, ref_phase_q);
            end
            if (kernel_we_o !== expected_kernel_we) begin
                errors = errors + 1;
                $display("FAIL t=%0t: kernel_we=%b expected=%b", $time, kernel_we_o,
                         expected_kernel_we);
            end
            if (kernel_addr_o !== ref_load_q) begin
                errors = errors + 1;
                $display("FAIL t=%0t: kernel_addr=%0d expected=%0d", $time, kernel_addr_o,
                         ref_load_q);
            end
            if (shift_valid_o !== expected_shift_valid) begin
                errors = errors + 1;
                $display("FAIL t=%0t: shift_valid=%b expected=%b", $time, shift_valid_o,
                         expected_shift_valid);
            end
            if (row_start_o !== expected_row_start) begin
                errors = errors + 1;
                $display("FAIL t=%0t: row_start=%b expected=%b", $time, row_start_o,
                         expected_row_start);
            end
            if (stream_start_o !== expected_stream_start) begin
                errors = errors + 1;
                $display("FAIL t=%0t: stream_start=%b expected=%b", $time, stream_start_o,
                         expected_stream_start);
            end
            if (ready_o !== expected_ready) begin
                errors = errors + 1;
                $display("FAIL t=%0t: ready=%b expected=%b", $time, ready_o, expected_ready);
            end
            if (result_valid_o !== expected_result_valid) begin
                errors = errors + 1;
                $display("FAIL t=%0t: result_valid=%b expected=%b", $time, result_valid_o,
                         expected_result_valid);
            end
            if (rst_count_o !== expected_rst_count) begin
                errors = errors + 1;
                $display("FAIL t=%0t: rst_count=%b expected=%b", $time, rst_count_o,
                         expected_rst_count);
            end
            if (busy_o !== expected_busy) begin
                errors = errors + 1;
                $display("FAIL t=%0t: busy=%b expected=%b", $time, busy_o, expected_busy);
            end
            if (done_o !== expected_done) begin
                errors = errors + 1;
                $display("FAIL t=%0t: done=%b expected=%b", $time, done_o, expected_done);
            end
        end
    end

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        start_i = 0;
        pixel_valid_i = 0;
        output_stall_i = 0;
        kernel_wr_valid_i = 0;
        kernel_data_i = 0;
        rst_n_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;
        @(negedge clk_i);

        // Directed test 1: hold idle with no start request
        repeat (5) @(negedge clk_i);
        if (state_o !== 0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: not idle without start (state=%0d)", $time, state_o);
        end

        // Directed test 2: a full frame with exact per-phase counts
        // Expected: 9 accepted kernel writes, TOTAL_PIXELS+2 shift cycles
        // (the padded-row prefix is just part of the same COMPUTE stream now,
        // plus a 2-cycle exit drain), STREAM_OUT_TOTAL result-valid pulses
        // (one per real image pixel), then done/re-arm.
        load_count = 0;
        shift_count = 0;
        valid_count = 0;
        kernel_wr_count = 0;
        seen_done = 0;
        pixel_valid_i = 1;  // continuous stream for the exact-count frame

        start_i = 1;
        repeat (1364) begin
            @(negedge clk_i);
            start_i = 0;  // one-cycle start pulse
            // Issue the N*N kernel writes back-to-back after the start
            if (kernel_wr_count < N*N) begin
                kernel_wr_valid_i = 1;
                kernel_data_i = kernel_wr_count;
                kernel_wr_count = kernel_wr_count + 1;
            end else begin
                kernel_wr_valid_i = 0;
            end
            if (kernel_we_o && kernel_wr_valid_i) load_count = load_count + 1;
            if (shift_valid_o) shift_count = shift_count + 1;
            if (result_valid_o) valid_count = valid_count + 1;
            if (done_o) seen_done = 1;
        end

        if (load_count !== N*N) begin
            errors = errors + 1;
            $display("FAIL t=%0t: kernel writes=%0d expected %0d", $time, load_count, N*N);
        end
        if (shift_count !== TOTAL_PIXELS + 2) begin
            errors = errors + 1;
            $display("FAIL t=%0t: shift cycles=%0d expected %0d", $time, shift_count,
                     TOTAL_PIXELS + 2);
        end
        if (valid_count !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: result pulses=%0d expected %0d", $time, valid_count,
                     STREAM_OUT_TOTAL);
        end
        if (!seen_done) begin
            errors = errors + 1;
            $display("FAIL t=%0t: done_o never asserted", $time);
        end
        if (state_o !== 0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: did not re-arm to idle (state=%0d)", $time, state_o);
        end

        // Directed test 3: host-paced load with gaps between kernel writes
        // The FSM must wait in LOAD and still produce a full frame.
        load_count = 0;
        valid_count = 0;
        kernel_wr_count = 0;
        gap_cnt = 0;
        seen_done = 0;
        pixel_valid_i = 1;  // continuous stream for the gapped-load frame

        start_i = 1;
        repeat (1564) begin
            @(negedge clk_i);
            start_i = 0;  // one-cycle start pulse
            gap_cnt = gap_cnt + 1;
            // Issue one kernel write every three cycles (two-cycle gaps)
            if ((gap_cnt % 3 == 1) && (kernel_wr_count < N*N)) begin
                kernel_wr_valid_i = 1;
                kernel_wr_count = kernel_wr_count + 1;
            end else begin
                kernel_wr_valid_i = 0;
            end
            kernel_data_i = kernel_wr_count;
            if (kernel_we_o && kernel_wr_valid_i) load_count = load_count + 1;
            if (result_valid_o) valid_count = valid_count + 1;
            if (done_o) seen_done = 1;
        end

        if (load_count !== N*N) begin
            errors = errors + 1;
            $display("FAIL t=%0t: gapped kernel writes=%0d expected %0d", $time, load_count,
                     N*N);
        end
        if (valid_count !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: gapped frame pulses=%0d expected %0d", $time, valid_count,
                     STREAM_OUT_TOTAL);
        end
        if (!seen_done) begin
            errors = errors + 1;
            $display("FAIL t=%0t: gapped frame never completed", $time);
        end

        // Directed test 4: a second frame starts cleanly after the first
        second_frame_started = 0;
        valid_count = 0;
        kernel_wr_count = 0;
        pixel_valid_i = 1;  // continuous stream for the second frame

        start_i = 1;
        repeat (1164) begin
            @(negedge clk_i);
            start_i = 0;  // one-cycle start pulse
            if (kernel_wr_count < N*N) begin
                kernel_wr_valid_i = 1;
                kernel_wr_count = kernel_wr_count + 1;
            end else begin
                kernel_wr_valid_i = 0;
            end
            if (state_o === 1) second_frame_started = 1;
            if (result_valid_o) valid_count = valid_count + 1;
        end
        if (!second_frame_started) begin
            errors = errors + 1;
            $display("FAIL t=%0t: second frame never entered LOAD", $time);
        end
        if (valid_count !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: second frame pulses=%0d expected %0d", $time, valid_count,
                     STREAM_OUT_TOTAL);
        end

        // Directed test 5: pixel-stream stalls must not break synchronization.
        // Deassert pixel_valid_i for 3 cycles every 40 during the stream; the
        // negedge checker compares every FSM/address-generator output against
        // the stall-aware reference for the whole frame.
        load_count = 0;
        valid_count = 0;
        kernel_wr_count = 0;
        gap_cnt = 0;
        seen_done = 0;

        start_i = 1;
        repeat (1664) begin
            @(negedge clk_i);
            start_i = 0;  // one-cycle start pulse
            if (kernel_wr_count < N*N) begin
                kernel_wr_valid_i = 1;
                kernel_wr_count = kernel_wr_count + 1;
            end else begin
                kernel_wr_valid_i = 0;
            end
            if (state_o == 2) begin
                // 3 stall cycles out of every 40 once COMPUTE (streaming) is active
                pixel_valid_i = ((gap_cnt % 40) < 3) ? 1'b0 : 1'b1;
                gap_cnt = gap_cnt + 1;
            end else begin
                pixel_valid_i = 0;
            end
            if (kernel_we_o && kernel_wr_valid_i) load_count = load_count + 1;
            if (result_valid_o) valid_count = valid_count + 1;
            if (done_o) seen_done = 1;
        end

        if (load_count !== N*N) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stalled kernel writes=%0d expected %0d", $time, load_count,
                     N*N);
        end
        if (valid_count !== STREAM_OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stalled frame pulses=%0d expected %0d", $time, valid_count,
                     STREAM_OUT_TOTAL);
        end
        if (!seen_done) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stalled frame never completed", $time);
        end
        if (state_o !== 0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stalled frame did not re-arm (state=%0d)", $time, state_o);
        end

        // Random stimulus
        // Stress-test with random start, kernel-write, and pixel-valid
        // toggles across several frames.
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(negedge clk_i);
            start_i = $urandom & 1;
            kernel_wr_valid_i = $urandom & 1;
            pixel_valid_i = $urandom & 1;
            kernel_data_i = $urandom;
        end
        start_i = 0;
        kernel_wr_valid_i = 0;
        pixel_valid_i = 0;

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | state=%0d | shift=%b rowst=%b rv=%b | kaddr=%0d done=%b", $time,
                 state_o, shift_valid_o, row_start_o, result_valid_o, kernel_addr_o, done_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_conv_fsm.vcd");
        $dumpvars(0, tb_conv_fsm);
    end

endmodule
