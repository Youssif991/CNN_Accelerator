`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Saturate/Round Unit
// Module Name: sat_round_unit
// Tool Versions: Vivado 2025.2
// Description: ReLU, fixed-point rescale, and saturation of the convolution
//              result to the OUT_WIDTH-bit signed output precision.
//
//              SUM_WIDTH exceeds OUT_WIDTH for two DISTINCT reasons that must
//              not be conflated:
//                1. INTEGER GUARD BITS: headroom (\$clog2(N*N) extra bits)
//                   so the adder tree can sum N*N full-precision products
//                   without overflow. These bits are handled entirely by
//                   adder_tree and require no rescale here.
//                2. FIXED-POINT FRACTIONAL BITS (FRAC_BITS): if the kernel
//                   coefficients are quantized fixed-point values (e.g. a
//                   normalized Q1.7 kernel where COEFF_WIDTH-bit integers
//                   represent real values in [-1,1)), then every product
//                   and the resulting sum are scaled up by 2^FRAC_BITS
//                   relative to the real-valued result. THIS unit is the
//                   only place in the datapath that rescales that back
//                   down, via a round-half-up right-shift by FRAC_BITS,
//                   before saturating to OUT_WIDTH.
//
//              FRAC_BITS = 0 (default) means "pure integer kernel, no
//              fixed-point scale" - the sum is saturated directly with no
//              shift, preserving prior behavior exactly.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Removed erroneous round/truncate-by-guard-bits logic;
//                  guard bits are integer headroom, not fixed-point
//                  fraction. Saturated the full-width sum directly.
// Revision 0.03 - Added FRAC_BITS parameter and a deliberate round-half-up
//                  rescale stage for genuine fixed-point kernels. This is
//                  NOT a reintroduction of the Rev 0.01 bug: Rev 0.01
//                  wrongly treated integer guard bits as fractional bits
//                  (shift amount = SUM_WIDTH-OUT_WIDTH, always on). Rev 0.03
//                  only shifts by the kernel's actual FRAC_BITS, which is
//                  independent of SUM_WIDTH/OUT_WIDTH, and defaults to 0
//                  (no shift) for integer-only kernels.
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module sat_round_unit #(
    parameter SUM_WIDTH    = 22,
    parameter OUT_WIDTH    = 16,
    parameter ROUND_ENABLE = 1,  // kept for port/parameter compatibility;
                                 // no-op - superseded by FRAC_BITS below
    parameter FRAC_BITS    = 0   // number of fractional bits in the
                                 // fixed-point kernel/product scale.
                                 // 0 = pure integer kernel (no rescale).
) (
    input  wire signed [SUM_WIDTH-1:0] sum_i,
    input  wire relu_en_i,  // ReLU enable: clamp negative sums to zero
    output wire signed [OUT_WIDTH-1:0] result_o
);

    // One extra bit of headroom so adding the round-half-up bias can never
    // overflow the ReLU-clamped sum, regardless of FRAC_BITS.
    localparam signed [SUM_WIDTH:0] SAT_MAX = (1 <<< (OUT_WIDTH-1)) - 1;  // +32767
    localparam signed [SUM_WIDTH:0] SAT_MIN = -(1 <<< (OUT_WIDTH-1));     // -32768

    // Round-half-up bias = 2^(FRAC_BITS-1). Zero when FRAC_BITS == 0, which
    // makes the rescale step below a true no-op for integer-only kernels.
    localparam signed [SUM_WIDTH:0] ROUND_BIAS =
        (FRAC_BITS > 0) ? (1 <<< (FRAC_BITS-1)) : 0;

    reg signed [SUM_WIDTH:0] sum_relu;    // ReLU-clamped sum, widened by 1 bit
    reg signed [SUM_WIDTH:0] sum_scaled;  // after fixed-point rescale
    reg signed [OUT_WIDTH-1:0] result_d;

    always @(*) begin : relu_rescale_sat
        // Optional ReLU: clamp negative sums to zero.
        if (relu_en_i && (sum_i < 0)) begin
            sum_relu = {(SUM_WIDTH+1){1'b0}};
        end else begin
            sum_relu = {sum_i[SUM_WIDTH-1], sum_i};  // sign-extend by 1 bit
        end

        // Fixed-point rescale: round-half-up then arithmetic right-shift by
        // FRAC_BITS. With FRAC_BITS == 0 this reduces to sum_scaled = sum_relu,
        // i.e. identical to the Rev 0.02 direct-saturate behavior.
        if (FRAC_BITS > 0) begin
            sum_scaled = (sum_relu + ROUND_BIAS) >>> FRAC_BITS;
        end else begin
            sum_scaled = sum_relu;
        end

        // Saturate the rescaled, full-precision sum to the signed
        // OUT_WIDTH range.
        if (sum_scaled > SAT_MAX) begin
            result_d = SAT_MAX[OUT_WIDTH-1:0];
        end else if (sum_scaled < SAT_MIN) begin
            result_d = SAT_MIN[OUT_WIDTH-1:0];
        end else begin
            result_d = sum_scaled[OUT_WIDTH-1:0];
        end
    end

    assign result_o = result_d;

endmodule