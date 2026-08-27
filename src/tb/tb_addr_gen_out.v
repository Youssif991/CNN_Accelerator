`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Control - Output Address Generator Testbench
// Module Name: tb_addr_gen_out
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the output address generator. A
//              golden reference models the row-major counter (independent
//              register mirror); the checker compares addr_o and last_o on
//              negedge. Covers reset, count, hold, restart, the full-frame
//              wrap, and randomized enable/restart stimulus.
//
// Dependencies: addr_gen_out (src/control/addr_gen_out.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_addr_gen_out;

    // Parameters
    localparam OUT_IMAGE_WIDTH = 30;
    localparam OUT_IMAGE_HEIGHT = 30;
    localparam ADDR_WIDTH = $clog2(OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT);
    localparam TOTAL = OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT;
    localparam NUM_TESTS = 200;  // random stimulus cycles

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg en_i;
    reg rst_count_i;
    wire [ADDR_WIDTH-1:0] addr_o;
    wire last_o;

    // Test infrastructure
    integer i;  // test loop counter
    integer errors = 0;
    reg seen_last;

    // Module instantiation
    addr_gen_out #(
        .OUT_IMAGE_WIDTH (OUT_IMAGE_WIDTH),
        .OUT_IMAGE_HEIGHT(OUT_IMAGE_HEIGHT),
        .ADDR_WIDTH      (ADDR_WIDTH)
    ) dut (
        .clk_i       (clk_i),
        .rst_n_i     (rst_n_i),
        .en_i        (en_i),
        .rst_count_i (rst_count_i),
        .addr_o      (addr_o),
        .last_o      (last_o)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Golden reference: independent counter mirror
    reg [ADDR_WIDTH-1:0] ref_count_q;

    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            ref_count_q <= 0;
        end else if (rst_count_i) begin
            ref_count_q <= 0;
        end else if (en_i) begin
            ref_count_q <= (ref_count_q == TOTAL-1) ? 0 : ref_count_q + 1;
        end
    end

    assign ref_last = en_i && (ref_count_q == TOTAL-1);

    // Checker
    // Compares DUT against the reference on negedge, after the posedge
    // capture has settled.
    always @(negedge clk_i) begin : check
        if (rst_n_i) begin
            if (addr_o !== ref_count_q) begin
                errors = errors + 1;
                $display("FAIL t=%0t: addr=%0d expected=%0d", $time, addr_o, ref_count_q);
            end
            if (last_o !== ref_last) begin
                errors = errors + 1;
                $display("FAIL t=%0t: last=%b expected=%b", $time, last_o, ref_last);
            end
        end
    end

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        en_i = 0;
        rst_count_i = 0;
        rst_n_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;
        @(negedge clk_i);

        // Directed test 1: count five cycles with the enable high
        en_i = 1;
        repeat (5) @(negedge clk_i);
        if (addr_o !== 5) begin
            errors = errors + 1;
            $display("FAIL t=%0t: count ended at %0d expected 5", $time, addr_o);
        end

        // Directed test 2: hold the count while disabled
        en_i = 0;
        repeat (2) @(negedge clk_i);
        if (addr_o !== 5) begin
            errors = errors + 1;
            $display("FAIL t=%0t: count moved while disabled (%0d)", $time, addr_o);
        end

        // Directed test 3: restart the count mid-frame
        rst_count_i = 1;
        @(negedge clk_i);
        rst_count_i = 0;
        @(negedge clk_i);
        if (addr_o !== 0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: restart left count at %0d expected 0", $time, addr_o);
        end

        // Directed test 4: full frame, last pulse, and wrap to zero
        en_i = 1;
        seen_last = 0;
        repeat (TOTAL + 4) begin
            @(negedge clk_i);
            if (last_o) seen_last = 1;
        end
        if (!seen_last) begin
            errors = errors + 1;
            $display("FAIL t=%0t: last_o never pulsed during the full frame", $time);
        end
        if (addr_o !== 4) begin
            errors = errors + 1;
            $display("FAIL t=%0t: wrap left count at %0d expected 4", $time, addr_o);
        end

        // Random stimulus
        // Stress-test with random enable/restart toggles.
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(negedge clk_i);
            en_i = $urandom & 1;
            rst_count_i = $urandom & 1;
        end
        en_i = 0;
        rst_count_i = 0;

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | en=%b rst=%b | addr=%0d last=%b | expected=%0d", $time, en_i,
                 rst_count_i, addr_o, last_o, ref_count_q);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_addr_gen_out.vcd");
        $dumpvars(0, tb_addr_gen_out);
    end

endmodule
