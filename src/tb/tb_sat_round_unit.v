`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Saturate/Round Unit Testbench
// Module Name: tb_sat_round_unit
// Tool Versions: Vivado 2025.2
// Description: Self-checking clocked testbench for the pipelined saturate/round
//              unit with optional ReLU activation. Tests the fixed-point rescale
//              path (FRAC_BITS = 6): ReLU (clamp negatives to zero), round-half-up
//              shift by FRAC_BITS, then saturate to OUT_WIDTH. The golden model
//              mirrors sat_round_unit's own arithmetic exactly, including its
//              1-bit headroom widening before the round bias is added.
//
//              As of sat_round_unit Rev 0.04, the DUT is a two-stage pipeline:
//                - Stage 1 register captures sum_scaled (ReLU + round + shift)
//                - Stage 2 register captures the saturated result
//              Both share en_i as a pipeline freeze. The checker therefore
//              waits two clock edges after presenting stimulus before sampling,
//              and drives en_i for the freeze test.
//
//              Note: ROUND_ENABLE is a no-op (rounding controlled entirely by
//              FRAC_BITS), so this TB exercises a single DUT instance against
//              the round-half-up model only.
//
// Dependencies: sat_round_unit (src/datapath/sat_round_unit.v)
//
// Revision:
// Revision 0.01 - File Created.
// Revision 0.02 - Removed the truncation-mode DUT instance and checker.
// Revision 0.03 - Added FRAC_BITS=6 and rewrote golden model to match RTL.
// Revision 0.04 - Converted to clocked TB for the two-stage pipelined DUT:
//                  added clk_i/rst_n_i/en_i, two-cycle latency, pipeline
//                  freeze test, and reset test.
// Revision 0.05 - Scaled the freeze-test stimulus by 2^FRAC_BITS so the
//                  expected value is the exact pass-through, not the rounded
//                  quotient (the old stimulus expected 100 but the rescale
//                  legitimately produces 2).
//////////////////////////////////////////////////////////////////////////////////

module tb_sat_round_unit;

    // Parameters
    localparam SUM_WIDTH = 22;
    localparam OUT_WIDTH = 16;
    localparam FRAC_BITS = 6;  // fractional bits in the fixed-point kernel/product scale
    localparam SAT_MAX = (1 << (OUT_WIDTH-1)) - 1;   // +32767
    localparam SAT_MIN = -(1 << (OUT_WIDTH-1));      // -32768
    localparam NUM_TESTS = 100;  // random stimulus vectors
    localparam LATENCY   = 2;    // pipeline depth of the DUT

    // DUT interconnect
    reg                        clk_i;
    reg                        rst_n_i;
    reg                        en_i;
    reg  signed [SUM_WIDTH-1:0] sum_i;
    reg                        relu_en_i;
    wire signed [OUT_WIDTH-1:0] result_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer errors = 0;

    // Reference values for the current stimulus (combinational, no pipeline)
    reg signed [SUM_WIDTH:0]   expected_shifted;
    reg signed [OUT_WIDTH-1:0] expected_result;

    // Module instantiation
    sat_round_unit #(
        .SUM_WIDTH   (SUM_WIDTH),
        .OUT_WIDTH   (OUT_WIDTH),
        .FRAC_BITS   (FRAC_BITS)
    ) dut (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .en_i      (en_i),
        .sum_i     (sum_i),
        .relu_en_i (relu_en_i),
        .result_o  (result_o)
    );

    // ----------------------------------------------------------------
    // Clock: 10 ns period (100 MHz)
    // ----------------------------------------------------------------
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;
    end

    // ----------------------------------------------------------------
    // Golden reference: mirrors sat_round_unit's own computation.
    // ReLU-clamp, sign-extend by 1 bit (matches sum_relu's headroom bit),
    // then round-half-up + shift by FRAC_BITS (a true no-op when
    // FRAC_BITS == 0), then saturate.
    // ----------------------------------------------------------------
    reg signed [SUM_WIDTH-1:0] ref_sum;
    always @(*) begin : reference
        ref_sum = (relu_en_i && (sum_i < 0)) ? 0 : sum_i;

        if (FRAC_BITS > 0) begin
            expected_shifted = ($signed({ref_sum[SUM_WIDTH-1], ref_sum}) +
                                (1 <<< (FRAC_BITS - 1))) >>> FRAC_BITS;
        end else begin
            expected_shifted = $signed({ref_sum[SUM_WIDTH-1], ref_sum});
        end

        if (expected_shifted > SAT_MAX) begin
            expected_result = SAT_MAX;
        end else if (expected_shifted < SAT_MIN) begin
            expected_result = SAT_MIN;
        end else begin
            expected_result = $signed(expected_shifted[OUT_WIDTH-1:0]);
        end
    end

    // ----------------------------------------------------------------
    // Checker task: present stimulus, wait LATENCY cycles, compare.
    // Called from the test sequence so the golden model is sampled at
    // the same instant the stimulus is applied.
    // ----------------------------------------------------------------
    task automatic check;
        input signed [SUM_WIDTH-1:0] stim_sum;
        input                        stim_relu;
        integer                      k;
        begin
            @(negedge clk_i);
            sum_i     = stim_sum;
            relu_en_i = stim_relu;
            en_i      = 1;

            // Golden model combinational, so it settles immediately.
            // Capture it now, before the pipeline advances.
            #1;
            begin : capture
                reg signed [OUT_WIDTH-1:0] exp;
                exp = expected_result;
                for (k = 0; k < LATENCY; k = k + 1)
                    @(posedge clk_i);
                #1;
                if (result_o !== exp) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: sum=%0d relu=%b dut=%0d expected=%0d",
                             $time, stim_sum, stim_relu, result_o, exp);
                end
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test sequence
    // ----------------------------------------------------------------
    initial begin : test
        // Reset
        rst_n_i   = 0;
        en_i      = 1;
        sum_i     = 0;
        relu_en_i = 0;
        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_n_i = 1;

        // Directed test 1: exact multiples of 2^FRAC_BITS (no rounding)
        check( 22'sd64,              0);
        check(-22'sd64,              0);
        check( 22'sd32767 << 6,      0);
        check((-22'sd32768) << 6,    0);

        // Directed test 2: rounding boundaries (half-ULP = 32)
        check( 22'sd31,              0);  // 31/64 -> 0
        check( 22'sd32,              0);  // tie -> 1 (round half up)
        check( 22'sd63,              0);  // 63/64 -> 1
        check(-22'sd32,              0);  // tie -> 0
        check(-22'sd33,              0);  // -33/64 -> -1
        check(-22'sd63,              0);  // -63/64 -> -1

        // Directed test 3: saturation boundaries
        check((22'sd32767 << 6) + 1,    0);  // +32767.015 -> saturate +32767
        check(((-22'sd32768) << 6) - 1, 0);  // -32768.015 -> saturate -32768
        check( 22'sd2097151,            0);  // max 22-bit positive -> +32767
        check(-(1 << 21),               0);  // min 22-bit negative -> -32768

        // Directed test 4: ReLU clamps every negative sum to zero
        check(-22'sd1,          1);
        check(-22'sd33,         1);
        check(-22'sd32768 << 6, 1);
        check(-22'sd63,         1);
        check( 22'sd100,        1);
        check((22'sd32767 << 6) + 1, 1);

        // Random stimulus: stress-test with random 22-bit sums; toggle ReLU
        for (i = 0; i < NUM_TESTS; i = i + 1)
            check($urandom(), (i % 4) < 2);

        // ------------------------------------------------------------
        // Pipeline freeze test (en_i = 0)
        // ------------------------------------------------------------
        // 100 << FRAC_BITS rescales back to exactly 100, so the freeze test
        // observes the pass-through value rather than the rounded one.
        @(negedge clk_i);
        sum_i     = 22'sd100 << 6;
        relu_en_i = 1;
        en_i      = 1;
        repeat (LATENCY) @(posedge clk_i);
        #1;
        if (result_o !== 16'sd100) begin
            errors = errors + 1;
            $display("FAIL freeze setup: expected 100, got %0d", result_o);
        end else begin
            $display("OK: freeze setup -> 100");
        end

        @(negedge clk_i);
        en_i      = 0;
        sum_i     = -(22'sd200 << 6);  // would be 0 under ReLU
        relu_en_i = 1;
        repeat (LATENCY + 2) @(posedge clk_i);
        #1;
        if (result_o !== 16'sd100) begin
            errors = errors + 1;
            $display("FAIL en_i freeze: expected 100, got %0d", result_o);
        end else begin
            $display("OK: en_i freeze held result at 100");
        end

        @(negedge clk_i);
        en_i = 1;
        repeat (LATENCY) @(posedge clk_i);
        #1;
        if (result_o !== 16'sd0) begin
            errors = errors + 1;
            $display("FAIL en_i release: expected 0, got %0d", result_o);
        end else begin
            $display("OK: en_i release updated result to 0");
        end

        // ------------------------------------------------------------
        // Reset test
        // ------------------------------------------------------------
        @(negedge clk_i);
        rst_n_i = 0;
        #1;
        if (result_o !== 16'sd0) begin
            errors = errors + 1;
            $display("FAIL reset: expected 0, got %0d", result_o);
        end else begin
            $display("OK: reset cleared result");
        end
        @(posedge clk_i);
        rst_n_i = 1;

        // Report
        #20;
        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else             $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_sat_round_unit.vcd");
        $dumpvars(0, tb_sat_round_unit);
    end

endmodule