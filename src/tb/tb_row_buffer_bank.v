`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/14/2026
// Design Name: CNN Convolution Datapath - Row Buffer Bank Testbench
// Module Name: tb_row_buffer_bank
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the rotating row-buffer window bank.
//              A golden reference keeps the history of every pixel shifted in and
//              rebuilds the expected window from it, one row at a time: window
//              row g holds the sample that was shifted in (N-g) padded rows ago,
//              and its three columns are that sample, one before it and one after
//              it, forced to zero at the left/right row borders. The checker
//              compares window_o against that model on negedge, after the posedge
//              capture has settled.
//
//              Covers reset, several full rows (all columns, so both border muxes
//              and every vertical tap are checked), a stream stall (en_i low must
//              freeze the bank and leave the window untouched) and random
//              stimulus with random gaps.
//
// Dependencies: row_buffer_bank (src/datapath/row_buffer_bank.v)
//
// Revision:
// Revision 0.01 - File Created.
//////////////////////////////////////////////////////////////////////////////////

module tb_row_buffer_bank;

    // Parameters
    localparam N = 3;  // Window size (odd)
    localparam IMAGE_WIDTH = 8;  // Row width used by this testbench
    localparam PIXEL_WIDTH = 8;  // Pixel width
    localparam COL_WIDTH = 3;  // $clog2(IMAGE_WIDTH)
    localparam ROWS = 6;  // Rows of ramp stimulus
    localparam RAMP_SAMPLES = (ROWS + N + 1) * IMAGE_WIDTH;  // Accepted ramp pixels
    localparam FLAT_SAMPLES = (ROWS + N + 1) * IMAGE_WIDTH;  // Accepted flat-row pixels
    localparam STIM_CYCLES = 900;  // Stimulus cycles (1 stall in 5)
    localparam STREAM_LEN = 1024;  // Stored stream samples
    localparam FIRST_VALID = N * IMAGE_WIDTH + 1;  // Deepest tap must hold real data
    localparam WINDOW_BITS = N * N * PIXEL_WIDTH;

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg en_i;
    reg [COL_WIDTH-1:0] col_i;
    reg [PIXEL_WIDTH-1:0] pixel_i;
    wire [WINDOW_BITS-1:0] window_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer k;  // reference-model loop counter (kept separate from i: the two
                // loops run concurrently and must not share an index)
    integer stim_idx;  // stream index driven by the test procedure
    integer errors = 0;
    integer p_idx;  // stream index tracked by the reference model
    reg [PIXEL_WIDTH-1:0] stream[0:STREAM_LEN-1];  // every pixel shifted in so far
    reg [WINDOW_BITS-1:0] expected_window;
    reg expected_valid;  // the reference model is meaningful from FIRST_VALID
    integer cur_idx;  // stream index the golden model describes (p_idx - 1)
    integer cur_col;  // its column, for the debug print

    localparam PIX_W = PIXEL_WIDTH;

    // Module instantiation
    row_buffer_bank #(
        .N          (N),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) dut (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (en_i),
        .col_i  (col_i),
        .pixel_i(pixel_i),
        .window_o(window_o)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Golden reference: record the stream and advance its own index only on an
    // accepted pixel, exactly like the DUT's shift enable. p_idx is then one
    // ahead of the pixel presented this cycle, which is why the model below
    // indexes with p_idx - 1.
    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            p_idx <= 0;
        end else if (en_i && (p_idx < STREAM_LEN)) begin
            stream[p_idx] <= pixel_i;
            p_idx <= p_idx + 1;
        end
    end

    // Expected window, rebuilt from the stream history. Window row g (row 0 is
    // the top of the patch) holds the sample i = N-g padded rows back: its col 0
    // tap is the sample i*W+1 back, col 1 is i*W back and col 2 is i*W-1 back.
    // The outer taps are zeroed at the row borders, which is the image's
    // horizontal zero padding.
    always @(*) begin : flags
        expected_valid = (p_idx >= (FIRST_VALID + 1));
        expected_window = {WINDOW_BITS{1'b0}};
        cur_idx = p_idx - 1;
        cur_col = cur_idx % IMAGE_WIDTH;
        for (k = 1; k <= N; k = k + 1) begin
            expected_window[((N-k)*N + 0)*PIX_W +: PIX_W] =
                (cur_col == 0) ? {PIX_W{1'b0}} : stream[cur_idx - (k*IMAGE_WIDTH + 1)];
            expected_window[((N-k)*N + 1)*PIX_W +: PIX_W] = stream[cur_idx - k*IMAGE_WIDTH];
            expected_window[((N-k)*N + 2)*PIX_W +: PIX_W] =
                (cur_col == (IMAGE_WIDTH - 1)) ? {PIX_W{1'b0}} :
                stream[cur_idx - (k*IMAGE_WIDTH - 1)];
        end
    end

    // Checker: compares the DUT window against the reference on negedge, after
    // the posedge capture has settled. Only checked once the deepest tap index
    // is non-negative (the row storage is reset-free).
    always @(negedge clk_i) begin : check
        if (rst_n_i && expected_valid) begin
            if (window_o !== expected_window) begin
                errors = errors + 1;
                $display("FAIL t=%0t: p_idx=%0d cur=%0d row=%0d col=%0d window=%h expected=%h", $time,
                         p_idx, cur_idx, cur_idx / IMAGE_WIDTH, cur_col, window_o,
                         expected_window);
            end
        end
    end

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        en_i = 0;
        col_i = 0;
        pixel_i = 0;
        rst_n_i = 0;
        stim_idx = 0;
        for (i = 0; i < STREAM_LEN; i = i + 1) stream[i] = 0;

        @(negedge clk_i);
        rst_n_i = 1;
        @(negedge clk_i);

        // --- Directed test 1: reset leaves the bank idle ---
        repeat (3) @(negedge clk_i);
        if (window_o !== {WINDOW_BITS{1'b0}}) begin
            errors = errors + 1;
            $display("FAIL t=%0t: window not zero after reset (%h)", $time, window_o);
        end

        // --- Directed test 2, stalls and random stimulus ---
        // One continuous stream, so the reference model and the DUT can never
        // disagree about how many pixels have been accepted. The stimulus is a
        // column-distinct ramp first (no two samples within a window span share a
        // value, so a wrong tap depth or border mask cannot hide), then
        // row-distinct, column-invariant rows (which isolate the vertical taps),
        // and finally random pixels. en_i is withdrawn periodically so the bank is
        // also checked while frozen, and each stall costs one accepted pixel in
        // both the DUT and the model.
        for (i = 0; i < STIM_CYCLES; i = i + 1) begin
            @(negedge clk_i);
            en_i = ((i % 5) != 3);
            if (en_i) begin
                col_i = stim_idx % IMAGE_WIDTH;
                if (stim_idx < RAMP_SAMPLES) pixel_i = stim_idx % 256;
                else if (stim_idx < (RAMP_SAMPLES + FLAT_SAMPLES))
                    pixel_i = ((stim_idx - RAMP_SAMPLES) / IMAGE_WIDTH) + 1;
                else pixel_i = $random;
                stim_idx = stim_idx + 1;
            end
        end

        // Let the last accepted pixel's half-cycle complete before withdrawing
        // en_i, so the DUT and the model stay in step.
        @(negedge clk_i);
        en_i = 0;

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | rst_n=%b en=%b col=%0d pixel=%h | window=%h expected=%h", $time,
                 rst_n_i, en_i, col_i, pixel_i, window_o, expected_window);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_row_buffer_bank.vcd");
        $dumpvars(0, tb_row_buffer_bank);
    end

endmodule
