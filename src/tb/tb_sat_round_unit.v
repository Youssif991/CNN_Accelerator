`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Saturate/Round Unit Testbench
// Module Name: tb_sat_round_unit
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the saturate/round unit with the
//              optional ReLU activation. A golden reference models ReLU
//              (clamp negatives to zero), round-half-up truncation, and
//              clamping with integer arithmetic (arithmetic shift vs the
//              DUT's part-select and pre-truncation bounds); the checker
//              compares both the rounding and the plain-truncation instances
//              after a #1 settle. Exercises both relu_en_i settings.
//
// Dependencies: sat_round_unit (src/datapath/sat_round_unit.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_sat_round_unit;

    // Parameters
    localparam SUM_WIDTH = 22;
    localparam OUT_WIDTH = 16;
    localparam BITS_DROPPED = SUM_WIDTH - OUT_WIDTH;
    localparam SAT_MAX = (1 << (OUT_WIDTH-1)) - 1;   // +32767
    localparam SAT_MIN = -(1 << (OUT_WIDTH-1));      // -32768
    localparam NUM_TESTS = 100;  // random stimulus vectors

    // DUT interconnect
    reg signed [SUM_WIDTH-1:0] sum_i;
    reg relu_en_i;
    wire signed [OUT_WIDTH-1:0] result_o;        // rounding enabled
    wire signed [OUT_WIDTH-1:0] result_o_trunc;  // plain truncation

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer errors = 0;
    reg signed [SUM_WIDTH-1:0] expected_shifted;       // rounded, pre-clamp
    reg signed [SUM_WIDTH-1:0] expected_shifted_trunc; // truncated, pre-clamp
    reg signed [OUT_WIDTH-1:0] expected_result;
    reg signed [OUT_WIDTH-1:0] expected_result_trunc;

    // Module instantiation (both rounding modes in one run)
    sat_round_unit #(
        .SUM_WIDTH(SUM_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .ROUND_ENABLE(1)
    ) dut (
        .sum_i(sum_i),
        .relu_en_i(relu_en_i),
        .result_o(result_o)
    );

    sat_round_unit #(
        .SUM_WIDTH(SUM_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .ROUND_ENABLE(0)
    ) dut_trunc (
        .sum_i(sum_i),
        .relu_en_i(relu_en_i),
        .result_o(result_o_trunc)
    );

    // Golden reference (rounding mode)
    // Independent integer model: optional ReLU (clamp negatives to zero), add
    // half the dropped LSBs, arithmetic-shift (floor for negatives - same as
    // the DUT's part-select), then clamp.
    reg signed [SUM_WIDTH-1:0] ref_sum;
    always @(*) begin : reference
        ref_sum = (relu_en_i && (sum_i < 0)) ? 0 : sum_i;
        // Round: add half the dropped LSBs into the signed accumulator, then
        // arithmetic-shift (floor for negatives - same as the DUT's
        // part-select), then clamp.
        expected_shifted = ref_sum + (1 << (BITS_DROPPED-1));
        expected_shifted = expected_shifted >>> BITS_DROPPED;
        if (expected_shifted > SAT_MAX) begin
            expected_result = SAT_MAX;
        end else if (expected_shifted < SAT_MIN) begin
            expected_result = SAT_MIN;
        end else begin
            expected_result = $signed(expected_shifted[OUT_WIDTH-1:0]);
        end
    end

    // Golden reference (truncation mode): optional ReLU, then no rounding bias.
    always @(*) begin : reference_trunc
        ref_sum = (relu_en_i && (sum_i < 0)) ? 0 : sum_i;
        expected_shifted_trunc = ref_sum >>> BITS_DROPPED;
        if (expected_shifted_trunc > SAT_MAX) begin
            expected_result_trunc = SAT_MAX;
        end else if (expected_shifted_trunc < SAT_MIN) begin
            expected_result_trunc = SAT_MIN;
        end else begin
            expected_result_trunc = $signed(expected_shifted_trunc[OUT_WIDTH-1:0]);
        end
    end

    // Checker
    // Compares both instances 1 ns after each stimulus change.
    always @(*) begin : check
        #1;
        if (result_o !== expected_result) begin
            errors = errors + 1;
            $display("FAIL t=%0t: round dut=%0d expected=%0d", $time, result_o,
                     expected_result);
        end
        if (result_o_trunc !== expected_result_trunc) begin
            errors = errors + 1;
            $display("FAIL t=%0t: trunc dut=%0d expected=%0d", $time, result_o_trunc,
                     expected_result_trunc);
        end
    end

    // Test sequence
    initial begin : test
        // Drive all inputs low
        sum_i = 0;
        relu_en_i = 0;
        #10;

        // Directed test 1: exact multiples of 2^BITS_DROPPED (no rounding)
        sum_i = 22'sd64;
        #10;
        sum_i = -22'sd64;
        #10;
        sum_i = 22'sd32767 << 6;
        #10;
        sum_i = (-22'sd32768) << 6;
        #10;

        // Directed test 2: rounding boundaries (half-ULP = 32)
        sum_i = 22'sd31;   // 31/64 -> 0
        #10;
        sum_i = 22'sd32;   // tie -> 1 (round half up)
        #10;
        sum_i = 22'sd63;   // 63/64 -> 1
        #10;
        sum_i = -22'sd32;  // tie -> 0
        #10;
        sum_i = -22'sd33;  // -33/64 -> -1
        #10;
        sum_i = -22'sd63;  // -63/64 -> -1
        #10;

        // Directed test 3: saturation boundaries
        sum_i = (22'sd32767 << 6) + 1;   // +32767.015 -> saturate +32767
        #10;
        sum_i = ((-22'sd32768) << 6) - 1;  // -32768.015 -> saturate -32768
        #10;
        sum_i = 22'sd2097151;  // max 22-bit positive -> +32767
        #10;
        sum_i = -(1 << 21);  // min 22-bit negative -> -32768
        #10;

        // Directed test 4: ReLU clamps every negative sum to zero
        relu_en_i = 1;
        sum_i = -22'sd1;  // would be -0.xx -> 0
        #10;
        sum_i = -22'sd33;  // would round to -1 -> 0
        #10;
        sum_i = -22'sd32768 << 6;  // min 22-bit -> 0
        #10;
        sum_i = -22'sd63;  // -> 0
        #10;
        // Positives are unchanged by ReLU
        sum_i = 22'sd100;
        #10;
        sum_i = (22'sd32767 << 6) + 1;  // still saturates to +32767
        #10;
        relu_en_i = 0;

        // Random stimulus
        // Stress-test with random 22-bit sums (full signed range); toggle
        // ReLU every few vectors.
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            sum_i = $urandom();
            relu_en_i = (i % 4) < 2;
            #10;
        end
        relu_en_i = 0;

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | sum=%0d | round=%0d trunc=%0d | exp_r=%0d exp_t=%0d", $time, sum_i,
                 result_o, result_o_trunc, expected_result, expected_result_trunc);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_sat_round_unit.vcd");
        $dumpvars(0, tb_sat_round_unit);
    end

endmodule
