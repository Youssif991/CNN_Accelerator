`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/02/2026
// Design Name: CNN Convolution Datapath - Output FIFO Testbench
// Module Name: tb_output_fifo
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the FWFT output FIFO. A golden
//              reference tracks the occupancy with a counter (an independent
//              algorithm from the DUT's wrap pointers) plus a circular data
//              mirror; the checker compares rd_data_o, rd_valid_o, and
//              wr_ready_o on negedge. Covers reset, fill-to-full, drain-to-
//              empty, wrap-around, back-to-back, simultaneous push/pop, and
//              randomized stimulus.
//
// Dependencies: output_fifo (src/datapath/output_fifo.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_output_fifo;

    // Parameters
    localparam DATA_WIDTH = 16;
    localparam DEPTH = 8;  // small for fast exhaustive coverage
    localparam NUM_TESTS = 500;  // random stimulus cycles

    // DUT interface
    reg clk_i;
    reg rst_n_i;
    reg [DATA_WIDTH-1:0] wr_data_i;
    reg wr_valid_i;
    wire wr_ready_o;
    wire [DATA_WIDTH-1:0] rd_data_o;
    wire rd_valid_o;
    reg rd_ready_i;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer errors = 0;

    // Golden reference: occupancy counter + circular data mirror
    integer g_cnt = 0;
    integer g_head = 0;
    integer g_tail = 0;
    reg [DATA_WIDTH-1:0] g_mem[0:DEPTH-1];
    wire g_full = (g_cnt == DEPTH);
    wire g_empty = (g_cnt == 0);

    // Module instantiation
    output_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .wr_data_i (wr_data_i),
        .wr_valid_i(wr_valid_i),
        .wr_ready_o(wr_ready_o),
        .rd_data_o (rd_data_o),
        .rd_valid_o(rd_valid_o),
        .rd_ready_i(rd_ready_i)
    );

    // Clock generation: free-running 20 ns period (50 MHz)
    initial begin : clock
        clk_i = 0;
        forever #10 clk_i = ~clk_i;
    end

    // Golden reference: mirror the transfers on posedge (same inputs as the
    // DUT); the occupancy counter is an independent algorithm from the DUT's
    // wrap pointers, so a pointer bug cannot be copied. Push and pop in the
    // same cycle net to zero occupancy, so they are handled in one branch.
    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            g_cnt <= 0;
            g_head <= 0;
            g_tail <= 0;
        end else begin
            if (wr_valid_i && !g_full && rd_ready_i && !g_empty) begin
                // push and pop in the same cycle: occupancy unchanged
                g_mem[g_tail] <= wr_data_i;
                g_tail <= (g_tail == DEPTH - 1) ? 0 : g_tail + 1;
                g_head <= (g_head == DEPTH - 1) ? 0 : g_head + 1;
            end else if (wr_valid_i && !g_full) begin
                // push only
                g_mem[g_tail] <= wr_data_i;
                g_tail <= (g_tail == DEPTH - 1) ? 0 : g_tail + 1;
                g_cnt <= g_cnt + 1;
            end else if (!g_empty && rd_ready_i) begin
                // pop only
                g_head <= (g_head == DEPTH - 1) ? 0 : g_head + 1;
                g_cnt <= g_cnt - 1;
            end
        end
    end

    // Combinational expectations from the reference state
    wire expected_rd_valid = !g_empty;
    wire expected_wr_ready = !g_full;
    wire [DATA_WIDTH-1:0] expected_rd_data = g_mem[g_head];

    // Checker: compare on negedge, after the posedge updates settle
    always @(negedge clk_i) begin : check
        if (rst_n_i) begin
            if (rd_valid_o !== expected_rd_valid) begin
                errors = errors + 1;
                $display("FAIL t=%0t: rd_valid=%b expected=%b", $time, rd_valid_o,
                         expected_rd_valid);
            end
            if (wr_ready_o !== expected_wr_ready) begin
                errors = errors + 1;
                $display("FAIL t=%0t: wr_ready=%b expected=%b", $time, wr_ready_o,
                         expected_wr_ready);
            end
            if (rd_valid_o && (rd_data_o !== expected_rd_data)) begin
                errors = errors + 1;
                $display("FAIL t=%0t: rd_data=%0d expected=%0d", $time, rd_data_o,
                         expected_rd_data);
            end
        end
    end

    // Task: one stimulus cycle (drive, advance one clock)
    task stim;
        input integer wr_v;
        input integer rd_r;
        input [DATA_WIDTH-1:0] data;
        begin
            @(negedge clk_i);
            wr_valid_i = wr_v;
            rd_ready_i = rd_r;
            wr_data_i = data;
        end
    endtask

    // Test procedure
    initial begin : test
        // Drive all inputs low and assert reset
        clk_i = 0;
        wr_valid_i = 0;
        rd_ready_i = 0;
        wr_data_i = 0;
        rst_n_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;
        @(negedge clk_i);

        // Directed test 1: fill the FIFO back-to-back, then drain it
        for (i = 0; i < DEPTH; i = i + 1) stim(1, 0, 100 + i);  // push only
        stim(0, 0, 0);  // settle so the last push lands
        if (wr_ready_o !== 0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: FIFO not full after %0d pushes", $time, DEPTH);
        end
        for (i = 0; i < DEPTH; i = i + 1) stim(0, 1, 0);  // pop only
        stim(0, 0, 0);  // settle so the last pop lands
        if (rd_valid_o !== 0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: FIFO not empty after %0d pops", $time, DEPTH);
        end

        // Directed test 2: wrap-around (more than DEPTH total words)
        for (i = 0; i < DEPTH * 2; i = i + 1) stim(1, 0, i);  // push 16, keep
        for (i = 0; i < DEPTH * 2; i = i + 1) stim(0, 1, 0);  // pop 16, drain
        stim(0, 0, 0);  // settle
        if (rd_valid_o !== 0) begin
            errors = errors + 1;
            $display("FAIL t=%0t: FIFO not empty after wrap-around drain", $time);
        end

        // Directed test 3: back-to-back push AND pop (throughput mode)
        for (i = 0; i < DEPTH * 3; i = i + 1) stim(1, 1, 500 + i);

        // Random stimulus: random valid/ready/data including stalls
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            stim($urandom % 2, $urandom % 2, $urandom % (1 << DATA_WIDTH));
        end

        // Drain everything and compare the remaining words in order
        while (!g_empty) begin
            stim(0, 1, 0);
        end
        @(negedge clk_i);
        stim(0, 0, 0);

        // Allow the last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | wr_v=%b wr_r=%b data=%0d | rd_v=%b rd_r=%b rd_data=%0d", $time,
                 wr_valid_i, wr_ready_o, wr_data_i, rd_valid_o, rd_ready_i, rd_data_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_output_fifo.vcd");
        $dumpvars(0, tb_output_fifo);
    end

endmodule
