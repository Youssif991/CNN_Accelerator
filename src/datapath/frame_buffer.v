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
//              RAM inference: mem[] carries a ram_style="block" attribute to
//              force mapping onto a Block RAM primitive (RAMB36/RAMB18 on
//              this 7-series part) instead of distributed RAM or a
//              flip-flop + wide-mux fallback. The mem[] write still lives in
//              its own reset-free always block with no other register
//              sharing it (same isolation rule as row_buffer_bank/
//              kernel_reg_bank) - that isolation is necessary but, without
//              the attribute, not sufficient to guarantee BRAM over
//              distributed RAM at this depth; the attribute makes the
//              choice explicit instead of leaving it to the tool's own
//              area/depth heuristic.
//
//              Read latency changed: mem[] is now registered on read
//              (Block RAM's own output register) instead of combinational,
//              so rd_data_o is presented one cycle AFTER rd_en_i, not the
//              same cycle. This is the standard BRAM read timing and is a
//              real timing/behavioral difference from the previous
//              distributed-RAM version - the caller's rd_en_i sequencing
//              must account for this one-cycle shift.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created (multiple-kernel feature).
//   0.02 - Split the mem[] write into its own reset-free always block so
//          Vivado can infer RAM for mem[] instead of falling back to
//          registers + a wide mux.
//   0.03 - Added ram_style="block" attribute to force Block RAM mapping
//          (XC7Z020 RAMB36E1/RAMB18E1) instead of distributed RAM, and
//          registered the read output to match BRAM's native timing.
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
                                                     // (registered: valid one cycle after rd_en_i)
);

    localparam TOTAL      = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam ADDR_WIDTH = $clog2(TOTAL);

    // Flat frame storage (one real image, row-major). ram_style="block"
    // forces Block RAM inference on this 7-series part instead of
    // distributed RAM.
    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] mem[0:TOTAL-1];

    // Write address (current)
    reg [ADDR_WIDTH-1:0] wr_addr_q;
    // Write address (next)
    reg [ADDR_WIDTH-1:0] wr_addr_d;

    // Write-address next-state
    always @(*) begin : wr_addr_next
        wr_addr_d = wr_addr_q;
        if (wr_rst_addr_i)      wr_addr_d = {ADDR_WIDTH{1'b0}};
        else if (wr_en_i)       wr_addr_d = wr_addr_q + 1'b1;
    end

    // Write-address state update (reset-bearing register, kept out of the
    // memory-write block below)
    always @(posedge clk_i or negedge rst_n_i) begin : wr_addr_state
        if (!rst_n_i) wr_addr_q <= {ADDR_WIDTH{1'b0}};
        else          wr_addr_q <= wr_addr_d;
    end

    // Memory write (no reset: an async reset would break RAM inference,
    // same as row_buffer_bank's row_mem and kernel_reg_bank's kernel_q)
    always @(posedge clk_i) begin : mem_write
        if (wr_en_i) mem[wr_addr_q] <= wr_data_i;
    end

    // Read address (current)
    reg [ADDR_WIDTH-1:0] rd_addr_q;
    // Read address (next)
    reg [ADDR_WIDTH-1:0] rd_addr_d;

    // Read-address next-state
    always @(*) begin : rd_addr_next
        rd_addr_d = rd_addr_q;
        if (rd_rst_addr_i)      rd_addr_d = {ADDR_WIDTH{1'b0}};
        else if (rd_en_i)       rd_addr_d = rd_addr_q + 1'b1;
    end

    // Read-address state update
    always @(posedge clk_i or negedge rst_n_i) begin : rd_addr_state
        if (!rst_n_i) rd_addr_q <= {ADDR_WIDTH{1'b0}};
        else          rd_addr_q <= rd_addr_d;
    end

    // Registered read: Block RAM's native read port is synchronous, so the
    // read data is captured into a register here (no reset: keeps this in
    // the same reset-free style as the memory write above, and matches how
    // RAMB36E1/RAMB18E1's own output register behaves - it has no
    // meaningful "reset value" worth modeling since mem[] itself is
    // uninitialized until written).
    reg [PIXEL_WIDTH-1:0] rd_data_q;

    always @(posedge clk_i) begin : mem_read
        if (rd_en_i) rd_data_q <= mem[rd_addr_d];
    end

    assign rd_data_o = rd_data_q;

endmodule