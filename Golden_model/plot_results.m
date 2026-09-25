%% plot_dut_vs_matlab_vs_exact.m
%
% Loads the RTL testbench's DUT output and the MATLAB fixed-point golden
% model output from hex files, computes the ideal ("exact") unquantized
% floating-point convolution from scratch, and displays all three side by
% side (per kernel) on one figure for visual comparison. Also prints a
% quick DUT-vs-golden-model correctness check (max/mean abs difference).
%
% Run with: run plot_dut_vs_matlab_vs_exact.m   (no other script required)

clear; clc; close all;

%% ---------------------------------------------------------------------
%  PARAMETERS  (must match the RTL/testbench configuration used to
%  produce the hex files)
%  -----------------------------------------------------------------------
N            = 5;
IMAGE_WIDTH  = 64;
IMAGE_HEIGHT = 64;
PIXEL_WIDTH  = 8;
COEFF_WIDTH  = 8;
OUT_BITS     = 16;
RELU_ENABLE  = true;
FRAC_BITS    = 4;      % already chosen from a prior sweep; fixed here
NUM_KERNELS  = 1;

% hex_dir is resolved relative to THIS script's own folder (not the
% current working directory), so the script can be run from anywhere.
script_dir = fileparts(mfilename('fullpath'));
hex_dir    = fullfile(script_dir, '..', 'src', 'tb');

% Padding, generalized for any odd N.
% NOTE: floor((N+1)/2) for PAD_ROWS_AFTER / PAD_COLS_AFTER (as originally
% specified) makes total padding = N (not N-1), which would grow the
% "exact" result to (IMAGE_HEIGHT+1) x (IMAGE_WIDTH+1) instead of matching
% the DUT/expected hex arrays' IMAGE_HEIGHT x IMAGE_WIDTH size. These two
% "before" variables are kept exactly as specified and are what actually
% get passed to compute_floating_point(); that function derives a
% matching pad_after internally ((N-1) - pad_before) so the output size
% always equals the input size for odd N. The *_AFTER variables below are
% still computed/displayed for documentation, but are not used for the
% actual convolution (see compute_floating_point below).
PAD_ROWS_BEFORE = floor((N - 1) / 2);
PAD_ROWS_AFTER  = floor((N + 1) / 2);   % informational only, see note above
PAD_COLS_BEFORE = floor((N - 1) / 2);
PAD_COLS_AFTER  = floor((N + 1) / 2);   % informational only, see note above

%% ---------------------------------------------------------------------
%  KERNEL DEFINITIONS (must match generate_golden_vectors.m exactly)
%  -----------------------------------------------------------------------
kernels = zeros(N, N, NUM_KERNELS);

if NUM_KERNELS >= 1
    kernels(:, :, 1) = [ ...
     0,  0, -1,  0,  0; ...
     0, -1, -2, -1,  0; ...
    -1, -2, 16, -2, -1; ...
     0, -1, -2, -1,  0; ...
     0,  0, -1,  0,  0];  % kernel 1: vertical edge detector
end
if NUM_KERNELS >= 2
    kernels(:, :, 2) = [1 1 1; 0 0 0; -1 -1 -1];   % kernel 2: horizontal edge detector
end
if NUM_KERNELS > 2
    error('plot_dut_vs_matlab_vs_exact:unsupportedKernelCount', ...
        'Only 2 standard kernels are defined (vertical/horizontal edge detectors); NUM_KERNELS > 2 is not supported.');
end

%% ---------------------------------------------------------------------
%  SOURCE IMAGE
%  -----------------------------------------------------------------------
img_file = 'input_image.jpg';
if exist(img_file, 'file')
    warning('Loading source image from "%s".', img_file);
    raw = imread(img_file);
    if size(raw, 3) == 3
        raw = rgb2gray(raw);
    end
    img = uint8(imresize(raw, [IMAGE_HEIGHT, IMAGE_WIDTH], 'nearest'));
