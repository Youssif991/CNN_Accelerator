`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/25/2026
// Design Name: Radix-4 Booth Final Adder
// Module Name: tb_final_adder
// Tool Versions: Vivado 2025.2
// Description: Testbench for the Radix-4 Booth final adder module.
//
// Dependencies: final_adder (src/rtl/final_adder.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_final_adder;

    // Parameters
    localparam WIDTH = 18;
    localparam NUM_TESTS = 100;

    // DUT interconnect
    reg [WIDTH-1:0] sum_i;
    reg [WIDTH-1:0] carry_i;
    wire [WIDTH-1:0] product_o;

    // Test infrastructure
    integer i;
    integer errors = 0;
    reg [WIDTH-1:0] expected_product_o;

    // Module instantiation
    final_adder #(
        .WIDTH(WIDTH)
    ) dut (
        .sum_i(sum_i),
        .carry_i(carry_i),
        .product_o(product_o)
    );

  // Test sequence
    initial begin : test
        sum_i   = 0;
        carry_i = 0;

        $display("   sum_i carry_i | product_o | Expected");
        $display("   ----------- | --------- | --------");

        for (i = 0; i < 8; i = i + 1) begin
            {sum_i, carry_i} = i;
            #10;

            // Golden reference
            expected_product_o = sum_i + carry_i;

            // Checker — compare DUT against reference
            if (product_o !== expected_product_o) begin
                errors = errors + 1;
                $display(
                    "FAIL at time %0t: sum_i=%b carry_i=%b | dut=%b expected=%b",
                    $time, sum_i, carry_i, product_o, expected_product_o);
            end else begin
                $display("  %b %b | %b    %b ", sum_i, carry_i, product_o, expected_product_o);
            end
        end

        // --- Random stimulus ---
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            sum_i   = $urandom() % (1 << WIDTH);
            carry_i = $urandom() % (1 << WIDTH);
            #10;

            // Golden reference
            expected_product_o = sum_i + carry_i;

            // Checker — compare DUT against reference
            if (product_o !== expected_product_o) begin
                errors = errors + 1;
                $display(
                    "FAIL at time %0t: sum_i=%h carry_i=%h | dut product_o=%h expected=%h",
                    $time, sum_i, carry_i, product_o, expected_product_o);
            end
        end

        #10;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor
    initial begin : monitor
        $monitor("Time=%0t | sum_i=%d | carry_i=%d | product_o=%d (0x%h) exp=%d (0x%h)", $time,
                 sum_i, carry_i,
                 product_o, product_o,
                 expected_product_o, expected_product_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_final_adder.vcd");
        $dumpvars(0, tb_final_adder);
    end

endmodule
