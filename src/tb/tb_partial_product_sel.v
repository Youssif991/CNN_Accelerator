`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/25/2026
// Design Name: Radix-4 Booth Partial Product Selector Testbench
// Module Name: tb_partial_product_sel
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the LUT-based partial product
//              selector. Golden reference computes the selected multiple
//              arithmetically; the checker compares it against the DUT's
//              case-table output after each stimulus settles.
//
// Dependencies: partial_product_sel (src/rtl/partial_product_sel.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_partial_product_sel;

    // Parameters
    localparam WIDTH = 9;

    // DUT interface
    reg     [WIDTH-1:0] x_ext_i;
    reg                 neg_i;
    reg                 is_one_i;
    reg                 is_two_i;
    wire    [WIDTH-1:0] partial_product_o;

    // Test infrastructure
    integer             i;
    integer             errors = 0;
    integer             mult;
    reg     [WIDTH-1:0] expected_partial_product_o;

    // Module instantiation
    partial_product_sel #(
        .WIDTH(WIDTH)
    ) dut (
        .x_ext_i          (x_ext_i),
        .neg_i            (neg_i),
        .is_one_i         (is_one_i),
        .is_two_i         (is_two_i),
        .partial_product_o(partial_product_o)
    );

    // Golden reference (combinational)
    always @(*) begin : reference
        mult = 0;
        if (is_one_i && !is_two_i) mult = 1;
        else if (!is_one_i && is_two_i) mult = 2;
        // else mult stays 0

        if (neg_i) mult = -mult;

        expected_partial_product_o = ($signed(x_ext_i) * mult) & ((1 << WIDTH) - 1);
    end

    // Checker
    always @(*) begin : check
        if (partial_product_o !== expected_partial_product_o) begin
            errors = errors + 1;
            $display("FAIL at time %0t: pp_o=%d expected=%d", $time, $signed(partial_product_o),
                     $signed(expected_partial_product_o));
        end
    end

    // Test procedure
    initial begin : test
        // Drive default inputs
        x_ext_i = 0;
        neg_i = 0;
        is_one_i = 0;
        is_two_i = 0;
        #1;  // allow initial values to settle

        // Directed cases
        // All zeros
        x_ext_i = 0;
        neg_i = 0;
        is_one_i = 0;
        is_two_i = 0;
        #1;

        // x = 1, all control combinations
        x_ext_i = 1;
        // 2'b00, neg=0
        neg_i = 0;
        is_one_i = 0;
        is_two_i = 0;
        #1;
        // 2'b00, neg=1
        neg_i = 1;
        is_one_i = 0;
        is_two_i = 0;
        #1;
        // 2'b01, neg=0
        neg_i = 0;
        is_one_i = 1;
        is_two_i = 0;
        #1;
        // 2'b01, neg=1
        neg_i = 1;
        is_one_i = 1;
        is_two_i = 0;
        #1;
        // 2'b10, neg=0
        neg_i = 0;
        is_one_i = 0;
        is_two_i = 1;
        #1;
        // 2'b10, neg=1
        neg_i = 1;
        is_one_i = 0;
        is_two_i = 1;
        #1;
        // 2'b11 (invalid), neg=0
        neg_i = 0;
        is_one_i = 1;
        is_two_i = 1;
        #1;
        // 2'b11, neg=1
        neg_i = 1;
        is_one_i = 1;
        is_two_i = 1;
        #1;

        // Maximum positive (2^(WIDTH-1) - 1)
        x_ext_i = (1 << (WIDTH - 1)) - 1;
        // +max
        neg_i = 0;
        is_one_i = 1;
        is_two_i = 0;
        #1;
        // -max
        neg_i = 1;
        is_one_i = 1;
        is_two_i = 0;
        #1;
        // +2*max
        neg_i = 0;
        is_one_i = 0;
        is_two_i = 1;
        #1;
        // -2*max
        neg_i = 1;
        is_one_i = 0;
        is_two_i = 1;
        #1;

        // Minimum negative (-2^(WIDTH-1))
        x_ext_i = -(1 << (WIDTH - 1));
        // +min
        neg_i = 0;
        is_one_i = 1;
        is_two_i = 0;
        #1;
        // -min (overflow)
        neg_i = 1;
        is_one_i = 1;
        is_two_i = 0;
        #1;
        // +2*min (overflow)
        neg_i = 0;
        is_one_i = 0;
        is_two_i = 1;
        #1;
        // -2*min
        neg_i = 1;
        is_one_i = 0;
        is_two_i = 1;
        #1;

        // Random stimulus
        for (i = 0; i < 100; i = i + 1) begin
            x_ext_i  = $urandom() % (1 << WIDTH);
            neg_i    = $urandom() % 2;
            is_one_i = $urandom() % 2;
            is_two_i = $urandom() % 2;
            #1;
        end

        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor
    initial begin : monitor
        $monitor("Time=%0t | x_ext_i=%d | pp_o=%d (0x%h) exp=%d (0x%h)", $time, x_ext_i,
                 partial_product_o, partial_product_o, expected_partial_product_o,
                 expected_partial_product_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_partial_product_sel.vcd");
        $dumpvars(0, tb_partial_product_sel);
    end

endmodule
