`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Control - Conv FSM
// Module Name: conv_fsm
// Tool Versions: Vivado 2025.2
// Description: Frame controller for the convolution accelerator. Sequences
//              kernel loading (LOAD), input-stream fill (FILL), the compute
//              pass (COMPUTE) with one output pixel per cycle, and the done
//              handoff. The kernel load is host-paced: LOAD advances one
//              coefficient per kernel_wr_valid_i pulse. The pixel stream is
//              gated by pixel_valid_i: a deasserted valid stalls the shift
//              (line buffers, window, and address counters all hold), so the
//              pipeline stays synchronized under stalls. Outputs are Moore
//              (state-derived); result_valid_o is registered to align with
//              the combinational MAC result that settles one cycle after its
//              window block completes.
//
// Dependencies: none (drives the datapath and the address generators)
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module conv_fsm #(
    parameter N = 3,  // Kernel size (N >= 2)
    parameter IMAGE_WIDTH = 32,  // Input feature-map width
    parameter IMAGE_HEIGHT = 32,  // Input feature-map height
    parameter COEFF_WIDTH = 8,  // Kernel coefficient width
    parameter PIPE_STAGES = 0,  // Datapath pipeline delay (stages after the window)
    parameter PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT),
    parameter STATE_WIDTH = 3  // State encoding width
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire start_i,  // Frame start request
    input wire pixel_valid_i,  // Input pixel valid (deasserted = stall)
    input wire kernel_wr_valid_i,  // Kernel coefficient write valid (host-paced)
    input wire [COEFF_WIDTH-1:0] kernel_data_i,  // Kernel coefficient data in
    input wire [PIX_ADDR_WIDTH-1:0] pix_addr_i,  // Current input pixel index
    input wire pix_last_i,  // Last input pixel is being presented
    output wire kernel_we_o,  // Kernel load write enable
    output wire [$clog2(N*N)-1:0] kernel_addr_o,  // Kernel load address
    output wire shift_valid_o,  // Shift the line buffers and the window
    output wire result_valid_o,  // Output pixel valid (pipeline aligned)
    output wire rst_count_o,  // Reset the address-generator counters
    output wire busy_o,  // Frame in progress
    output wire done_o,  // Frame complete
    output wire [STATE_WIDTH-1:0] state_o  // Current state (observability)
);

    // State encoding
    localparam S_IDLE = 0;
    localparam S_LOAD = 1;
    localparam S_FILL = 2;
    localparam S_COMPUTE = 3;
    localparam S_DONE = 4;

    // Fill cycles
    localparam FILL_CYCLES = (N-1) * IMAGE_WIDTH + (N-1);

    // Current state
    reg [STATE_WIDTH-1:0] state_q;
    // Next state
    reg [STATE_WIDTH-1:0] state_d;
    // Kernel load index (current)
    reg [$clog2(N*N)-1:0] load_cnt_q;
    // Kernel load index (next)
    reg [$clog2(N*N)-1:0] load_cnt_d;
    // Compute-exit countdown (current)
    reg [$clog2(PIPE_STAGES+3)-1:0] exit_cnt_q;
    // Compute-exit countdown (next)
    reg [$clog2(PIPE_STAGES+3)-1:0] exit_cnt_d;
    // Result valid (current, pipeline aligned)
    reg result_valid_q;
    // Result valid (next)
    reg result_valid_d;

    // Row of the current input pixel
    wire [PIX_ADDR_WIDTH-1:0] pix_row = pix_addr_i / IMAGE_WIDTH;
    wire block_valid = (pix_row >= N-1);

    // Next-state
    always @(*) begin : next_state
        state_d = state_q;
        load_cnt_d = load_cnt_q;
        exit_cnt_d = exit_cnt_q;
        result_valid_d = 1'b0;

        case (state_q)
            // Wait for a frame-start request
            S_IDLE: begin
                if (start_i) state_d = S_LOAD;
            end
            // Load the N*N kernel coefficients, one per host write
            S_LOAD: begin
                if (kernel_wr_valid_i) begin
                    load_cnt_d = (load_cnt_q == N*N-1) ? 0 : load_cnt_q + 1;
                    if (load_cnt_q == N*N-1) state_d = S_FILL;
                end
            end
            // Prime the line buffers and the window with the first rows
            S_FILL: begin
                if (pix_addr_i >= FILL_CYCLES-1) state_d = S_COMPUTE;
            end
            // Shift the stream and produce one output pixel per cycle.
            S_COMPUTE: begin
                result_valid_d = block_valid && pixel_valid_i;
                if (pix_last_i) begin
                    exit_cnt_d = PIPE_STAGES + 2;
                end else if (exit_cnt_q > 0) begin
                    exit_cnt_d = exit_cnt_q - 1;
                    if (exit_cnt_q == 1) state_d = S_DONE;
                end
            end
            // Hold the done flag, then re-arm for the next frame
            S_DONE: state_d = S_IDLE;
            default: state_d = S_IDLE;
        endcase
    end

    // State update
    always @(posedge clk_i or negedge rst_n_i) begin : state
        if (!rst_n_i) begin
            state_q <= S_IDLE;
            load_cnt_q <= 0;
            exit_cnt_q <= 0;
            result_valid_q <= 1'b0;
        end else begin
            state_q <= state_d;
            load_cnt_q <= load_cnt_d;
            exit_cnt_q <= exit_cnt_d;
            result_valid_q <= result_valid_d;
        end
    end

    // Output decode (Moore)
    assign kernel_we_o = (state_q == S_LOAD);
    assign kernel_addr_o = load_cnt_q;
    assign shift_valid_o = ((state_q == S_FILL) || (state_q == S_COMPUTE)) && pixel_valid_i;
    assign result_valid_o = result_valid_q;
    assign rst_count_o = (state_q == S_LOAD);
    assign busy_o = (state_q == S_LOAD) || (state_q == S_FILL) || (state_q == S_COMPUTE);
    assign done_o = (state_q == S_DONE);
    assign state_o = state_q;

endmodule
