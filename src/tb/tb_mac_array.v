`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - MAC Array Testbench
// Module Name: tb_mac_array
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the NxN MAC array. A golden
//              reference computes every tap product arithmetically (unsigned
//              pixel x signed coefficient) and the checker compares all
//              products_o slices after a #1 settle. Covers directed edge
//              cases (zero, extremes, negative coefficients) and randomized
//              stimulus.
//
// Dependencies: mac_array (src/datapath/mac_array.v)
//               booth_mult_r4 (src/booth_mult/booth_mult_r4.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_mac_array;

    // Parameters
    localparam N = 3;
    localparam PIXEL_WIDTH = 8;
    localparam COEFF_WIDTH = 8;
    localparam PROD_WIDTH  = PIXEL_WIDTH + COEFF_WIDTH + 2;
    localparam NUM_TESTS = 100;  // random stimulus vectors

    // DUT interconnect
    reg  [N*N*PIXEL_WIDTH-1:0] window_i;
    reg  [N*N*COEFF_WIDTH-1:0] kernel_i;
    wire [N*N*PROD_WIDTH-1:0]  products_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer t;  // reference tap counter
    integer u;  // checker tap counter
    integer errors = 0;
    reg signed [PROD_WIDTH-1:0] expected_products [0:N*N-1];  // golden reference taps

    // Module instantiation
    mac_array #(
        .N(N),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .PROD_WIDTH (PROD_WIDTH)
    ) dut (
        .window_i  (window_i),
        .kernel_i  (kernel_i),
        .products_o(products_o)
    );

    // Golden reference
    always @(*) begin : reference
        for (t = 0; t < N*N; t = t + 1) begin
            expected_products[t] = $signed({1'b0, window_i[PIXEL_WIDTH*t +: PIXEL_WIDTH]}) *
                                   $signed(kernel_i[COEFF_WIDTH*t +: COEFF_WIDTH]);
        end
    end

    // Checker
    always @(*) begin : check
        #1;
        for (u = 0; u < N*N; u = u + 1) begin
            if (products_o[PROD_WIDTH*u +: PROD_WIDTH] !== expected_products[u]) begin
                errors = errors + 1;
                $display("FAIL t=%0t: tap=%0d dut=%0d expected=%0d", $time, u,
                         $signed(products_o[PROD_WIDTH*u +: PROD_WIDTH]),
                         expected_products[u]);
            end
        end
    end

    // Test sequence
    initial begin : test
        // Drive all inputs low
        window_i = 0;
        kernel_i = 0;
        #10;

        // Directed test 1: all zeros
        window_i = 0;
        kernel_i = 0;
        #10;

        // Directed test 2: all ones (window and kernel)
        window_i = {N*N*PIXEL_WIDTH{1'b1}};
        kernel_i = {N*N*COEFF_WIDTH{1'b1}};
        #10;

        // Directed test 3: positive extremes
        // Every window tap 255, every kernel tap 127 -> products 32385.
        window_i = {N*N{8'd255}};
        kernel_i = {N*N{8'sd127}};
        #10;

        // Directed test 4: negative coefficients
        // Window all 255, kernel all -1 -> products -255.
        window_i = {N*N{8'd255}};
        kernel_i = {N*N{-8'sd1}};
        #10;
        // Window all 1, kernel all -128 -> products -128.
        window_i = {N*N{8'd1}};
        kernel_i = {N*N{-8'sd128}};
        #10;

        // Directed test 5: distinct per-tap pattern
        // Tap g: window = g, kernel = -g (signed), product = -(g*g).
        for (i = 0; i < N*N; i = i + 1) begin
            window_i[PIXEL_WIDTH*i +: PIXEL_WIDTH] = i;
            kernel_i[COEFF_WIDTH*i +: COEFF_WIDTH] = -i;
        end
        #10;

        // Random stimulus
        // Stress-test with random window and kernel values. The vectors are
        // built from concatenated $urandom() calls (a 72-bit range exceeds a
        // 32-bit integer, so a modulo by (1 << 72) would overflow to zero).
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            window_i = {$urandom(), $urandom(), $urandom()};
            kernel_i = {$urandom(), $urandom(), $urandom()};
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
        $monitor("Time=%0t | window=%h kernel=%h | products=%h", $time, window_i, kernel_i,
                 products_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_mac_array.vcd");
        $dumpvars(0, tb_mac_array);
    end

endmodule
