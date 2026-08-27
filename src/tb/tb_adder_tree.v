`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Adder Tree Testbench
// Module Name: tb_adder_tree
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the adder tree. A golden
//              reference sums all products arithmetically (signed) and the
//              checker compares sum_o after a #1 settle. Covers directed
//              extreme and mixed-sign cases and randomized stimulus.
//
// Dependencies: adder_tree (src/datapath/adder_tree.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_adder_tree;

    // Parameters
    localparam N = 3;
    localparam PROD_WIDTH = 18;
    localparam SUM_WIDTH  = PROD_WIDTH + $clog2(N*N);
    localparam NUM_TESTS = 100;  // random stimulus vectors

    // DUT interconnect
    reg  [N*N*PROD_WIDTH-1:0] products_i;
    wire signed [SUM_WIDTH-1:0] sum_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer t;  // reference tap counter
    integer errors = 0;
    reg signed [SUM_WIDTH-1:0] expected_sum;  // golden reference sum

    // Module instantiation
    adder_tree #(
        .N(N),
        .PROD_WIDTH(PROD_WIDTH),
        .SUM_WIDTH (SUM_WIDTH)
    ) dut (
        .products_i(products_i),
        .sum_o     (sum_o)
    );

    // Golden reference
    // Sums every product slice arithmetically with explicit signed casts.
    always @(*) begin : reference
        expected_sum = {SUM_WIDTH{1'b0}};
        for (t = 0; t < N*N; t = t + 1) begin
            expected_sum = expected_sum + $signed(products_i[PROD_WIDTH*t +: PROD_WIDTH]);
        end
    end

    // Checker
    // Compares the sum 1 ns after each stimulus change, once settled.
    always @(*) begin : check
        #1;
        if (sum_o !== expected_sum) begin
            errors = errors + 1;
            $display("FAIL t=%0t: dut=%0d expected=%0d", $time, sum_o, expected_sum);
        end
    end

    // Test sequence
    initial begin : test
        // Drive all inputs low
        products_i = 0;
        #10;

        // Directed test 1: all zeros
        products_i = 0;
        #10;

        // Directed test 2: all maximum positive products
        // 9 x 32385 = 291465, the largest possible sum.
        products_i = {N*N{18'd32385}};
        #10;

        // Directed test 3: all maximum-magnitude negative products
        // 9 x -32640 = -293760.
        products_i = {N*N{-18'sd32640}};
        #10;

        // Directed test 4: alternating signs
        // Even taps +1000, odd taps -1000 -> sum -1000.
        for (i = 0; i < N*N; i = i + 1) begin
            products_i[PROD_WIDTH*i +: PROD_WIDTH] = (i % 2 == 0) ? 18'sd1000 : -18'sd1000;
        end
        #10;

        // Directed test 5: per-tap ramp with mixed signs
        // Tap g = 1000*g - 4000 -> sum = -36000.
        for (i = 0; i < N*N; i = i + 1) begin
            products_i[PROD_WIDTH*i +: PROD_WIDTH] = 1000*i - 4000;
        end
        #10;

        // Random stimulus
        // Stress-test with random product vectors. Six concatenated
        // $urandom() calls (192 bits) ensure every tap of the 162-bit vector
        // gets random data; fewer calls would leave the top taps zero.
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            products_i = {$urandom(), $urandom(), $urandom(), $urandom(), $urandom(),
                          $urandom()};
            #10;
        end

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | products=%h | sum=%0d expected=%0d", $time, products_i, sum_o,
                 expected_sum);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_adder_tree.vcd");
        $dumpvars(0, tb_adder_tree);
    end

endmodule