else
    warning('"%s" not found; synthesizing a %dx%d checkerboard test image instead.', ...
        img_file, IMAGE_HEIGHT, IMAGE_WIDTH);
    % NOTE: checkerboard(1, IMAGE_HEIGHT, IMAGE_WIDTH) (the literal call
    % given in the spec) actually returns a (2*IMAGE_HEIGHT) x
    % (2*IMAGE_WIDTH) image, because each of the P x Q tiles checkerboard()
    % lays out is 2 pixels x 2 pixels when the unit-square size is 1. To
    % end up with exactly IMAGE_HEIGHT x IMAGE_WIDTH (required for the
    % reshape against the hex files below), the tile counts are halved and
    % the result is cropped defensively to the exact requested size.
    board = checkerboard(1, ceil(IMAGE_HEIGHT / 2), ceil(IMAGE_WIDTH / 2)) * 255;
    board = board(1:IMAGE_HEIGHT, 1:IMAGE_WIDTH);
    img = uint8(board);
end

%% ---------------------------------------------------------------------
%  READ DUT AND EXPECTED (GOLDEN MODEL) HEX FILES
%  -----------------------------------------------------------------------
dut_file = fullfile(hex_dir, 'dut_output.hex');
exp_file = fullfile(hex_dir, 'expected_output.hex');

dut_raw = read_hex_signed(dut_file, OUT_BITS);
exp_raw = read_hex_signed(exp_file, OUT_BITS);

%% ---------------------------------------------------------------------
%  VALIDATION
%  -----------------------------------------------------------------------
expected_count = IMAGE_HEIGHT * IMAGE_WIDTH * NUM_KERNELS;

if numel(dut_raw) ~= expected_count
    error('plot_dut_vs_matlab_vs_exact:dutSizeMismatch', ...
        ['dut_output.hex ("%s") has %d values, but IMAGE_HEIGHT*IMAGE_WIDTH*' ...
         'NUM_KERNELS = %d*%d*%d = %d values were expected.'], ...
        dut_file, numel(dut_raw), IMAGE_HEIGHT, IMAGE_WIDTH, NUM_KERNELS, expected_count);
end

if numel(exp_raw) ~= expected_count
    error('plot_dut_vs_matlab_vs_exact:expectedSizeMismatch', ...
        ['expected_output.hex ("%s") has %d values, but IMAGE_HEIGHT*IMAGE_WIDTH*' ...
         'NUM_KERNELS = %d*%d*%d = %d values were expected.'], ...
        exp_file, numel(exp_raw), IMAGE_HEIGHT, IMAGE_WIDTH, NUM_KERNELS, expected_count);
end

%% ---------------------------------------------------------------------
%  BUILD PER-KERNEL IMAGES: DUT, EXPECTED (GOLDEN), AND EXACT (FLOAT)
%  -----------------------------------------------------------------------
slice_len = IMAGE_HEIGHT * IMAGE_WIDTH;

dut_imgs   = cell(NUM_KERNELS, 1);
exp_imgs   = cell(NUM_KERNELS, 1);
exact_imgs = cell(NUM_KERNELS, 1);

for k_idx = 1:NUM_KERNELS
    idx_start = (k_idx - 1) * slice_len + 1;
    idx_end   = k_idx * slice_len;

    dut_slice = dut_raw(idx_start:idx_end);
    exp_slice = exp_raw(idx_start:idx_end);

    % Undo the row-major (raster-scan) flattening used when the golden
    % files were generated.
    dut_imgs{k_idx} = reshape(dut_slice, [IMAGE_WIDTH, IMAGE_HEIGHT]).';
    exp_imgs{k_idx} = reshape(exp_slice, [IMAGE_WIDTH, IMAGE_HEIGHT]).';

    exact_imgs{k_idx} = compute_floating_point(img, kernels(:, :, k_idx), N, ...
        PAD_ROWS_BEFORE, PAD_COLS_BEFORE, RELU_ENABLE);
end

%% ---------------------------------------------------------------------
%  SANITY CHECK: DUT vs EXPECTED (GOLDEN MODEL), SHOULD MATCH EXACTLY
%  -----------------------------------------------------------------------
fprintf('\n================ DUT vs MATLAB fixed-point (golden model) ============\n');
for k_idx = 1:NUM_KERNELS
    diff_dut_exp = double(dut_imgs{k_idx}) - double(exp_imgs{k_idx});
    max_abs_diff  = max(abs(diff_dut_exp(:)));
    mean_abs_diff = mean(abs(diff_dut_exp(:)));
    fprintf('Kernel %d: max |DUT-Expected| = %g, mean |DUT-Expected| = %g\n', ...
        k_idx - 1, max_abs_diff, mean_abs_diff);
