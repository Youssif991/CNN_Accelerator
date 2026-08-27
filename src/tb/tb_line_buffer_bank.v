`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Line Buffer Bank Testbench
// Module Name: tb_line_buffer_bank
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the line buffer bank. A golden
//              reference models the N row streams with a single shared delay
//              line (a different algorithm from the DUT's chained line
//              buffers); the checker compares every row_streams_o slice on
//              negedge clk. Covers reset, a full multi-row image, hold, and
//              randomized stimulus.
//
// Dependencies: line_buffer_bank (src/datapath/line_buffer_bank.v)
//               line_buffer (src/datapath/line_buffer.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_line_buffer_bank;

    // Parameters
    localparam N = 3;
    localparam IMAGE_WIDTH = 32;
    localparam PIXEL_WIDTH = 8;
    localparam DELAY_TAPS = (N-1)*IMAGE_WIDTH + 1;  // shared delay line depth
    localparam NUM_TESTS = 150;  // random stimulus vectors

    // DUT interconnect
    reg clk_i;
    reg rst_n_i;
    reg shift_valid_i;
    reg [PIXEL_WIDTH-1:0] pixel_in_i;
    wire [N*PIXEL_WIDTH-1:0] row_streams_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer s;  // reference/checker stream counter
    integer k;  // reference reset loop counter
    integer errors = 0;
    reg [PIXEL_WIDTH-1:0] expected_dly [0:DELAY_TAPS-1];  // reference delay line
    integer expected_wr_ptr;  // reference write pointer
    reg [N*PIXEL_WIDTH-1:0] expected_streams;  // flattened expected row streams

    // Module instantiation
    line_buffer_bank #(
        .N(N),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) dut (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .shift_valid_i(shift_valid_i),
        .pixel_in_i   (pixel_in_i),
        .row_streams_o(row_streams_o)
    );

    // Golden reference
    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            for (k = 0; k < DELAY_TAPS; k = k + 1) expected_dly[k] <= 0;
            expected_wr_ptr <= 0;
        end else if (shift_valid_i) begin
            expected_dly[expected_wr_ptr] <= pixel_in_i;
            expected_wr_ptr <= (expected_wr_ptr == DELAY_TAPS-1) ? 0 : expected_wr_ptr + 1;
        end
    end

    // Combinational tap read
    always @(*) begin : expected_streams_comb
        for (s = 1; s < N; s = s + 1) begin
            expected_streams[s*PIXEL_WIDTH +: PIXEL_WIDTH] =
                expected_dly[(expected_wr_ptr + DELAY_TAPS - s*IMAGE_WIDTH) % DELAY_TAPS];
        end
    end

    // Checker
    always @(posedge clk_i) begin : check_stream0
        if (rst_n_i && (row_streams_o[0*PIXEL_WIDTH +: PIXEL_WIDTH] !== pixel_in_i)) begin
            errors = errors + 1;
            $display("FAIL t=%0t: stream=0 dut=%0d expected=%0d", $time,
                     row_streams_o[0*PIXEL_WIDTH +: PIXEL_WIDTH], pixel_in_i);
        end
    end

    always @(negedge clk_i) begin : check
        if (rst_n_i) begin
            for (s = 1; s < N; s = s + 1) begin
                if (row_streams_o[s*PIXEL_WIDTH +: PIXEL_WIDTH] !==
                    expected_streams[s*PIXEL_WIDTH +: PIXEL_WIDTH]) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: stream=%0d dut=%0d expected=%0d", $time, s,
                             row_streams_o[s*PIXEL_WIDTH +: PIXEL_WIDTH],
                             expected_streams[s*PIXEL_WIDTH +: PIXEL_WIDTH]);
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
        pixel_in_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;  // release reset

        // Directed test 1: stream a full 3-row image
        // N*IMAGE_WIDTH pixels with valid=1: stream s must equal the pixel
        // from s rows earlier; delayed streams start at zero until their
        // delay elapses.
        for (i = 0; i < N*IMAGE_WIDTH; i = i + 1) begin
            @(negedge clk_i);
            shift_valid_i = 1;
            pixel_in_i = i;
        end
        @(negedge clk_i);
        shift_valid_i = 0;

        // Directed test 2: hold while valid is low
        // Input changes must not propagate to any stream.
        @(negedge clk_i);
        shift_valid_i = 0;
        pixel_in_i = 8'd77;
        repeat (2) @(negedge clk_i);

        // Directed test 3: back-to-back second image
        for (i = 0; i < N*IMAGE_WIDTH; i = i + 1) begin
            @(negedge clk_i);
            shift_valid_i = 1;
            pixel_in_i = 200 + i;
        end
        @(negedge clk_i);
        shift_valid_i = 0;

        // Random stimulus
        // Stress-test with random shift enables and pixel values.
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
        $monitor("Time=%0t | rst_n=%b valid=%b in=%0d | streams=%h expected=%h", $time, rst_n_i,
                 shift_valid_i, pixel_in_i, row_streams_o, expected_streams);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_line_buffer_bank.vcd");
        $dumpvars(0, tb_line_buffer_bank);
    end

endmodule
