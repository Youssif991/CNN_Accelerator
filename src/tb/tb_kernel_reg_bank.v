`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: CNN Convolution Datapath - Kernel Register Bank Testbench
// Module Name: tb_kernel_reg_bank
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the kernel register bank. A golden
//              reference model tracks the NxN signed coefficient array on
//              posedge clk; the checker compares every kernel_o tap slice
//              against it on negedge clk. Covers reset, directed loads
//              (positive and negative coefficients), hold, out-of-range
//              writes, and randomized stimulus.
//
// Dependencies: kernel_reg_bank (src/datapath/kernel_reg_bank.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_kernel_reg_bank;

    // Parameters
    localparam N = 3;
    localparam COEFF_WIDTH = 8;
    localparam NUM_TESTS = 100;  // random stimulus vectors

    // DUT interconnect
    reg clk_i;
    reg rst_n_i;
    reg load_valid_i;
    reg signed [COEFF_WIDTH-1:0] load_data_i;
    reg [$clog2(N*N)-1:0] load_addr_i;
    wire [N*N*COEFF_WIDTH-1:0] kernel_o;

    // Test infrastructure
    integer i;  // test procedure loop counter
    integer j;  // reference/checker loop counter
    integer errors = 0;
    reg signed [COEFF_WIDTH-1:0] expected_kernel [0:N*N-1];  // golden reference taps

    // Module instantiation
    kernel_reg_bank #(
        .N(N),
        .COEFF_WIDTH(COEFF_WIDTH)
    ) dut (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .load_valid_i (load_valid_i),
        .load_addr_i  (load_addr_i),
        .load_data_i  (load_data_i),
        .kernel_o     (kernel_o)
    );

    // Golden reference
    always @(posedge clk_i or negedge rst_n_i) begin : reference
        if (!rst_n_i) begin
            for (j = 0; j < N*N; j = j + 1) expected_kernel[j] <= 0;
        end else if (load_valid_i && (load_addr_i < N*N)) begin
            expected_kernel[load_addr_i] <= load_data_i;
        end
    end

    // Checker
    always @(negedge clk_i) begin : check
        if (rst_n_i) begin
            for (j = 0; j < N*N; j = j + 1) begin
                if ($signed(kernel_o[COEFF_WIDTH*j +: COEFF_WIDTH]) !== expected_kernel[j]) begin
                    errors = errors + 1;
                    $display("FAIL t=%0t: tap=%0d dut=%0d expected=%0d", $time, j,
                             $signed(kernel_o[COEFF_WIDTH*j +: COEFF_WIDTH]), expected_kernel[j]);
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
        load_valid_i = 0;
        load_data_i = 0;
        load_addr_i = 0;

        @(negedge clk_i);
        rst_n_i = 1;  // release reset

        // Directed test 1: load all taps with a signed kernel
        for (i = 0; i < N*N; i = i + 1) begin
            @(negedge clk_i);
            load_valid_i = 1;
            load_addr_i = i;
            case (i)
                0: load_data_i = 8'sd3;
                1: load_data_i = -8'sd1;
                2: load_data_i = 8'sd2;
                3: load_data_i = -8'sd128;
                4: load_data_i = 8'sd127;
                5: load_data_i = 8'sd0;
                6: load_data_i = -8'sd7;
                7: load_data_i = 8'sd9;
                default: load_data_i = -8'sd2;
            endcase
        end
        @(negedge clk_i);
        load_valid_i = 0;

        // Directed test 2: hold while valid is low
        @(negedge clk_i);
        load_valid_i = 0;
        load_addr_i = 0;
        load_data_i = 8'sd99;
        repeat (2) @(negedge clk_i);

        // Directed test 3: overwrite a single tap
        @(negedge clk_i);
        load_valid_i = 1;
        load_addr_i = 2;
        load_data_i = -8'sd5;
        @(negedge clk_i);
        load_valid_i = 0;

        // Directed test 4: out-of-range address is ignored
        @(negedge clk_i);
        load_valid_i = 1;
        load_addr_i = 15;
        load_data_i = 8'sd42;
        @(negedge clk_i);
        load_valid_i = 0;

        // Random stimulus
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            @(negedge clk_i);
            load_valid_i = $urandom() % 2;
            load_addr_i = $urandom() % (1 << $clog2(N*N));
            load_data_i = $urandom() % (1 << COEFF_WIDTH);
        end
        @(negedge clk_i);
        load_valid_i = 0;

        // Allow last transaction to settle, then report
        #20;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor: prints signal values on every change
    initial begin : monitor
        $monitor("Time=%0t | rst_n=%b valid=%b addr=%0d data=%0d | kernel_o=%h", $time, rst_n_i,
                 load_valid_i, load_addr_i, load_data_i, kernel_o);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_kernel_reg_bank.vcd");
        $dumpvars(0, tb_kernel_reg_bank);
    end

endmodule
