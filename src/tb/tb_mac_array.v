`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - MAC Array Testbench
// Module Name: tb_mac_array
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the NxN MAC array (DSP taps). A
//              golden reference computes every tap product arithmetically
//              (unsigned pixel x signed coefficient); the checker samples all
//              products_o slices one clock after each vector is applied, since
//              the DSP output register is the first pipeline stage. Covers
//              directed edge cases (zero, extremes, negative coefficients) and
//              randomized stimulus.
//
// Dependencies: mac_array (src/datapath/mac_array.v)
//               dsp_mult_r4 (src/multiplier/dsp_mult_r4.v)
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
    reg  clk_i;
    reg  en_i = 1;
    reg  [N*N*PIXEL_WIDTH-1:0] window_i;
    reg  [N*N*COEFF_WIDTH-1:0] kernel_i;
    wire [N*N*PROD_WIDTH-1:0]  products_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer t;  // reference tap counter
    integer errors = 0;
    reg signed [PROD_WIDTH-1:0] expected_products [0:N*N-1];  // golden reference taps

    // Module instantiation
    mac_array #(
        .N            (N),
        .PIXEL_WIDTH  (PIXEL_WIDTH),
        .COEFF_WIDTH  (COEFF_WIDTH),
        .PROD_WIDTH   (PROD_WIDTH)
    ) dut (
        .clk_i      (clk_i),
        .en_i       (en_i),
        .window_i   (window_i),
        .kernel_i   (kernel_i),
        .products_o (products_o)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Task: apply one vector and check every tap one clock later (the DSP
    // output register captures the vector at the next posedge).
    task apply_check;
        input [N*N*PIXEL_WIDTH-1:0] win;
        input [N*N*COEFF_WIDTH-1:0] ker;
        begin
            @(negedge clk_i);
            window_i = win;
            kernel_i = ker;
            @(posedge clk_i);
            @(negedge clk_i);
            for (t = 0; t < N*N; t = t + 1) begin
                expected_products[t] =
                    $signed({1'b0, window_i[PIXEL_WIDTH*t +: PIXEL_WIDTH]}) *
                    $signed(kernel_i[COEFF_WIDTH*t +: COEFF_WIDTH]);
                if (products_o[PROD_WIDTH*t +: PROD_WIDTH] !== expected_products[t]) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: tap=%0d dut=%0d expected=%0d", $time, t,
                             $signed(products_o[PROD_WIDTH*t +: PROD_WIDTH]),
                             expected_products[t]);
                end
            end
        end
    endtask

    // Test procedure
    initial begin : test
        // Drive all inputs low and synchronize to the clock
        window_i = 0;
        kernel_i = 0;

        // Directed test 1: all zeros
        apply_check({N*N*PIXEL_WIDTH{1'b0}}, {N*N*COEFF_WIDTH{1'b0}});

        // Directed test 2: all ones (window and kernel)
        apply_check({N*N*PIXEL_WIDTH{1'b1}}, {N*N*COEFF_WIDTH{1'b1}});

        // Directed test 3: positive extremes
        // Every window tap 255, every kernel tap 127 -> products 32385.
        apply_check({N*N{8'd255}}, {N*N{8'sd127}});

        // Directed test 4: negative coefficients
        // Window all 255, kernel all -1 -> products -255.
        apply_check({N*N{8'd255}}, {N*N{-8'sd1}});
        // Window all 1, kernel all -128 -> products -128.
        apply_check({N*N{8'd1}}, {N*N{-8'sd128}});

        // Directed test 5: distinct per-tap pattern
        // Tap g: window = g, kernel = -g (signed), product = -(g*g).
        for (i = 0; i < N*N; i = i + 1) begin
            window_i[PIXEL_WIDTH*i +: PIXEL_WIDTH] = i;
            kernel_i[COEFF_WIDTH*i +: COEFF_WIDTH] = -i;
        end
        @(negedge clk_i);
        @(posedge clk_i);
        @(negedge clk_i);
        for (t = 0; t < N*N; t = t + 1) begin
            expected_products[t] =
                $signed({1'b0, window_i[PIXEL_WIDTH*t +: PIXEL_WIDTH]}) *
                $signed(kernel_i[COEFF_WIDTH*t +: COEFF_WIDTH]);
            if (products_o[PROD_WIDTH*t +: PROD_WIDTH] !== expected_products[t]) begin
                errors = errors + 1;
                $display("FAIL t=%0t: tap=%0d dut=%0d expected=%0d", $time, t,
                         $signed(products_o[PROD_WIDTH*t +: PROD_WIDTH]), expected_products[t]);
            end
        end

        // Random stimulus
        // Stress-test with random window and kernel values. The vectors are
        // built from concatenated $urandom() calls (a 72-bit range exceeds a
        // 32-bit integer, so a modulo by (1 << 72) would overflow to zero).
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            apply_check({$urandom(), $urandom(), $urandom()},
                        {$urandom(), $urandom(), $urandom()});
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
