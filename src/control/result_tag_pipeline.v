`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Youssef
//
// Create Date: 09/22/2026
// Design Name: CNN Convolution Control - Result Tag Pipeline
// Module Name: result_tag_pipeline
// Tool Versions: Vivado 2025.2
// Description: Samples the current pass's frame-last flag and kernel/channel
//              index the same cycle the window they belong to enters the
//              datapath pipeline, then shifts all three tags (last, kernel
//              index, and result-valid) PIPE_STAGES deep in lock-step with
//              the result, so they land aligned with result_o out of
//              mac_chain/sat_round_unit.
//
//              Extracted verbatim out of accelerator_top (previously
//              last_q/kidx_q and the three separate last_p/kidx_p/
//              result_valid_p generate blocks lived directly in the top
//              module). Same equations, same generate structure
//              (PIPE_STAGES == 1 / >= 2 / else), just moved into their own
//              leaf module and instantiated from the top. No functional
//              change.
//
// Dependencies: none (leaf module)
//
// Revision:
//   0.01 - File Created (extracted from accelerator_top).
//////////////////////////////////////////////////////////////////////////////////

module result_tag_pipeline #(
    parameter PIPE_STAGES = 11,
    parameter KIDX_WIDTH  = 1
) (
    input  wire                  clk_i,
    input  wire                  rst_n_i,
    input  wire                  freeze_i,         // Pipeline freeze (output_fifo's almost-full flag)
    input  wire                  pix_last_i,       // Last accepted pixel of the current pass
    input  wire [KIDX_WIDTH-1:0] kernel_idx_i,     // Current pass's kernel/channel index
    input  wire                  result_valid_i,   // conv_fsm's registered result_valid_o
    output wire                  last_p_o,         // Frame-last flag, pipeline aligned
    output wire [KIDX_WIDTH-1:0] kidx_p_o,         // Source kernel index, pipeline aligned
    output wire                  result_valid_p_o  // Result valid, pipeline aligned
);

    // Sampled the same cycle the window enters the pipeline
    reg last_q;
    always @(posedge clk_i or negedge rst_n_i) begin : last_reg
        if (!rst_n_i)         last_q <= 1'b0;
        else if (!freeze_i)   last_q <= pix_last_i;
    end

    reg [KIDX_WIDTH-1:0] kidx_q;
    always @(posedge clk_i or negedge rst_n_i) begin : kidx_reg
        if (!rst_n_i)         kidx_q <= {KIDX_WIDTH{1'b0}};
        else if (!freeze_i)   kidx_q <= kernel_idx_i;
    end

    generate
        if (PIPE_STAGES == 1) begin : gen_pipe_last1
            reg last_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) last_p1 <= 1'b0;
                else if (!freeze_i) last_p1 <= last_q;
            end
            assign last_p_o = last_p1;
        end else if (PIPE_STAGES >= 2) begin : gen_pipe_lastn
            reg [PIPE_STAGES-1:0] last_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) last_p1 <= 0;
                else if (!freeze_i) last_p1 <= {last_p1[PIPE_STAGES-2:0], last_q};
            end
            assign last_p_o = last_p1[PIPE_STAGES-1];
        end else begin : gen_no_pipe_last
            assign last_p_o = last_q;
        end
    endgenerate

    generate
        if (PIPE_STAGES == 1) begin : gen_pipe_kidx1
            reg [KIDX_WIDTH-1:0] kidx_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) kidx_p1 <= {KIDX_WIDTH{1'b0}};
                else if (!freeze_i) kidx_p1 <= kidx_q;
            end
            assign kidx_p_o = kidx_p1;
        end else if (PIPE_STAGES >= 2) begin : gen_pipe_kidxn
            reg [KIDX_WIDTH-1:0] kidx_p1[0:PIPE_STAGES-1];
            integer p;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) begin
                    for (p = 0; p < PIPE_STAGES; p = p + 1) kidx_p1[p] <= {KIDX_WIDTH{1'b0}};
                end else if (!freeze_i) begin
                    kidx_p1[0] <= kidx_q;
                    for (p = 1; p < PIPE_STAGES; p = p + 1) kidx_p1[p] <= kidx_p1[p-1];
                end
            end
            assign kidx_p_o = kidx_p1[PIPE_STAGES-1];
        end else begin : gen_no_pipe_kidx
            assign kidx_p_o = kidx_q;
        end
    endgenerate

    generate
        if (PIPE_STAGES == 1) begin : gen_pipe_valid1
            reg valid_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) valid_p1 <= 1'b0;
                else if (!freeze_i) valid_p1 <= result_valid_i;
            end
            assign result_valid_p_o = valid_p1;
        end else if (PIPE_STAGES >= 2) begin : gen_pipe_validn
            reg [PIPE_STAGES-1:0] valid_p1;
            always @(posedge clk_i or negedge rst_n_i) begin : stage
                if (!rst_n_i) valid_p1 <= 0;
                else if (!freeze_i) valid_p1 <= {valid_p1[PIPE_STAGES-2:0], result_valid_i};
            end
            assign result_valid_p_o = valid_p1[PIPE_STAGES-1];
        end else begin : gen_no_pipe_valid
            assign result_valid_p_o = result_valid_i;
        end
    endgenerate

endmodule
