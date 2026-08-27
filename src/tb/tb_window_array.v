`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Window Array Testbench
// Module Name: tb_window_array
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the NxN sliding window array. A
//              golden reference models the shift-left / new-column update on
//              posedge clk; the checker compares every window_o tap slice
//              against it on negedge clk. Covers reset, directed fill and
//              shift patterns, hold, row roll-over, and randomized stimulus.
//
// Dependencies: window_array (src/datapath/window_array.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_window_array;

    // Parameters
    localparam N = 3;
    localparam PIXEL_WIDTH = 8;
    localparam NUM_TESTS = 100;  // random stimulus vectors

    // DUT interconnect
    reg clk_i;
    reg rst_n_i;
    reg shift_valid_i;
    reg [N*PIXEL_WIDTH-1:0] data_row_i;
    wire [N*N*PIXEL_WIDTH-1:0] window_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer j;  // test procedure loop counter (reserved)
    integer r;  // reference/checker row counter
    integer c;  // reference/checker column counter
    integer errors = 0;
    reg [PIXEL_WIDTH-1:0] expected_window [0:N-1][0:N-1];  // golden reference window

    // Module instantiation
    window_array #(
        .N(N),
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) dut (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .shift_valid_i(shift_valid_i),
        .data_row_i   (data_row_i),
        .window_o     (window_o)
    );

    // Golden reference
    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    expected_window[r][c] <= 0;
                end
            end
        end else if (shift_valid_i) begin
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N-1; c = c + 1) begin
                    expected_window[r][c] <= expected_window[r][c+1];
                end
                expected_window[r][N-1] <= data_row_i[r*PIXEL_WIDTH +: PIXEL_WIDTH];
            end
        end
    end

    // Checker
    // Compares every window tap on negedge, after the posedge capture settled.
    always @(negedge clk_i) begin : check
        if (rst_n_i) begin
            for (r = 0; r < N; r = r + 1) begin
                for (c = 0; c < N; c = c + 1) begin
                    if (window_o[PIXEL_WIDTH*(r*N+c) +: PIXEL_WIDTH] !==
                        expected_window[r][c]) begin
                        errors = errors + 1;
                        $display("FAIL t=%0t: row=%0d col=%0d dut=%0d expected=%0d", $time, r, c,
                                 window_o[PIXEL_WIDTH*(r*N+c) +: PIXEL_WIDTH],
                                 expected_window[r][c]);
                    end
                end
            end
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
        data_row_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;  // release reset

        // Directed test 1: fill the window with a per-row ramp
        // Cycle k loads data_row slices {20+k, 10+k, k} into rows 2, 1, 0;
        // after N fills, row r holds [10*r, 10*r+1, 10*r+2].
        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk_i);
            shift_valid_i = 1;
            data_row_i = ((20 + i) << 16) | ((10 + i) << 8) | i;
        end
        @(negedge clk_i);
        shift_valid_i = 0;

        // Directed test 2: continue shifting (row roll-over)
        // Three more fills fully overwrite the window: row r -> [10*r+3 .. 10*r+5].
        for (i = N; i < 2*N; i = i + 1) begin
            @(negedge clk_i);
            shift_valid_i = 1;
            data_row_i = ((20 + i) << 16) | ((10 + i) << 8) | i;
        end
        @(negedge clk_i);
        shift_valid_i = 0;

        // Directed test 3: hold while valid is low
        // Bus data changes must not alter the window.
        @(negedge clk_i);
        shift_valid_i = 0;
        data_row_i = {3{8'd99}};
        repeat (2) @(negedge clk_i);

        // Random stimulus
        // Stress-test with random shift enables and pixel columns.
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(negedge clk_i);
            shift_valid_i = $urandom() % 2;
            data_row_i = $urandom() % (1 << (N*PIXEL_WIDTH));
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
        $monitor("Time=%0t | rst_n=%b valid=%b data_row=%h | window_o=%h", $time, rst_n_i,
                 shift_valid_i, data_row_i, window_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_window_array.vcd");
        $dumpvars(0, tb_window_array);
    end

endmodule
