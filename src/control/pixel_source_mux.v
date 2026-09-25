`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/22/2026
// Design Name: CNN Convolution Control - Pixel Source Mux
// Module Name: pixel_source_mux
// Tool Versions: Vivado 2025.2
// Description: Selects the pixel word fed to pixel_pad_inserter between the
//              live host stream (pass 0) and the frame_buffer replay (later
//              kernel passes), derives the frame_buffer's own write/read
//              enables, and gates the host-facing ready so the host only
//              ever sees ready during the live pass.
//
//              Extracted verbatim out of accelerator_top (previously the
//              live_pass/pad_inserter_pixel_in/pad_inserter_pixel_valid/
//              fb_wr_en/fb_rd_en/ready_o wiring lived directly in the top
//              module). No functional change: same equations, just moved
//              into their own leaf module and instantiated from the top.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created (extracted from accelerator_top).
//////////////////////////////////////////////////////////////////////////////////

module pixel_source_mux #(
    parameter PIXEL_WIDTH = 8
) (
    input  wire                   replay_pass_i,  // High while this pass replays frame_buffer
    input  wire [PIXEL_WIDTH-1:0] pixel_in_i,      // Host pixel data (live pass)
    input  wire                   pixel_valid_i,   // Host pixel valid (live pass)
    input  wire [PIXEL_WIDTH-1:0] fb_rd_data_i,    // frame_buffer replay data
    input  wire                   pad_ready_i,     // pixel_pad_inserter's own ready, ungated
    output wire [PIXEL_WIDTH-1:0] pixel_o,         // Selected pixel data -> pixel_pad_inserter
    output wire                   pixel_valid_o,   // Selected pixel valid -> pixel_pad_inserter
    output wire                   fb_wr_en_o,      // frame_buffer write enable (live pass capture)
    output wire                   fb_rd_en_o,      // frame_buffer read enable (replay pass)
    output wire                   host_ready_o     // Host-facing ready (asserts on live pass only)
);

    wire live_pass = !replay_pass_i;

    assign pixel_o       = live_pass ? pixel_in_i    : fb_rd_data_i;
    assign pixel_valid_o = live_pass ? pixel_valid_i : 1'b1;

    assign fb_wr_en_o = live_pass      && pad_ready_i && pixel_valid_i;
    assign fb_rd_en_o = replay_pass_i  && pad_ready_i;

    assign host_ready_o = pad_ready_i && live_pass;

endmodule
