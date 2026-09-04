`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Saturate/Round Unit
// Module Name: sat_round_unit
// Tool Versions: Vivado 2025.2
// Description: Saturation, rounding, truncation, and the optional ReLU
//              activation of the convolution result to the >=16-bit signed
//              output precision. ReLU (relu_en_i) clamps negative sums to
//              zero before rounding; rounding is round-half-up (add half the
//              dropped LSBs, then truncate); overflow and underflow clamp to
//              the signed output range.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module sat_round_unit #(
    parameter SUM_WIDTH = 22,
    parameter OUT_WIDTH = 16,
    parameter ROUND_ENABLE = 1  // 1 = round-half-up, 0 = plain truncation
) (
    input  wire signed [SUM_WIDTH-1:0] sum_i,
    input  wire relu_en_i,  // ReLU enable: clamp negative sums to zero
    output wire signed [OUT_WIDTH-1:0] result_o
);

    localparam BITS_DROPPED = SUM_WIDTH - OUT_WIDTH;
    localparam ROUND_BIAS   = 1 << (BITS_DROPPED - 1);   // half of the dropped LSBs
    localparam SAT_MAX      = (1 << (OUT_WIDTH-1)) - 1;  // +32767
    localparam SAT_MIN      = -(1 << (OUT_WIDTH-1));     // -32768
    localparam SAT_MAX_EXT  = SAT_MAX << BITS_DROPPED;   // pre-truncation bound
    localparam SAT_MIN_EXT  = SAT_MIN << BITS_DROPPED;   // pre-truncation bound

    reg signed [SUM_WIDTH-1:0] sum_relu;  // ReLU-clamped sum
    reg signed [SUM_WIDTH-1:0] rounded;    // biased sum (pre-truncation)
    reg signed [OUT_WIDTH-1:0] truncated;  // top OUT_WIDTH bits of the rounded sum
    reg signed [OUT_WIDTH-1:0] result_d;

    always @(*) begin : relu_round_sat
        // Optional ReLU: clamp negative sums to zero before rounding. For a
        // quantized output this is equivalent to max(sum, 0) on the result,
        // since a negative sum can never round above zero.
        if (relu_en_i && (sum_i < 0)) begin
            sum_relu = {SUM_WIDTH{1'b0}};
        end else begin
            sum_relu = sum_i;
        end
        // Round: add half of the dropped LSBs (round-half-up) unless disabled.
        rounded = sum_relu + (ROUND_ENABLE ? ROUND_BIAS : 0);
        // Truncate: keep the top OUT_WIDTH bits (arithmetic for two's
        // complement - rounds toward minus infinity on the dropped bits).
        truncated = rounded[SUM_WIDTH-1 -: OUT_WIDTH];
        // Saturate on the pre-truncation value: the dropped bits are the
        // range check, so clamping must happen before the truncation wraps.
        if (rounded > SAT_MAX_EXT) begin
            result_d = SAT_MAX;
        end else if (rounded < SAT_MIN_EXT) begin
            result_d = SAT_MIN;
        end else begin
            result_d = truncated;
        end
    end

    assign result_o = result_d;

endmodule
