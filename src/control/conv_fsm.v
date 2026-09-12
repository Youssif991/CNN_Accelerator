`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 08/27/2026
// Design Name: CNN Convolution Control - Conv FSM
// Module Name: conv_fsm
// Tool Versions: Vivado 2025.2
// Description: Frame controller for the convolution accelerator. Sequences
//              kernel loading (LOAD) and the compute pass (COMPUTE) with one
//              output pixel per cycle, then the done handoff. The kernel load
//              is host-paced: LOAD advances one coefficient per
//              kernel_wr_valid_i pulse. The pixel stream is gated by
//              pixel_valid_i: a deasserted valid stalls the shift (line
//              buffers, window, and address counters all hold), so the
//              pipeline stays synchronized under stalls. Outputs are Moore
//              (state-derived); result_valid_o is registered to align with
//              the combinational MAC result that settles one cycle after its
//              window block completes.
//
//              IMAGE_HEIGHT here is the *padded* row count (real image rows
//              plus the pixel_pad_inserter's leading zero-padding rows): the
//              caller (accelerator_top) binds it to IMAGE_HEIGHT_real + N-1,
//              not the real image height. A result is only valid once the
//              sliding window has accumulated N-1 full padded rows of history
//              (row >= N-1); no column gate is needed any more; because
//              pixel_pad_inserter prepends real zero rows (so the row-delay
//              line buffers hold genuine zeros, not garbage) and window_array
//              flushes its older columns at the start of every row (see
//              row_start_o below), every column of every row past the first
//              N-1 padded rows is already a correctly zero-padded window --
//              there is no longer a "straddles two rows" seam to exclude.
//              This removes the FILL state entirely: LOAD transitions
//              straight into COMPUTE, and the row gate alone suppresses the
//              (one-time, not periodic) padding-row prefix.
//
// Dependencies: none (drives the datapath, pixel_pad_inserter, and window_array)
//
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Added column gate to block_valid (fix row-boundary
//                  wraparound window bug)
// Revision 0.03 - Removed the column gate and the FILL state: IMAGE_HEIGHT
//                  now denotes the padded row count, block_valid is a
//                  row-only check, and row padding + the window's row-start
//                  flush give a gap-free, zero-padded stream for free. Added
//                  row_start_o (drives window_array's flush) and
//                  stream_start_o (a one-cycle pulse on the LOAD->COMPUTE
//                  transition, used to arm pixel_pad_inserter for the frame).
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module conv_fsm #(
    parameter N = 3,  // Kernel size (N >= 2)
    parameter IMAGE_WIDTH = 32,  // Input feature-map width
    parameter IMAGE_HEIGHT = 32,  // Padded row count (real rows + N-1 leading pad rows)
    parameter COEFF_WIDTH = 8,  // Kernel coefficient width
    parameter PIPE_STAGES = 0,  // Datapath pipeline delay (stages after the window)
    parameter PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT),
    parameter STATE_WIDTH = 2  // State encoding width
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire start_i,  // Frame start request
    input wire pixel_valid_i,  // Input pixel valid (deasserted = stall)
    input wire output_stall_i,  // Output consumer stalled (freeze the accept)
    input wire kernel_wr_valid_i,  // Kernel coefficient write valid (host-paced)
    input wire [COEFF_WIDTH-1:0] kernel_data_i,  // Kernel coefficient data in
    input wire [PIX_ADDR_WIDTH-1:0] pix_addr_i,  // Current input pixel index
    input wire pix_last_i,  // Last input pixel is being presented
    output wire kernel_we_o,  // Kernel load write enable
    output wire [$clog2(N*N)-1:0] kernel_addr_o,  // Kernel load address
    output wire shift_valid_o,  // Shift the line buffers and the window
    output wire row_start_o,  // First column of a new row: flush window_array instead of shifting
    output wire stream_start_o,  // One-cycle pulse on LOAD->COMPUTE: arms pixel_pad_inserter
    output wire ready_o,  // Accepting input pixels (COMPUTE, ungated)
    output wire result_valid_o,  // Output pixel valid (pipeline aligned)
    output wire rst_count_o,  // Reset the address-generator counters
    output wire busy_o,  // Frame in progress
    output wire done_o,  // Frame complete
    output wire [STATE_WIDTH-1:0] state_o  // Current state (observability)
);

    // State encoding
    localparam S_IDLE = 0;
    localparam S_LOAD = 1;
    localparam S_COMPUTE = 2;
    localparam S_DONE = 3;

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

    // Row and column of the current input pixel (padded coordinate system)
    wire [PIX_ADDR_WIDTH-1:0] pix_row = pix_addr_i / IMAGE_WIDTH;
    wire [PIX_ADDR_WIDTH-1:0] pix_col = pix_addr_i % IMAGE_WIDTH;

    // A result is valid once N-1 full padded rows of history are behind us;
    // window_array's row-start flush already makes every column correct.
    wire block_valid = (pix_row >= N-1);

    // The last cycle of LOAD (about to move to COMPUTE): arms the pad inserter.
    wire load_done = (state_q == S_LOAD) && kernel_wr_valid_i && (load_cnt_q == N*N-1);

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
                    if (load_cnt_q == N*N-1) state_d = S_COMPUTE;
                end
            end
            // Shift the padded stream and produce one output pixel per cycle.
            S_COMPUTE: begin
                if (output_stall_i) begin
                    result_valid_d = result_valid_q;
                end else begin
                    result_valid_d = block_valid && pixel_valid_i;
                    if (pix_last_i && pixel_valid_i) begin
                        exit_cnt_d = PIPE_STAGES + 2;
                    end else if (exit_cnt_q > 0) begin
                        exit_cnt_d = exit_cnt_q - 1;
                        if (exit_cnt_q == 1) state_d = S_DONE;
                    end
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

    // Output decode (Moore, except stream_start_o/load_done which are Mealy
    // pulses on the LOAD->COMPUTE transition)
    assign kernel_we_o = (state_q == S_LOAD);
    assign kernel_addr_o = load_cnt_q;
    assign shift_valid_o = (state_q == S_COMPUTE) && pixel_valid_i && !output_stall_i;
    assign row_start_o = shift_valid_o && (pix_col == 0);
    assign stream_start_o = load_done;
    assign ready_o = (state_q == S_COMPUTE) && !output_stall_i;
    assign result_valid_o = result_valid_q;
    assign rst_count_o = (state_q == S_LOAD);
    assign busy_o = (state_q == S_LOAD) || (state_q == S_COMPUTE);
    assign done_o = (state_q == S_DONE);
    assign state_o = state_q;

endmodule
