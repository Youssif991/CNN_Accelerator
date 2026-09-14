`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/13/2026
// Design Name: CNN Convolution Datapath - Saturate/Round Unit
// Module Name: sat_round_unit
// Tool Versions: Vivado 2025.2
// Description: Pipelined ReLU, fixed-point rescale, and saturation to the
//              OUT_WIDTH-bit signed output precision.
//
//              Stage 1 (registered): ReLU clamp, sign-extend by 1 bit, add
//              the round-half-up bias, and arithmetic right-shift by
//              FRAC_BITS. Output register width is SUM_WIDTH+1 (one
//              headroom bit so the bias add can never overflow the
//              ReLU-clamped sum).
//
//              Stage 2 (registered): saturate the rescaled sum to the
//              signed OUT_WIDTH range.
//
//              FRAC_BITS = 0 makes the rescale step a no-op; the shifted
//              register then just carries the sign-extended sum.
//
//              en_i is the pipeline freeze. When low, both registers hold.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created.
//   0.02 - Removed erroneous guard-bit round logic.
//   0.03 - Added FRAC_BITS parameter and round-half-up rescale.
//   0.04 - Split into two registered stages; added clk/rst/en.
//////////////////////////////////////////////////////////////////////////////////

module sat_round_unit #(
    parameter SUM_WIDTH    = 22,
    parameter OUT_WIDTH    = 16,
    parameter ROUND_ENABLE = 1,
    parameter FRAC_BITS    = 0
) (
    input  wire                        clk_i,
    input  wire                        rst_n_i,
    input  wire                        en_i,
    input  wire signed [SUM_WIDTH-1:0] sum_i,
    input  wire                        relu_en_i,
    output wire signed [OUT_WIDTH-1:0] result_o
);

    localparam signed [SUM_WIDTH:0] SAT_MAX = (1 <<< (OUT_WIDTH-1)) - 1;  // +32767
    localparam signed [SUM_WIDTH:0] SAT_MIN = -(1 <<< (OUT_WIDTH-1));     // -32768

    localparam signed [SUM_WIDTH:0] ROUND_BIAS =
        (FRAC_BITS > 0) ? (1 <<< (FRAC_BITS-1)) : 0;

    // Stage 1 (combinational)
    reg signed [SUM_WIDTH:0] sum_relu;
    reg signed [SUM_WIDTH:0] sum_scaled;

    always @(*) begin : stage1_comb
        // ReLU clamp
        if (relu_en_i && (sum_i < 0))
            sum_relu = {(SUM_WIDTH+1){1'b0}};
        else
            sum_relu = {sum_i[SUM_WIDTH-1], sum_i};

        // Round-half-up + arithmetic right shift
        if (FRAC_BITS > 0)
            sum_scaled = (sum_relu + ROUND_BIAS) >>> FRAC_BITS;
        else
            sum_scaled = sum_relu;
    end

    // Stage 1 (registered)
    reg signed [SUM_WIDTH:0] sum_scaled_q;
    always @(posedge clk_i or negedge rst_n_i) begin : stage1_reg
        if (!rst_n_i)                    sum_scaled_q <= 0;
        else if (en_i)                   sum_scaled_q <= sum_scaled;
    end

    // Stage 2 (combinational): saturate
    reg signed [OUT_WIDTH-1:0] result_d;
    always @(*) begin : stage2_comb
        if (sum_scaled_q > SAT_MAX)
            result_d = SAT_MAX[OUT_WIDTH-1:0];
        else if (sum_scaled_q < SAT_MIN)
            result_d = SAT_MIN[OUT_WIDTH-1:0];
        else
            result_d = sum_scaled_q[OUT_WIDTH-1:0];
    end

    // Stage 2 (registered)
    reg signed [OUT_WIDTH-1:0] result_q;
    always @(posedge clk_i or negedge rst_n_i) begin : stage2_reg
        if (!rst_n_i)                    result_q <= 0;
        else if (en_i)                   result_q <= result_d;
    end

    assign result_o = result_q;

endmodule