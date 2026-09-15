/*`ifndef CONV_PARAMS_PKG_SVH
`define CONV_PARAMS_PKG_SVH

package conv_params_pkg;
    localparam int N              = 3;
    localparam int IMAGE_WIDTH    = 8;
    localparam int IMAGE_HEIGHT   = 8;
    localparam int PIXEL_WIDTH    = 8;
    localparam int COEFF_WIDTH    = 8;
    localparam int OUT_WIDTH      = 16;
    localparam int ROUND_ENABLE   = 1;
    localparam int FRAC_BITS      = 4;
    localparam int PIPE_STAGES    = 11;
    localparam int PIX_ADDR_WIDTH = $clog2(IMAGE_WIDTH * IMAGE_HEIGHT);
    localparam int PROD_WIDTH     = PIXEL_WIDTH + COEFF_WIDTH + 2;
    localparam int SUM_WIDTH      = PROD_WIDTH + $clog2(N*N);
endpackage
`endif
*/