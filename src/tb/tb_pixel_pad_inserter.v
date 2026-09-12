`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/12/2026
// Design Name: CNN Convolution Accelerator - Zero-Padding Stream Inserter Testbench
// Module Name: tb_pixel_pad_inserter
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the zero-padding stream inserter.
//              A golden reference independently mirrors the padded raster
//              scan (its own row/col/active counters, not the DUT's) and
//              registers the same four outputs one cycle behind the accepted
//              position; the checker compares every output on negedge for
//              the entire simulation. Covers reset, a full continuous frame
//              (exact padded/real/ready/last pulse counts), host stalls
//              during the real-pixel region, a system pause (en_i low)
//              spanning both padding and real positions, a mid-frame
//              restart, back-to-back frames, and randomized stimulus.
//
// Dependencies: pixel_pad_inserter (src/datapath/pixel_pad_inserter.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_pixel_pad_inserter;

    // Parameters
    localparam IMAGE_WIDTH = 32;
    localparam IMAGE_HEIGHT = 32;
    localparam PIXEL_WIDTH = 8;
    localparam PAD_BEFORE = 1;
    localparam PAD_AFTER = 1;
    localparam PADDED_WIDTH = IMAGE_WIDTH + PAD_BEFORE + PAD_AFTER;
    localparam PADDED_HEIGHT = IMAGE_HEIGHT + PAD_BEFORE + PAD_AFTER;
    localparam ROW_BITS = $clog2(PADDED_HEIGHT);
    localparam COL_BITS = $clog2(PADDED_WIDTH);
    localparam TOTAL_PADDED = PADDED_WIDTH * PADDED_HEIGHT;
    localparam TOTAL_REAL = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam NUM_TESTS = 500;  // random stimulus cycles

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg en_i;
    reg start_i;
    reg [PIXEL_WIDTH-1:0] pixel_in_i;
    reg pixel_valid_i;
    wire [PIXEL_WIDTH-1:0] padded_pixel_o;
    wire padded_pixel_valid_o;
    wire ready_o;
    wire real_pixel_o;
    wire last_pixel_o;

    // Test infrastructure
    integer i;  // test loop / random-stimulus counter
    integer cycle_cnt;  // stall/pause cadence counter
    integer errors = 0;
    integer pad_valid_count;  // padded_pixel_valid_o pulses observed
    integer real_count;  // real_pixel_o pulses observed
    integer ready_count;  // ready_o pulses observed
    integer last_count;  // last_pixel_o pulses observed

    // Module instantiation
    pixel_pad_inserter #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .PAD_BEFORE  (PAD_BEFORE),
        .PAD_AFTER   (PAD_AFTER)
    ) dut (
        .clk_i               (clk_i),
        .rst_n_i             (rst_n_i),
        .en_i                (en_i),
        .start_i             (start_i),
        .pixel_in_i          (pixel_in_i),
        .pixel_valid_i       (pixel_valid_i),
        .padded_pixel_o      (padded_pixel_o),
        .padded_pixel_valid_o(padded_pixel_valid_o),
        .ready_o             (ready_o),
        .real_pixel_o        (real_pixel_o),
        .last_pixel_o        (last_pixel_o)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Golden reference: independent raster-scan mirror of the padded frame
    // (its own row/col/active counters, covering the same PAD_BEFORE/
    // PAD_AFTER geometry as the DUT, but computed separately here).
    reg [ROW_BITS-1:0] ref_row_q;
    reg [COL_BITS-1:0] ref_col_q;
    reg ref_active_q;
    reg [PIXEL_WIDTH-1:0] expected_pad_pixel;
    reg expected_pad_valid;
    reg expected_real_pixel;
    reg expected_last_pixel;

    wire ref_is_real_row = (ref_row_q >= PAD_BEFORE) && (ref_row_q < (IMAGE_HEIGHT + PAD_BEFORE));
    wire ref_is_real_col = (ref_col_q >= PAD_BEFORE) && (ref_col_q < (IMAGE_WIDTH + PAD_BEFORE));
    wire ref_is_real = ref_is_real_row && ref_is_real_col;
    wire ref_last_row = (ref_row_q == (PADDED_HEIGHT - 1));
    wire ref_last_col = (ref_col_q == (PADDED_WIDTH - 1));
    wire ref_advance = ref_active_q && en_i && (ref_is_real ? pixel_valid_i : 1'b1);
    wire ref_last_pixel = ref_advance && ref_is_real &&
                          (ref_row_q == (IMAGE_HEIGHT + PAD_BEFORE - 1)) &&
                          (ref_col_q == (IMAGE_WIDTH  + PAD_BEFORE - 1));

    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            ref_row_q <= 0;
            ref_col_q <= 0;
            ref_active_q <= 1'b0;
            expected_pad_pixel <= 0;
            expected_pad_valid <= 1'b0;
            expected_real_pixel <= 1'b0;
            expected_last_pixel <= 1'b0;
        end else begin
            // Counter update: start_i always wins and (re)arms the raster;
            // otherwise advance only while active, enabled, and (for a real
            // position) the host presents a valid pixel.
            if (start_i) begin
                ref_row_q <= 0;
                ref_col_q <= 0;
                ref_active_q <= 1'b1;
            end else if (ref_advance) begin
                if (ref_last_col) begin
                    ref_col_q <= 0;
                    if (ref_last_row) ref_active_q <= 1'b0;
                    else ref_row_q <= ref_row_q + 1'b1;
                end else begin
                    ref_col_q <= ref_col_q + 1'b1;
                end
            end

            // Registered outputs, one cycle behind the accepted position.
            expected_pad_valid <= ref_advance;
            expected_pad_pixel <= ref_is_real ? pixel_in_i : {PIXEL_WIDTH{1'b0}};
            expected_real_pixel <= ref_advance && ref_is_real;
            expected_last_pixel <= ref_last_pixel;
        end
    end

    // Expected flags: ready_o is combinational (a Moore function of the
    // reference state), unlike the other four registered outputs above.
    reg expected_ready;
    always @(*) begin : flags
        expected_ready = ref_active_q && en_i && ref_is_real;
    end

    // Checker
    // Compares every DUT output against the reference on negedge, after the
    // posedge capture has settled. Runs for the whole simulation so stalls,
    // pauses, and restarts are all validated cycle-by-cycle, not just by the
    // directed pulse-count checks in the test procedure.
    always @(negedge clk_i) begin : check
        if (rst_n_i) begin
            if (ready_o !== expected_ready) begin
                errors = errors + 1;
                $display("FAIL t=%0t: ready=%b expected=%b", $time, ready_o, expected_ready);
            end
            if (padded_pixel_valid_o !== expected_pad_valid) begin
                errors = errors + 1;
                $display("FAIL t=%0t: valid=%b expected=%b", $time, padded_pixel_valid_o,
                         expected_pad_valid);
            end
            if (real_pixel_o !== expected_real_pixel) begin
                errors = errors + 1;
                $display("FAIL t=%0t: real=%b expected=%b", $time, real_pixel_o,
                         expected_real_pixel);
            end
            if (last_pixel_o !== expected_last_pixel) begin
                errors = errors + 1;
                $display("FAIL t=%0t: last=%b expected=%b", $time, last_pixel_o,
                         expected_last_pixel);
            end
            if (padded_pixel_o !== expected_pad_pixel) begin
                errors = errors + 1;
                $display("FAIL t=%0t: pixel=%0d expected=%0d", $time, padded_pixel_o,
                         expected_pad_pixel);
            end
        end
    end

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        en_i = 0;
        start_i = 0;
        pixel_in_i = 0;
        pixel_valid_i = 0;
        rst_n_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;
        @(negedge clk_i);

        // Directed test 1: hold idle with no start request
        en_i = 1;
        repeat (5) @(negedge clk_i);
        if (ready_o !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: ready asserted before start (ready=%b)", $time, ready_o);
        end
        if (padded_pixel_valid_o !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: valid asserted before start (valid=%b)", $time,
                     padded_pixel_valid_o);
        end

        // Directed test 2: a full frame with continuous host valid (no
        // stalls). Every padded position must be produced exactly once,
        // every real position accepted exactly once, and last_pixel_o must
        // pulse exactly once at the final real position.
        pad_valid_count = 0;
        real_count = 0;
        ready_count = 0;
        last_count = 0;
        pixel_valid_i = 1;  // host always has data ready

        start_i = 1;
        repeat (TOTAL_PADDED + 4) begin
            @(negedge clk_i);
            start_i = 0;  // one-cycle start pulse
            pixel_in_i = pixel_in_i + 1'b1;  // free-running content
            if (ready_o) ready_count = ready_count + 1;
            if (padded_pixel_valid_o) pad_valid_count = pad_valid_count + 1;
            if (real_pixel_o) real_count = real_count + 1;
            if (last_pixel_o) last_count = last_count + 1;
        end

        if (pad_valid_count !== TOTAL_PADDED) begin
            errors = errors + 1;
            $display("FAIL t=%0t: padded pulses=%0d expected %0d", $time, pad_valid_count,
                     TOTAL_PADDED);
        end
        if (real_count !== TOTAL_REAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: real pulses=%0d expected %0d", $time, real_count, TOTAL_REAL);
        end
        if (ready_count !== TOTAL_REAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: ready pulses=%0d expected %0d", $time, ready_count, TOTAL_REAL);
        end
        if (last_count !== 1) begin
            errors = errors + 1;
            $display("FAIL t=%0t: last_pixel pulses=%0d expected 1", $time, last_count);
        end

        // Directed test 3: host stalls during the real-pixel region.
        // Deassert pixel_valid_i for 2 out of every 10 cycles across the
        // whole frame; a stall only holds the raster while positioned on a
        // real pixel (padding positions never sample pixel_valid_i).
        real_count = 0;
        last_count = 0;
        cycle_cnt = 0;

        start_i = 1;
        repeat (2 * TOTAL_PADDED) begin
            @(negedge clk_i);
            start_i = 0;
            pixel_valid_i = ((cycle_cnt % 10) < 2) ? 1'b0 : 1'b1;
            cycle_cnt = cycle_cnt + 1;
            pixel_in_i = pixel_in_i + 1'b1;
            if (real_pixel_o) real_count = real_count + 1;
            if (last_pixel_o) last_count = last_count + 1;
        end

        if (real_count !== TOTAL_REAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stalled real pulses=%0d expected %0d", $time, real_count,
                     TOTAL_REAL);
        end
        if (last_count !== 1) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stalled frame last pulses=%0d expected 1", $time, last_count);
        end
        pixel_valid_i = 1;

        // Directed test 4: system pause (en_i deasserted) spanning both the
        // padding and real regions. The raster must hold completely while
        // paused and resume exactly where it left off once en_i returns.
        real_count = 0;
        last_count = 0;
        cycle_cnt = 0;

        start_i = 1;
        repeat (2 * TOTAL_PADDED) begin
            @(negedge clk_i);
            start_i = 0;
            cycle_cnt = cycle_cnt + 1;
            en_i = ((cycle_cnt % 50) < 3) ? 1'b0 : 1'b1;  // pause 3 of every 50 cycles
            pixel_in_i = pixel_in_i + 1'b1;
            if (real_pixel_o) real_count = real_count + 1;
            if (last_pixel_o) last_count = last_count + 1;
        end

        if (real_count !== TOTAL_REAL) begin
            errors = errors + 1;
            $display("FAIL t=%0t: paused real pulses=%0d expected %0d", $time, real_count,
                     TOTAL_REAL);
        end
        if (last_count !== 1) begin
            errors = errors + 1;
            $display("FAIL t=%0t: paused frame last pulses=%0d expected 1", $time, last_count);
        end
        en_i = 1;

        // Directed test 5: mid-frame restart. Re-assert start_i partway
        // through a frame; the interrupted frame must be discarded and a
        // fresh one started cleanly (the continuous checker above validates
        // this cycle-by-cycle since the reference applies the same
        // override).
        last_count = 0;
        start_i = 1;
        @(negedge clk_i);
        start_i = 0;
        repeat (TOTAL_PADDED / 2) @(negedge clk_i);  // run halfway, then restart
        start_i = 1;
        @(negedge clk_i);
        start_i = 0;
        repeat (TOTAL_PADDED + 4) begin
            @(negedge clk_i);
            if (last_pixel_o) last_count = last_count + 1;
        end
        if (last_count !== 1) begin
            errors = errors + 1;
            $display("FAIL t=%0t: restarted frame last pulses=%0d expected 1", $time, last_count);
        end

        // Directed test 6: back-to-back frames complete cleanly with no
        // reset in between.
        for (i = 0; i < 2; i = i + 1) begin
            last_count = 0;
            start_i = 1;
            @(negedge clk_i);
            start_i = 0;
            repeat (TOTAL_PADDED + 4) begin
                @(negedge clk_i);
                if (last_pixel_o) last_count = last_count + 1;
            end
            if (last_count !== 1) begin
                errors = errors + 1;
                $display("FAIL t=%0t: back-to-back frame %0d last pulses=%0d expected 1", $time,
                         i, last_count);
            end
        end

        // Random stimulus
        // Stress-test with random enable/valid/start toggles and random
        // pixel content; the continuous reference checker validates every
        // cycle, including unexpected mid-frame restarts.
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(negedge clk_i);
            en_i = $urandom & 1;
            pixel_valid_i = $urandom & 1;
            start_i = ($urandom % 20) == 0;  // occasional frame restarts
            pixel_in_i = $urandom;
        end
        en_i = 1;
        start_i = 0;
        pixel_valid_i = 0;

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | en=%b start=%b | ready=%b valid=%b real=%b last=%b | pixel=%0d",
                 $time, en_i, start_i, ready_o, padded_pixel_valid_o, real_pixel_o, last_pixel_o,
                 padded_pixel_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_pixel_pad_inserter.vcd");
        $dumpvars(0, tb_pixel_pad_inserter);
    end

endmodule
