`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: Radix-4 Booth Partial Product Compressor Testbench
// Module Name: tb_partial_product_compressor
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the partial-product compressor.
//              The compressor reduces 5 partial-product rows to a (sum, carry)
//              row pair such that sum_o + carry_o == row0 + ... + row4 modulo
//              2^WIDTH (the carry out of the top column is dropped, matching
//              what the downstream final_adder consumes). The golden reference
//              computes the 5-row sum directly in WIDTH-bit arithmetic; the
//              checker compares sum_o + carry_o against it after each stimulus.
//
// Dependencies: partial_product_compressor (src/rtl/partial_product_compressor.v)
//               carry_save_adder          (src/rtl/carry_save_adder.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_partial_product_compressor;

    // Parameters
    localparam WIDTH = 18;
    localparam NUM_TESTS = 100;
    localparam SINGLE_ROW_VAL = 18'h1_2345;  // mid-range alternating pattern
    localparam [WIDTH-1:0] MAX_ROW = {WIDTH{1'b1}};

    // DUT interface
    reg [WIDTH-1:0] row0_i = 0;
    reg [WIDTH-1:0] row1_i = 0;
    reg [WIDTH-1:0] row2_i = 0;
    reg [WIDTH-1:0] row3_i = 0;
    reg [WIDTH-1:0] row4_i = 0;
    wire [WIDTH-1:0] sum_o;
    wire [WIDTH-1:0] carry_o;
    // Derived signal: what the downstream final_adder would compute.
    wire [WIDTH-1:0] sum_plus_carry = sum_o + carry_o;

    // Test infrastructure
    integer i;
    integer errors = 0;
    reg [WIDTH-1:0] expected_total = 0;

    // Module instantiation
    partial_product_compressor #(
        .WIDTH(WIDTH)
    ) dut (
        .row0_i (row0_i),
        .row1_i (row1_i),
        .row2_i (row2_i),
        .row3_i (row3_i),
        .row4_i (row4_i),
        .sum_o  (sum_o),
        .carry_o(carry_o)
    );

    // Golden reference
    always @(*) begin : reference
        expected_total = row0_i + row1_i + row2_i + row3_i + row4_i;
    end

    // Checker
    always @(*) begin : check
        #1;
        if (sum_plus_carry !== expected_total) begin
            errors = errors + 1;
            $display("FAIL at time %0t: rows=%h %h %h %h %h | sum+carry=%0d expected=%0d", $time,
                     row0_i, row1_i, row2_i, row3_i, row4_i, sum_plus_carry, expected_total);
        end
    end

    // Test procedure
    initial begin : test
        // Drive all inputs low
        row0_i = 0;
        row1_i = 0;
        row2_i = 0;
        row3_i = 0;
        row4_i = 0;
        #10;

        // Directed case 1: all zeros
        row0_i = 0;
        row1_i = 0;
        row2_i = 0;
        row3_i = 0;
        row4_i = 0;
        #10;

        // Directed case 2: all rows at maximum
        row0_i = MAX_ROW;
        row1_i = MAX_ROW;
        row2_i = MAX_ROW;
        row3_i = MAX_ROW;
        row4_i = MAX_ROW;
        #10;

        // Directed case 3: single nonzero row, mid-range value
        for (i = 0; i < 5; i = i + 1) begin
            row0_i = 0;
            row1_i = 0;
            row2_i = 0;
            row3_i = 0;
            row4_i = 0;
            case (i)
                0:       row0_i = SINGLE_ROW_VAL;
                1:       row1_i = SINGLE_ROW_VAL;
                2:       row2_i = SINGLE_ROW_VAL;
                3:       row3_i = SINGLE_ROW_VAL;
                default: row4_i = SINGLE_ROW_VAL;
            endcase
            #10;
        end

        // Directed case 4: single nonzero row, maximum value
        for (i = 0; i < 5; i = i + 1) begin
            row0_i = 0;
            row1_i = 0;
            row2_i = 0;
            row3_i = 0;
            row4_i = 0;
            case (i)
                0:       row0_i = MAX_ROW;
                1:       row1_i = MAX_ROW;
                2:       row2_i = MAX_ROW;
                3:       row3_i = MAX_ROW;
                default: row4_i = MAX_ROW;
            endcase
            #10;
        end

        // Directed case 5: small progressive numbers
        row0_i = 3;
        row1_i = 7;
        row2_i = 15;
        row3_i = 31;
        row4_i = 63;
        #10;

        // Directed case 6: alternating bit patterns
        row0_i = 18'h0_AAAA;
        row1_i = 18'h1_5555;
        row2_i = 18'h2_AAAA;
        row3_i = 18'h1_5555;
        row4_i = 18'h0_AAAA;
        #10;

        // Directed case 7: isolated single-bit rows
        row0_i = 18'd1;
        row1_i = 18'd2;
        row2_i = 18'd4;
        row3_i = 18'd8;
        row4_i = 18'd16;
        #10;

        // Directed case 8: boundary combinations near maximum
        row0_i = MAX_ROW;
        row1_i = MAX_ROW;
        row2_i = 0;
        row3_i = 0;
        row4_i = 0;
        #10;
        row0_i = 0;
        row1_i = 0;
        row2_i = MAX_ROW;
        row3_i = MAX_ROW;
        row4_i = 0;
        #10;
        row0_i = MAX_ROW;
        row1_i = 0;
        row2_i = MAX_ROW;
        row3_i = 0;
        row4_i = MAX_ROW;
        #10;
        row0_i = 1;
        row1_i = MAX_ROW;
        row2_i = MAX_ROW;
        row3_i = MAX_ROW;
        row4_i = MAX_ROW;
        #10;

        // Directed case 9: deterministic mixed values
        row0_i = 123;
        row1_i = 456;
        row2_i = 789;
        row3_i = 1024;
        row4_i = 2048;
        #10;

        // Random stimulus
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            row0_i = $urandom() % (1 << WIDTH);
            row1_i = $urandom() % (1 << WIDTH);
            row2_i = $urandom() % (1 << WIDTH);
            row3_i = $urandom() % (1 << WIDTH);
            row4_i = $urandom() % (1 << WIDTH);
            #10;
        end

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor
    initial begin : monitor
        $monitor("Time=%0t | rows=%h %h %h %h %h | sum_o=%d carry_o=%d | sum+carry=%d expected=%d",
                 $time, row0_i, row1_i, row2_i, row3_i, row4_i, sum_o, carry_o, sum_plus_carry,
                 expected_total);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_partial_product_compressor.vcd");
        $dumpvars(0, tb_partial_product_compressor);
    end

endmodule
