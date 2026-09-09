`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Saturate/Round Unit Testbench
// Module Name: tb_sat_round_unit
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the saturate/round unit with the
//              optional ReLU activation. Tests the fixed-point rescale path
//              (FRAC_BITS = 6): ReLU (clamp negatives to zero), round-half-up
//              shift by FRAC_BITS, then saturate to OUT_WIDTH. The golden
//              model mirrors sat_round_unit's own arithmetic exactly,
//              including its 1-bit headroom widening before the round bias
//              is added.
//
//              Note: as of sat_round_unit Rev 0.03, ROUND_ENABLE is a no-op
//              (rounding is controlled entirely by FRAC_BITS), so there is
//              no DUT configuration that performs "truncation without
//              rounding" at a nonzero FRAC_BITS. This testbench therefore
//              exercises a single DUT instance against the round-half-up
//              model only; the old dual round/trunc comparison from
//              Revision 0.01 no longer applies to the current RTL contract.
//
// Dependencies: sat_round_unit (src/datapath/sat_round_unit.v)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Removed the truncation-mode DUT instance and checker
//                  (ROUND_ENABLE no longer controls rounding behavior in
//                  sat_round_unit Rev 0.03). Added FRAC_BITS=6 to the DUT
//                  instantiation and rewrote the golden model to match
//                  sat_round_unit's rescale arithmetic exactly.
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_sat_round_unit;

    // Parameters
    localparam SUM_WIDTH = 22;
    localparam OUT_WIDTH = 16;
    localparam FRAC_BITS = 6;  // fractional bits in the fixed-point kernel/product scale
    localparam SAT_MAX = (1 << (OUT_WIDTH-1)) - 1;   // +32767
    localparam SAT_MIN = -(1 << (OUT_WIDTH-1));      // -32768
    localparam NUM_TESTS = 100;  // random stimulus vectors

    // DUT interconnect
    reg signed [SUM_WIDTH-1:0] sum_i;
    reg relu_en_i;
    wire signed [OUT_WIDTH-1:0] result_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer errors = 0;
    reg signed [SUM_WIDTH:0] expected_shifted;  // +1 bit: matches sat_round_unit's headroom bit
    reg signed [OUT_WIDTH-1:0] expected_result;

    // Module instantiation
    sat_round_unit #(
        .SUM_WIDTH   (SUM_WIDTH),
        .OUT_WIDTH   (OUT_WIDTH),
        .FRAC_BITS   (FRAC_BITS)
    ) dut (
        .sum_i    (sum_i),
        .relu_en_i(relu_en_i),
        .result_o (result_o)
    );

    // Golden reference: mirrors sat_round_unit's own computation.
    // ReLU-clamp, sign-extend by 1 bit (matches sum_relu's headroom bit),
    // then round-half-up + shift by FRAC_BITS (a true no-op when
    // FRAC_BITS == 0), then saturate.
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

    // Checker: compares the DUT 1 ns after each stimulus change.
    always @(*) begin : check
        #1;
        if (result_o !== expected_result) begin
            errors = errors + 1;
            $display("FAIL t=%0t: result dut=%0d expected=%0d", $time, result_o,
                     expected_result);
        end
    end

    // Test sequence
    initial begin : test
        // Drive all inputs low
        sum_i = 0;
        relu_en_i = 0;
        #10;

        // Directed test 1: exact multiples of 2^FRAC_BITS (no rounding)
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
        $monitor("Time=%0t | sum=%0d | result=%0d | expected=%0d", $time, sum_i, result_o,
                 expected_result);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_sat_round_unit.vcd");
        $dumpvars(0, tb_sat_round_unit);
    end

endmodule