end
fprintf('========================================================================\n\n');

%% ---------------------------------------------------------------------
%  PLOTTING: ONE FIGURE, NUM_KERNELS ROWS x 3 COLUMNS
%  -----------------------------------------------------------------------
fig = figure('Name', sprintf('DUT vs MATLAB (fixed-point) vs Exact (floating-point) - FRAC_BITS = %d', FRAC_BITS), ...
    'Position', [100 100 1400 450 * NUM_KERNELS]);

for k_idx = 1:NUM_KERNELS
    dut_img   = double(dut_imgs{k_idx});
    exp_img   = double(exp_imgs{k_idx});
    exact_img = double(exact_imgs{k_idx});

    all_vals  = [dut_img(:); exp_img(:); exact_img(:)];
    clim_lo   = min(all_vals);
    clim_hi   = max(all_vals);
    if clim_lo == clim_hi
        clim_hi = clim_lo + 1;   % avoid a degenerate color range
    end

    row_base = (k_idx - 1) * 3;

    subplot(NUM_KERNELS, 3, row_base + 1);
    imagesc(dut_img, [clim_lo clim_hi]);
    colormap(gca, 'gray'); axis image;
    title(sprintf('DUT - kernel %d', k_idx - 1));

    subplot(NUM_KERNELS, 3, row_base + 2);
    imagesc(exp_img, [clim_lo clim_hi]);
    colormap(gca, 'gray'); axis image;
    title(sprintf('MATLAB fixed-point (expected) - kernel %d', k_idx - 1));

    subplot(NUM_KERNELS, 3, row_base + 3);
    imagesc(exact_img, [clim_lo clim_hi]);
    colormap(gca, 'gray'); axis image;
    title(sprintf('Exact (floating-point, FRAC\\_BITS=inf) - kernel %d', k_idx - 1));
    colorbar;
end

sgtitle(sprintf('DUT vs MATLAB (fixed-point) vs Exact (floating-point) - FRAC\\_BITS = %d', FRAC_BITS));

%% =======================================================================
%  LOCAL FUNCTIONS
%  =======================================================================

function vals = read_hex_signed(filename, width_bits)
% Reads one hex value per line from 'filename', converts each to an
% unsigned integer, and sign-extends via two's complement to a signed
% width_bits-bit value.
    fid = fopen(filename, 'r');
    if fid == -1
        error('read_hex_signed:fileNotFound', 'Could not open hex file: %s', filename);
    end
    raw = textscan(fid, '%s');
    fclose(fid);

    hex_strs = raw{1};
    n = numel(hex_strs);
    vals = zeros(n, 1);

    for i = 1:n
        unsigned_value = hex2dec(hex_strs{i});
        if unsigned_value >= 2^(width_bits - 1)
            vals(i) = unsigned_value - 2^width_bits;
        else
            vals(i) = unsigned_value;
        end
    end
end

function out = compute_floating_point(image, kernel, N, pad_rows_before, pad_cols_before, relu_enable)
% Ideal floating-point (unquantized) convolution: real-valued kernel,
% double-precision accumulation, same-padding output size (derives
% pad_after = (N-1) - pad_before internally so output size always equals
% input size for odd N), optional ReLU. NO quantization, rounding, or
% saturation.
%
% CORRELATION, NOT FLIPPED CONVOLUTION: the RTL's mac_chain accumulates
% sum_{i,j} kernel(i,j) * pixel(...) directly (correlation). MATLAB's
% conv2 performs true convolution (flips the kernel both ways before
% sliding), so the kernel is pre-flipped with rot90(kernel,2) here so that
% conv2's internal flip cancels out and the result matches the RTL.
    pad_rows_after = (N - 1) - pad_rows_before;
    pad_cols_after = (N - 1) - pad_cols_before;

    img_d = double(image);
    [H, W] = size(img_d);

    padded = zeros(H + pad_rows_before + pad_rows_after, W + pad_cols_before + pad_cols_after);
    padded(pad_rows_before + 1 : pad_rows_before + H, ...
           pad_cols_before + 1 : pad_cols_before + W) = img_d;

    out = conv2(padded, rot90(kernel, 2), 'valid');   % correlation via pre-flipped kernel

    if relu_enable
        out = max(out, 0);
    end
end