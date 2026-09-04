`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/04/2026
// Design Name: CNN Convolution Datapath - DSP Multiplier Testbench
// Module Name: tb_dsp_mult_r4
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the registered DSP multiplier. A
//              golden reference computes the product arithmetically (unsigned
//              pixel x signed coefficient); the checker samples prod_o one
//              clock after each vector is applied (the product register is the
//              DSP output). Covers directed edge cases (zero, extremes,
//              negative coefficients) and randomized stimulus.
//
// Dependencies: dsp_mult_r4 (src/multiplier/dsp_mult_r4.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_dsp_mult_r4;

    // Parameters
    localparam PIXEL_WIDTH = 8;
    localparam COEFF_WIDTH = 8;
    localparam PROD_WIDTH  = PIXEL_WIDTH + COEFF_WIDTH + 2;
    localparam NUM_TESTS   = 200;  // random stimulus vectors

    // DUT interface
    reg  clk_i;
    reg  en_i = 1;
    reg  [PIXEL_WIDTH-1:0] pixel_i = 0;  // Unsigned pixel value
    reg signed [COEFF_WIDTH-1:0] coeff_i = 0;  // Signed coefficient
    wire signed [PROD_WIDTH-1:0] prod_o;  // Registered product

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer errors = 0;  // Mismatch counter
    reg signed [PROD_WIDTH-1:0] expected_prod;  // Golden reference product

    // Module instantiation
    dsp_mult_r4 #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .PROD_WIDTH (PROD_WIDTH)
    ) dut (
        .clk_i  (clk_i),
        .en_i   (en_i),
        .pixel_i(pixel_i),
        .coeff_i(coeff_i),
        .prod_o (prod_o)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Task: apply one vector and check the registered product one cycle later
    task apply_check;
        input [PIXEL_WIDTH-1:0] px;
        input signed [COEFF_WIDTH-1:0] cf;
        begin
            @(negedge clk_i);
            pixel_i = px;
            coeff_i = cf;
            @(posedge clk_i);  // the product register captures this vector
            @(negedge clk_i);
            expected_prod = $signed({1'b0, pixel_i}) * $signed(coeff_i);
            if (prod_o !== expected_prod) begin
                errors = errors + 1;
                $display("FAIL t=%0t: pixel=%0d coeff=%0d | dut=%0d expected=%0d", $time, pixel_i,
                         coeff_i, prod_o, expected_prod);
            end
        end
    endtask

    // Test procedure
    initial begin : test
        // Synchronize to the clock
        pixel_i = 0;
        coeff_i = 0;

        // Directed test 1: all-zeros
        apply_check(8'd0, 8'sd0);

        // Directed test 2: pixel sweep with a fixed coefficient
        for (i = 0; i < 256; i = i + 1) apply_check(i[7:0], 8'sd17);

        // Directed test 3: negative coefficients
        apply_check(8'd1, -8'sd1);
        apply_check(8'd255, -8'sd1);
        apply_check(8'd255, -8'sd128);
        apply_check(8'd128, -8'sd128);
        apply_check(8'd1, -8'sd128);

        // Directed test 4: positive extremes
        apply_check(8'd255, 8'sd127);
        apply_check(8'd255, 8'sd1);
        apply_check(8'd0, 8'sd127);
        apply_check(8'd0, -8'sd128);

        // Directed test 5: clock-enable freeze. With en_i low the product
        // register holds its value even when the inputs change (the pipeline
        // freeze); on re-enable it captures the new product.
        apply_check(8'd10, 8'sd3);  // product = 30
        @(negedge clk_i);
        en_i = 0;
        pixel_i = 8'd100;
        coeff_i = 8'sd7;
        @(posedge clk_i);  // en low: the register must hold 30
        @(negedge clk_i);
        if (prod_o !== 30) begin
            errors = errors + 1;
            $display("FAIL t=%0t: en-low freeze: dut=%0d expected=30", $time, prod_o);
        end
        en_i = 1;
        @(posedge clk_i);  // en high: captures 100*7 = 700
        @(negedge clk_i);
        if (prod_o !== 700) begin
            errors = errors + 1;
            $display("FAIL t=%0t: en-high capture: dut=%0d expected=700", $time, prod_o);
        end

        // Random stimulus
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            apply_check($urandom % 256, $urandom % 256);  // signed wrap is fine: golden is exact
        end

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | pixel=%0d coeff=%0d | prod=%0d", $time, pixel_i, coeff_i, prod_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_dsp_mult_r4.vcd");
        $dumpvars(0, tb_dsp_mult_r4);
    end

endmodule
