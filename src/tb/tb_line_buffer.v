`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Line Buffer Testbench
// Module Name: tb_line_buffer
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the one-row line buffer. A golden
//              reference models the shift register on posedge clk; the
//              checker compares pixel_out_o against it on negedge clk.
//              Covers reset, a full-row ramp delay, hold, and randomized
//              stimulus.
//
// Dependencies: line_buffer (src/datapath/line_buffer.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_line_buffer;

    // Parameters
    localparam IMAGE_WIDTH = 32;
    localparam PIXEL_WIDTH = 8;
    localparam NUM_TESTS = 100;  // random stimulus vectors

    // DUT interconnect
    reg                   clk_i;
    reg                   rst_n_i;
    reg                   shift_valid_i;
    reg  [PIXEL_WIDTH-1:0] pixel_in_i;
    wire [PIXEL_WIDTH-1:0] pixel_out_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer k;  // reference loop counter (separate from i)
    integer errors = 0;
    reg [PIXEL_WIDTH-1:0] expected_pixel_out;
    reg [PIXEL_WIDTH-1:0] expected_mem [0:IMAGE_WIDTH-1];  // reference circular buffer
    integer expected_wr_ptr;  // reference write pointer

    // Golden reference
    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            for (k = 0; k < IMAGE_WIDTH; k = k + 1) expected_mem[k] <= 0;
            expected_wr_ptr <= 0;
        end else if (shift_valid_i) begin
            expected_mem[expected_wr_ptr] <= pixel_in_i;
            expected_wr_ptr <= (expected_wr_ptr == IMAGE_WIDTH-1) ? 0 : expected_wr_ptr + 1;
        end
    end

    // Combinational read of the delayed pixel from the reference buffer
    always @(*) begin
        expected_pixel_out = expected_mem[expected_wr_ptr];
    end

    // DUT instantiation
    line_buffer #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .shift_valid_i(shift_valid_i),
        .pixel_in_i(pixel_in_i),
        .pixel_out_o(pixel_out_o)
    );

    // Checker
    always @(negedge clk_i) begin : check
        if (rst_n_i && (pixel_out_o !== expected_pixel_out)) begin
            errors = errors + 1;
            $display("FAIL t=%0t: valid=%b in=%0d dut=%0d exp=%0d", $time, shift_valid_i,
                     pixel_in_i, pixel_out_o, expected_pixel_out);
        end
    end

    // Clock generator: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Test sequence
    initial begin : test
        // Drive all inputs low and assert reset
        clk_i = 0;
        rst_n_i = 0;
        shift_valid_i = 0;
        pixel_in_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;  // release reset

        // Directed test 1: full-row delay with a ramp
        // Stream IMAGE_WIDTH + 2 pixels with valid=1; the output must equal
        // the pixel entered exactly IMAGE_WIDTH valid cycles earlier.
        for (i = 0; i < IMAGE_WIDTH + 2; i = i + 1) begin
            @(negedge clk_i);
            shift_valid_i = 1;
            pixel_in_i = i;
        end
        @(negedge clk_i);
        shift_valid_i = 0;

        // Directed test 2: hold while valid is low
        // Input changes must not propagate to the output.
        @(negedge clk_i);
        shift_valid_i = 0;
        pixel_in_i = 8'd77;
        repeat (2) @(negedge clk_i);

        // Directed test 3: back-to-back rows
        // A second ramp follows immediately after the first.
        for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
            @(negedge clk_i);
            shift_valid_i = 1;
            pixel_in_i = 100 + i;
        end
        @(negedge clk_i);
        shift_valid_i = 0;

        // Random stimulus
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(negedge clk_i);
            shift_valid_i = $urandom() % 2;
            pixel_in_i = $urandom() % (1 << PIXEL_WIDTH);
        end
        @(negedge clk_i);
        shift_valid_i = 0;

        // Allow last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | rst_n=%b valid=%b in=%0d | out=%0d expected=%0d", $time, rst_n_i,
                 shift_valid_i, pixel_in_i, pixel_out_o, expected_pixel_out);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_line_buffer.vcd");
        $dumpvars(0, tb_line_buffer);
    end

endmodule