`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Control - Conv FSM Testbench
// Module Name: tb_conv_fsm
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the convolution frame controller
//              wired together with the input/output address generators (the
//              control unit as integrated in the accelerator top). A golden
//              reference models the frame phases with its own shift counter
//              (independent of the DUT's address generators); the checker
//              compares every FSM and address-generator output on negedge.
//              Covers reset, a full frame with exact cycle counts, a second
//              frame, and randomized start-request stimulus.
//
// Dependencies: conv_fsm (src/control/conv_fsm.v)
//               addr_gen_in (src/control/addr_gen_in.v)
//               addr_gen_out (src/control/addr_gen_out.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_conv_fsm;

    // Parameters
    localparam N = 3;
    localparam IMAGE_WIDTH = 32;
    localparam IMAGE_HEIGHT = 32;
    localparam COEFF_WIDTH = 8;
    localparam PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT);
    localparam FILL_CYCLES = (N-1) * IMAGE_WIDTH + (N-1);
    localparam TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam OUT_IMAGE_WIDTH = IMAGE_WIDTH - N + 1;
    localparam OUT_IMAGE_HEIGHT = IMAGE_HEIGHT - N + 1;
    localparam OUT_TOTAL = OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT;
    localparam OUT_ADDR_WIDTH = $clog2(OUT_TOTAL);
    localparam STATE_WIDTH = 3;
    localparam NUM_TESTS = 300;  // random stimulus cycles

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg start_i;
    reg [COEFF_WIDTH-1:0] kernel_data_i;
    wire kernel_we_o;
    wire [$clog2(N*N)-1:0] kernel_addr_o;
    wire shift_valid_o;
    wire mem_rd_en_o;
    wire result_valid_o;
    wire rst_count_o;
    wire busy_o;
    wire done_o;
    wire [STATE_WIDTH-1:0] state_o;

    // Address-generator interconnect (as wired in the accelerator top)
    wire [PIX_ADDR_WIDTH-1:0] pix_addr;
    wire pix_last;
    wire [OUT_ADDR_WIDTH-1:0] out_addr;
    wire out_last;

    // Test infrastructure
    integer i;  // test loop counter
    integer errors = 0;
    integer load_count;  // kernel write-enable pulses per frame
    integer shift_count;  // shift-valid cycles per frame
    integer valid_count;  // result-valid pulses per frame
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
        .kernel_data_i (kernel_data_i),
        .pix_addr_i    (pix_addr),
        .pix_last_i    (pix_last),
        .kernel_we_o   (kernel_we_o),
        .kernel_addr_o (kernel_addr_o),
        .shift_valid_o (shift_valid_o),
        .mem_rd_en_o   (mem_rd_en_o),
        .result_valid_o(result_valid_o),
        .rst_count_o   (rst_count_o),
        .busy_o        (busy_o),
        .done_o        (done_o),
        .state_o       (state_o)
    );

    addr_gen_in #(
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

    addr_gen_out #(
        .OUT_IMAGE_WIDTH (OUT_IMAGE_WIDTH),
        .OUT_IMAGE_HEIGHT(OUT_IMAGE_HEIGHT),
        .ADDR_WIDTH      (OUT_ADDR_WIDTH)
    ) u_out (
        .clk_i       (clk_i),
        .rst_n_i     (rst_n_i),
        .en_i        (result_valid_o),
        .rst_count_i (rst_count_o),
        .addr_o      (out_addr),
        .last_o      (out_last)
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
    localparam PH_FILL = 2;
    localparam PH_COMPUTE = 3;
    localparam PH_DONE = 4;

    reg [STATE_WIDTH-1:0] ref_phase_q;
    reg [PIX_ADDR_WIDTH-1:0] ref_shifts_q;  // pixels shifted so far
    reg [$clog2(N*N)-1:0] ref_load_q;  // kernel load index
    reg [1:0] ref_exit_q;  // compute-exit countdown
    reg expected_result_valid;
    reg [OUT_ADDR_WIDTH-1:0] expected_out_cnt_q;

    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            ref_phase_q <= PH_IDLE;
            ref_shifts_q <= 0;
            ref_load_q <= 0;
            ref_exit_q <= 0;
            expected_result_valid <= 1'b0;
            expected_out_cnt_q <= 0;
        end else begin
            // Shift counter: restart at frame start, count while shifting
            if (rst_count_o) begin
                ref_shifts_q <= 0;
            end else if ((ref_phase_q == PH_FILL) || (ref_phase_q == PH_COMPUTE)) begin
                ref_shifts_q <= ref_shifts_q + 1;
            end

            case (ref_phase_q)
                // Wait for a frame-start request
                PH_IDLE: begin
                    if (start_i) ref_phase_q <= PH_LOAD;
                end
                // Load the N*N kernel coefficients, one per cycle
                PH_LOAD: begin
                    ref_load_q <= (ref_load_q == N*N-1) ? 0 : ref_load_q + 1;
                    if (ref_load_q == N*N-1) ref_phase_q <= PH_FILL;
                end
                // Prime the line buffers and the window with the first rows
                PH_FILL: begin
                    if (ref_shifts_q == FILL_CYCLES-1) ref_phase_q <= PH_COMPUTE;
                end
                // Shift the stream and produce one output pixel per cycle
                PH_COMPUTE: begin
                    expected_result_valid <= ref_block_valid;
                    if (ref_shifts_q == TOTAL_PIXELS-1) begin
                        ref_exit_q <= 2;
                    end else if (ref_exit_q > 0) begin
                        ref_exit_q <= ref_exit_q - 1;
                        if (ref_exit_q == 1) ref_phase_q <= PH_DONE;
                    end
                end
                // Hold the done flag, then re-arm for the next frame
                PH_DONE: ref_phase_q <= PH_IDLE;
                default: ref_phase_q <= PH_IDLE;
            endcase

            // Output counter: reset at frame start, count valid results
            if (rst_count_o) begin
                expected_out_cnt_q <= 0;
            end else if (result_valid_o) begin
                expected_out_cnt_q <= (expected_out_cnt_q == OUT_TOTAL-1) ?
                    0 : expected_out_cnt_q + 1;
            end
        end
    end

    // Reference block-valid: the current pixel completes an NxN window
    wire ref_block_valid = (ref_shifts_q / IMAGE_WIDTH >= N-1) &&
                           (ref_shifts_q % IMAGE_WIDTH >= N-1);

    // Expected Moore outputs (combinational from the reference phase)
    wire expected_kernel_we = (ref_phase_q == PH_LOAD);
    wire expected_shift_valid = (ref_phase_q == PH_FILL) || (ref_phase_q == PH_COMPUTE);
    wire expected_rst_count = (ref_phase_q == PH_LOAD);
    wire expected_busy = (ref_phase_q != PH_IDLE) && (ref_phase_q != PH_DONE);
    wire expected_done = (ref_phase_q == PH_DONE);
    wire expected_out_last = result_valid_o && (expected_out_cnt_q == OUT_TOTAL-1);

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
            if (mem_rd_en_o !== expected_shift_valid) begin
                errors = errors + 1;
                $display("FAIL t=%0t: mem_rd_en=%b expected=%b", $time, mem_rd_en_o,
                         expected_shift_valid);
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
            if (out_addr !== expected_out_cnt_q) begin
                errors = errors + 1;
                $display("FAIL t=%0t: out_addr=%0d expected=%0d", $time, out_addr,
                         expected_out_cnt_q);
            end
            if (out_last !== expected_out_last) begin
                errors = errors + 1;
                $display("FAIL t=%0t: out_last=%b expected=%b", $time, out_last,
                         expected_out_last);
            end
        end
    end

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        start_i = 0;
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
        // Expected: 9 kernel writes, 1026 shift cycles (66 fill + 958
        // compute + 2 exit), 900 result-valid pulses, then done and re-arm.
        load_count = 0;
        shift_count = 0;
        valid_count = 0;
        seen_done = 0;

        start_i = 1;
        repeat (1300) begin
            @(negedge clk_i);
            start_i = 0;  // one-cycle start pulse
            if (kernel_we_o) load_count = load_count + 1;
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
        if (valid_count !== OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: result pulses=%0d expected %0d", $time, valid_count,
                     OUT_TOTAL);
        end
        if (!seen_done) begin
            errors = errors + 1;
            $display("FAIL t=%0t: done_o never asserted", $time);
        end
        if (state_o !== 0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: did not re-arm to idle (state=%0d)", $time, state_o);
        end

        // Directed test 3: a second frame starts cleanly
        second_frame_started = 0;
        valid_count = 0;
        start_i = 1;
        repeat (1100) begin
            @(negedge clk_i);
            start_i = 0;  // one-cycle start pulse
            if (state_o === 1) second_frame_started = 1;
            if (result_valid_o) valid_count = valid_count + 1;
        end
        if (!second_frame_started) begin
            errors = errors + 1;
            $display("FAIL t=%0t: second frame never entered LOAD", $time);
        end
        if (valid_count !== OUT_TOTAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: second frame pulses=%0d expected %0d", $time, valid_count,
                     OUT_TOTAL);
        end

        // Random stimulus
        // Stress-test with random start requests across several frames.
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(negedge clk_i);
            start_i = $urandom & 1;
            kernel_data_i = $urandom;
        end
        start_i = 0;

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | state=%0d | shift=%b rv=%b | kaddr=%0d | out=%0d done=%b", $time,
                 state_o, shift_valid_o, result_valid_o, kernel_addr_o, out_addr, done_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_conv_fsm.vcd");
        $dumpvars(0, tb_conv_fsm);
    end

endmodule
