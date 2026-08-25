`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/25/2026
// Design Name: Booth encoder testbench
// Module Name: tb_encoder
// Tool Versions: Vivado 2025.2
// Description: Exhaustive testbench for encoder. Golden reference computes
//              the Booth digit arithmetically and checks against the DUT's
//              case-table output after each stimulus settles.
//
// Dependencies: encoder (encoder.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module tb_encoder;
    // DUT interconnect
    reg [2:0] data_i;
    wire neg_o;
    wire is_two_o;
    wire is_one_o;
    // Test infrastructure
    integer i;
    integer errors = 0;
    reg expect_neg;
    reg expect_is_two;
    reg expect_is_one;
    reg signed [2:0] digit;
    // DUT instantiation
    encoder dut (
        .data_i(data_i),
        .neg_o(neg_o),
        .is_two_o(is_two_o),
        .is_one_o(is_one_o)
    );
    // Golden Reference
    always @(*) begin
        digit         = -2 * data_i[2] + data_i[1] + data_i[0];
        expect_neg    = (digit < 0);
        expect_is_two = (digit == 2) || (digit == -2);
        expect_is_one = (digit == 1) || (digit == -1);
    end

    // Stimulus + Checker.
    initial begin
        for (i = 0; i < 8; i = i + 1) begin
            data_i = i[2:0];
            #1;
            if (neg_o !== expect_neg) begin
                errors = errors + 1;
                $display("FAIL at time %0t: data_i=%b neg_o=%b expected=%b", $time, data_i, neg_o,
                         expect_neg);
            end
            if (is_two_o !== expect_is_two) begin
                errors = errors + 1;
                $display("FAIL at time %0t: data_i=%b is_two_o=%b expected=%b", $time, data_i,
                         is_two_o, expect_is_two);
            end
            if (is_one_o !== expect_is_one) begin
                errors = errors + 1;
                $display("FAIL at time %0t: data_i=%b is_one_o=%b expected=%b", $time, data_i,
                         is_one_o, expect_is_one);
            end
        end
        if (errors == 0) $display("TEST PASSED");
        else $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor(
            "Time=%0t | data_i=%b | dut_neg=%b dut_is_two=%b dut_is_one=%b | expected_neg=%b expected_is_two=%b expected_is_one=%b",
            $time, data_i, neg_o, is_two_o, is_one_o, expect_neg, expect_is_two, expect_is_one);
    end
    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_encoder.vcd");
        $dumpvars(0, tb_encoder);
    end

endmodule
