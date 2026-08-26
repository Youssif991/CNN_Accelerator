`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: Radix-4 Booth Multiplier Testbench
// Module Name: tb_booth_mult_r4
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the radix-4 Booth multiplier.
//              Uses a golden reference model (unsigned pixel x signed
//              coefficient) compared against the DUT after each stimulus
//              settles. Covers directed edge cases (zero, extremes, negative
//              coefficients) and randomized full-range stimulus.
//
// Dependencies: booth_mult_r4 (src/booth_mult/booth_mult_r4.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_booth_mult_r4;

    // Parameters
    localparam PIXEL_WIDTH = 8;
    localparam COEFF_WIDTH = 8;
    localparam PROD_WIDTH  = PIXEL_WIDTH + COEFF_WIDTH + 2;
    localparam NUM_TESTS   = 200;  // random stimulus vectors

    // DUT interface
    reg  [PIXEL_WIDTH-1:0] pixel_i = 0;  // Unsigned pixel value
    reg signed [COEFF_WIDTH-1:0] coeff_i = 0;  // Signed coefficient
    wire signed [PROD_WIDTH-1:0] prod_o;  // Product output

    // Test infrastructure
    integer i;  // Loop counter
    integer errors = 0;  // Mismatch counter
    reg signed [PROD_WIDTH-1:0] expected_product_o = 0;  // Golden reference

    // Module instantiation
    booth_mult_r4 #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH),
        .PROD_WIDTH (PROD_WIDTH)
    ) dut (
        .pixel_i (pixel_i),
        .coeff_i (coeff_i),
        .prod_o  (prod_o)
    );

    // Golden reference
    always @(*) begin : reference
        expected_product_o = $signed({1'b0, pixel_i}) * $signed(coeff_i);
    end

    // Checker
    always @(*) begin : check
        #1;
        if (prod_o !== expected_product_o) begin
            errors = errors + 1;
            $display("FAIL t=%0t: pixel=%0d coeff=%0d | dut=%0d expected=%0d", $time, pixel_i,
                     coeff_i, prod_o, expected_product_o);
        end
    end

    // Test procedure
    initial begin : test
        // Drive all inputs low
        pixel_i = 0;
        coeff_i = 0;

        // Directed test 1: all-zeros
        pixel_i = 8'd0;
        coeff_i = 8'd0;
        #10;

        // Directed test 2: coefficient sweep (pixel == coeff)
        for (i = 0; i < 256; i = i + 1) begin
            pixel_i = i;
            coeff_i = i;
            #10;
        end

        // Directed test 3: negative coefficients
        pixel_i = 8'd1;
        coeff_i = -8'sd1;
        #10;
        pixel_i = 8'd255;
        coeff_i = -8'sd1;
        #10;
        pixel_i = 8'd255;
        coeff_i = -8'sd128;  // product extreme: -32640
        #10;
        pixel_i = 8'd128;
        coeff_i = -8'sd128;
        #10;
        pixel_i = 8'd1;
        coeff_i = -8'sd2;
        #10;

        // Directed test 4: positive extremes
        pixel_i = 8'd255;
        coeff_i = 8'sd127;  // product extreme: 32385
        #10;
        pixel_i = 8'd0;
        coeff_i = 8'sd127;
        #10;

        // Random stimulus
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            pixel_i = $urandom() % (1 << PIXEL_WIDTH);
            coeff_i = $urandom() % (1 << COEFF_WIDTH);
            #10;
        end

        // Allow the last transaction to settle, then report
        #10;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | pixel=%0d coeff=%0d | dut=%0d expected=%0d", $time, pixel_i,
                 coeff_i, prod_o, expected_product_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_booth_mult_r4.vcd");
        $dumpvars(0, tb_booth_mult_r4);
    end

endmodule
