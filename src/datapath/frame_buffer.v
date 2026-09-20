`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Marwan
//
// Create Date: 09/17/2026
// Design Name: CNN Convolution Datapath - Frame Buffer
// Module Name: frame_buffer
// Tool Versions: Vivado 2025.2
// Description: Stores one real image (IMAGE_WIDTH x IMAGE_HEIGHT pixels) so a
//              multi-kernel job only needs the host to stream the frame once.
//
//              Write side: during the live (pass 0) stream, accelerator_top
//              writes each accepted real pixel here (wr_en_i pulses once per
//              accepted host pixel) at a free-running address that resets on
//              wr_rst_addr_i (tied to the job's start_i).
//
//              Read side: during a replay pass (kernel index > 0),
//              accelerator_top reads this buffer instead of the host's
//              pixel_in_i, one pixel per rd_en_i pulse, at an address that
//              resets on rd_rst_addr_i (tied to the FSM's per-pass
//              stream_start pulse) so every replay pass starts from pixel 0.
//
//              Combinational read, like row_buffer_bank/kernel_reg_bank: the
//              data at the current read address is presented the same cycle
//              it is consumed (rd_en_i), matching the way pixel_in_i is a
//              combinational value sampled the cycle it's accepted.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created (multiple-kernel feature).
//////////////////////////////////////////////////////////////////////////////////

module frame_buffer#(
    parameter IMAGE_WIDTH  = 32,
    parameter IMAGE_HEIGHT = 32,
    parameter PIXEL_WIDTH  = 8
) (
    input  wire                     clk_i,
    input  wire                     rst_n_i,

    // Write (capture) side - live pass only
    input  wire                     wr_en_i,        // Accepted real pixel this cycle
    input  wire                     wr_rst_addr_i,  // Restart the write address (job start)
    input  wire [PIXEL_WIDTH-1:0]   wr_data_i,      // Pixel to store

    // Read (replay) side - kernel passes 1..N_Kernel-1
    input  wire                     rd_en_i,        // Consumed a replay pixel this cycle
    input  wire                     rd_rst_addr_i,  // Restart the read address (pass start)
    output wire [PIXEL_WIDTH-1:0]   rd_data_o       // Pixel at the current read address
);

    localparam TOTAL      = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam ADDR_WIDTH = $clog2(TOTAL);

    // Flat frame storage (one real image, row-major)
    reg [PIXEL_WIDTH-1:0] mem[0:TOTAL-1];

    // Write address (current/next)
    reg [ADDR_WIDTH-1:0] wr_addr_q;

    always @(posedge clk_i or negedge rst_n_i) begin : write
        if (!rst_n_i) begin
            wr_addr_q <= {ADDR_WIDTH{1'b0}};
        end else if (wr_rst_addr_i) begin
            wr_addr_q <= {ADDR_WIDTH{1'b0}};
        end else if (wr_en_i) begin
            mem[wr_addr_q] <= wr_data_i;
            wr_addr_q      <= wr_addr_q + 1'b1;
        end
    end

    // Read address (current/next)
    reg [ADDR_WIDTH-1:0] rd_addr_q;

    always @(posedge clk_i or negedge rst_n_i) begin : read_ptr
        if (!rst_n_i) begin
            rd_addr_q <= {ADDR_WIDTH{1'b0}};
        end else if (rd_rst_addr_i) begin
            rd_addr_q <= {ADDR_WIDTH{1'b0}};
        end else if (rd_en_i) begin
            rd_addr_q <= rd_addr_q + 1'b1;
        end
    end

    assign rd_data_o = mem[rd_addr_q];

endmodule
