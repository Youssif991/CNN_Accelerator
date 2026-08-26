`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/26/2026
// Design Name: Radix-4 Booth Carry-Save Adder Testbench
// Module Name: tb_carry_save_adder
// Tool Versions: Vivado 2025.2
// Description: Self-checking testbench for the 3:2 carry-save adder (a bank of
//              full adders). Each bit column computes sum = a ^ b ^ c and
//              carry = majority(a, b, c); the checker verifies the identity
//              a + b + c == sum + (carry << 1) modulo 2^WIDTH for every vector.
//              Covers directed column-state and boundary/wrap-around vectors,
//              then randomized full-width stimulus.
//
// Dependencies: carry_save_adder (src/rtl/carry_save_adder.v)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tb_carry_save_adder;

    // Parameters
    localparam WIDTH = 18;
    localparam NUM_TESTS = 200;

    // DUT interface
    reg [WIDTH-1:0] a_i = 0;
    reg [WIDTH-1:0] b_i = 0;
    reg [WIDTH-1:0] c_i = 0;
    wire [WIDTH-1:0] sum_o;
    wire [WIDTH-1:0] carry_o;

    // Test infrastructure
    integer i;
    integer errors = 0;
    reg [WIDTH-1:0] expected_total = 0;

    // Module instantiation
    carry_save_adder #(
        .WIDTH(WIDTH)
    ) dut (
        .a_i(a_i),
        .b_i(b_i),
        .c_i(c_i),
        .sum_o(sum_o),
        .carry_o(carry_o)
    );

    // Golden reference
    always @(*) begin : reference
        expected_total = a_i + b_i + c_i;
    end

    // Checker
    always @(*) begin : check
        #1;
        if ((sum_o + (carry_o << 1)) !== expected_total) begin
            errors = errors + 1;
            $display("FAIL t=%0t: a=%h b=%h c=%h | dut sum=%h carry=%h | exp=%h", $time, a_i, b_i,
                     c_i, sum_o, carry_o, expected_total);
        end
    end

    // Test procedure.
    initial begin : test
        // Drive all inputs low
        a_i = 0;
        b_i = 0;
        c_i = 0;

        // Directed test 1: all 8 states of one bit column
        $display("   a  b  c | Sum  Carry | Expected");
        $display("   ------- | --------- | --------");
        for (i = 0; i < 8; i = i + 1) begin
            a_i = 0;
            b_i = 0;
            c_i = 0;
            a_i[0] = i[0];
            b_i[0] = i[1];
            c_i[0] = i[2];
            #10;
            $display("   %h %h %h | %h    %h   | %h", a_i, b_i, c_i, sum_o, carry_o,
                     expected_total);
        end

        // Directed test 2: boundary / wrap-around values
        for (i = 0; i < 3; i = i + 1) begin
            a_i = {WIDTH{1'b1}};
            case (i)
                0: begin
                    b_i = {WIDTH{1'b1}};
                    c_i = {WIDTH{1'b1}};
                end
                1: begin
                    b_i = {WIDTH{1'b1}};
                    c_i = 0;
                end
                default: begin
                    b_i = 0;
                    c_i = 0;
                end
            endcase
            #10;
        end

        // Random stimulus.
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            a_i = $urandom() % (1 << WIDTH);
            b_i = $urandom() % (1 << WIDTH);
            c_i = $urandom() % (1 << WIDTH);
            #10;
        end

        // Allow last transaction to settle, then report
        #10;

        if (errors == 0) $display(" TEST PASSED — all checks matched");
        else $display(" TEST FAILED — %0d mismatches found", errors);

        $finish;
    end

    // Live monitor
    initial begin : monitor
        $monitor("Time=%0t | a=%h b=%h c=%h | dut sum=%h carry=%h | expected=%h", $time, a_i, b_i,
                 c_i, sum_o, carry_o, expected_total);
    end

    // VCD dump for waveform debugging
    initial begin
        $dumpfile("tb_carry_save_adder.vcd");
        $dumpvars(0, tb_carry_save_adder);
    end

endmodule
