`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/02/2026
// Design Name: CNN Convolution Datapath - Output FIFO
// Module Name: output_fifo
// Tool Versions: Vivado 2025.2
// Description: Synchronous first-word-fall-through (FWFT) output FIFO between
//              the convolution pipeline and the downstream consumer (AXI-Stream
//              DMA). The write side accepts when not full (wr_ready_o); the
//              read side presents the oldest word immediately (rd_data_o valid
//              while not empty) and advances on rd_ready_i. DEPTH must be a
//              power of two for the wrap-pointer full/empty detection. A
//              consumer that keeps up never fills the FIFO; if it does, the
//              pipeline back-pressure (wr_ready_o low) holds the result.
//
// Dependencies: none (leaf module)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module output_fifo #(
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 16  // must be a power of two
) (
    input  wire clk_i,
    input  wire rst_n_i,

    // Write (producer) side
    input  wire [DATA_WIDTH-1:0] wr_data_i,
    input  wire wr_valid_i,
    output wire wr_ready_o,  // high while the FIFO can accept a word

    // Read (consumer) side - first-word-fall-through
    output wire [DATA_WIDTH-1:0] rd_data_o,
    output wire rd_valid_o,  // high while a word is available
    input  wire rd_ready_i
);

    localparam ADDR_WIDTH = $clog2(DEPTH);
    localparam PTR_WIDTH = ADDR_WIDTH + 1;

    // Storage
    reg [DATA_WIDTH-1:0] mem_q[0:DEPTH-1];
    // Write pointer (current)
    reg [PTR_WIDTH-1:0] wr_ptr_q;
    // Write pointer (next)
    reg [PTR_WIDTH-1:0] wr_ptr_d;
    // Read pointer (current)
    reg [PTR_WIDTH-1:0] rd_ptr_q;
    // Read pointer (next)
    reg [PTR_WIDTH-1:0] rd_ptr_d;

    // Transfers and status
    wire write_transfer = wr_valid_i && wr_ready_o;
    wire read_transfer = rd_valid_o && rd_ready_i;
    wire fifo_empty = (wr_ptr_q == rd_ptr_q);
    wire fifo_full = (wr_ptr_q[ADDR_WIDTH] != rd_ptr_q[ADDR_WIDTH]) &&
                     (wr_ptr_q[ADDR_WIDTH-1:0] == rd_ptr_q[ADDR_WIDTH-1:0]);

    // Next-state logic
    always @(*) begin : next_state
        wr_ptr_d = wr_ptr_q;
        rd_ptr_d = rd_ptr_q;
        if (write_transfer) wr_ptr_d = wr_ptr_q + 1'b1;
        if (read_transfer) rd_ptr_d = rd_ptr_q + 1'b1;
    end

    // State update
    always @(posedge clk_i or negedge rst_n_i) begin : state
        if (!rst_n_i) begin
            wr_ptr_q <= 0;
            rd_ptr_q <= 0;
        end else begin
            wr_ptr_q <= wr_ptr_d;
            rd_ptr_q <= rd_ptr_d;
        end
    end

    // Memory write
    always @(posedge clk_i) begin : mem_write
        if (write_transfer) mem_q[wr_ptr_q[ADDR_WIDTH-1:0]] <= wr_data_i;
    end

    // Output decode (FWFT: present the oldest word; no read-stage register)
    assign rd_data_o = mem_q[rd_ptr_q[ADDR_WIDTH-1:0]];
    assign rd_valid_o = !fifo_empty;
    assign wr_ready_o = !fifo_full;

endmodule
