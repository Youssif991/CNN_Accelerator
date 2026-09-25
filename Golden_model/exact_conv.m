%% kernel_frac_bits_sweep.m
%
% Sweeps FRAC_BITS (fractional-bit count) for a fixed-point 2D convolution
% accelerator model, across six standard image-processing kernels, to find
% the FRAC_BITS value that minimizes the error between the fixed-point
% pipeline (quantized coefficients -> int accumulate -> round-half-up
% rescale -> ReLU -> saturate) and the ideal floating-point convolution.
%
% Run with: run kernel_frac_bits_sweep.m   (no other script required)

clear; clc; close all;

%% ---------------------------------------------------------------------
%  PARAMETERS
%  -----------------------------------------------------------------------
IMAGE_WIDTH      = 512;
IMAGE_HEIGHT     = 512;
PIXEL_WIDTH      = 8;              % unsigned grayscale pixel width
COEFF_WIDTH      = 8;              % signed fixed-point coefficient width
OUT_BITS         = 16;             % signed output width
RELU_ENABLE      = true;
FRAC_BITS_SWEEP  = 0:(COEFF_WIDTH-1);   % sweep every candidate frac-bit count

%% ---------------------------------------------------------------------
%  LOAD (OR SYNTHESIZE) THE TEST IMAGE
%  -----------------------------------------------------------------------
img_file = 'input_image.jpg';
if exist(img_file, 'file')
    raw = imread(img_file);
    if size(raw, 3) == 3
        raw = rgb2gray(raw);
    end
    img = double(imresize(raw, [IMAGE_HEIGHT, IMAGE_WIDTH]));
    img = round(img);
    fprintf('Loaded "%s" and resized to %d x %d.\n', img_file, IMAGE_HEIGHT, IMAGE_WIDTH);
else
    warning('"%s" not found; synthesizing a %dx%d checkerboard test image instead.', ...
        img_file, IMAGE_HEIGHT, IMAGE_WIDTH);
    % Manual checkerboard pattern (base MATLAB only, no toolbox required):
    % equivalent in spirit to the Image Processing Toolbox checkerboard().
    tile = 32;
    [X, Y] = meshgrid(0:IMAGE_WIDTH-1, 0:IMAGE_HEIGHT-1);
    cb  = mod(floor(X / tile) + floor(Y / tile), 2);
    img = double(cb) * (2^PIXEL_WIDTH - 1);
end

% Clamp to the unsigned PIXEL_WIDTH range.
img = min(max(img, 0), 2^PIXEL_WIDTH - 1);

%% ---------------------------------------------------------------------
%  KERNEL DEFINITIONS
%  Each entry: name, real-valued kernel matrix, N = size(kernel,1).
%  -----------------------------------------------------------------------
kernels = struct('name', {}, 'kernel', {}, 'N', {});

% 1. Ridge/edge detection kernel: standard 3x3 discrete Laplacian
%    (4-connected Laplacian operator), the canonical textbook ridge/edge
%    detector: [0 -1 0; -1 4 -1; 0 -1 0].
k = [1 0 -1; 1 0 -1; 1 0 -1];
kernels(end+1) = struct('name', 'Laplacian ridge/edge 3x3', 'kernel', k, 'N', size(k,1));

% 2. Sharpen kernel: standard 3x3 sharpening kernel (identity + Laplacian),
%    the classic textbook "sharpen" filter: [0 -1 0; -1 5 -1; 0 -1 0].
k = [ 0 -1  0;
     -1  5 -1;
      0 -1  0];
kernels(end+1) = struct('name', 'Sharpen 3x3', 'kernel', k, 'N', size(k,1));

% 3. Box blur 3x3: uniform averaging filter, all elements = 1/9.
k = ones(3,3) / 9;
kernels(end+1) = struct('name', 'Box blur 3x3', 'kernel', k, 'N', size(k,1));

% 4. Gaussian blur 3x3: standard discrete binomial approximation to a 2D
%    Gaussian (sigma ~ 1): [1 2 1; 2 4 2; 1 2 1] / 16.
k = [1 2 1; 2 4 2; 1 2 1] / 16;
kernels(end+1) = struct('name', 'Gaussian blur 3x3', 'kernel', k, 'N', size(k,1));

% 5. Gaussian blur 5x5: standard discrete binomial approximation to a 2D
%    Gaussian, formed from the outer product of the 5-tap binomial
%    (Pascal's-triangle) row [1 4 6 4 1], normalized to sum to 1:
%      [ 1  4  6  4  1;
%        4 16 24 16  4;
%        6 24 36 24  6;
%        4 16 24 16  4;
%        1  4  6  4  1] / 256
b  = [1 4 6 4 1];
G5 = (b' * b);          % outer product of the binomial row with itself
G5 = G5 / sum(G5(:));   % normalize (denominator is 256)
kernels(end+1) = struct('name', 'Gaussian blur 5x5', 'kernel', G5, 'N', size(G5,1));

% 6. Unsharp masking 5x5: standard unsharp mask, built as
%    output = original + amount*(original - blurred), i.e.
%      kernel = (1+amount)*delta - amount*Gaussian5x5
%    with amount = 1 and "blurred" = the 5x5 Gaussian kernel above, and
%    delta the 5x5 unit impulse (identity) kernel. This is the classic
%    center-weighted unsharp-mask matrix:
%      [ -1  -4   -6  -4  -1;
%        -4 -16  -24 -16  -4;
%        -6 -24  476 -24  -6;
%        -4 -16  -24 -16  -4;
%        -1  -4   -6  -4  -1] / 256
delta5   = zeros(5,5);
delta5(3,3) = 1;
amount   = 1;
Kunsharp = (1 + amount) * delta5 - amount * G5;
kernels(end+1) = struct('name', 'Unsharp mask 5x5', 'kernel', Kunsharp, 'N', size(Kunsharp,1));

numKernels = numel(kernels);

%% ---------------------------------------------------------------------
%  SWEEP FRAC_BITS FOR EACH KERNEL
%  -----------------------------------------------------------------------
numFB = numel(FRAC_BITS_SWEEP);

meanAbsErr = zeros(numKernels, numFB);
rmseErr    = zeros(numKernels, numFB);
maxAbsErr  = zeros(numKernels, numFB);
overflowFB = false(numKernels, numFB);

for ki = 1:numKernels
    kernel = kernels(ki).kernel;

    % Floating-point reference: computed once per kernel (does not
    % depend on FRAC_BITS).
    floatOut = compute_floating_point(img, kernel, RELU_ENABLE);

    for fi = 1:numFB
        frac_bits = FRAC_BITS_SWEEP(fi);

        [fixedOut, ovf] = compute_fixed_point(img, kernel, frac_bits, ...
            COEFF_WIDTH, OUT_BITS, RELU_ENABLE);
        overflowFB(ki, fi) = ovf;

        diff = fixedOut - floatOut;
        meanAbsErr(ki, fi) = mean(abs(diff(:)));
        rmseErr(ki, fi)    = sqrt(mean(diff(:).^2));
        maxAbsErr(ki, fi)  = max(abs(diff(:)));
    end
end

%% ---------------------------------------------------------------------
%  BEST FRAC_BITS PER KERNEL, PER METRIC
%  -----------------------------------------------------------------------
bestFB_rmse   = zeros(numKernels,1);
bestFB_mae    = zeros(numKernels,1);
bestFB_maxae  = zeros(numKernels,1);
bestVal_rmse  = zeros(numKernels,1);
bestVal_mae   = zeros(numKernels,1);
bestVal_maxae = zeros(numKernels,1);
anyOverflow   = false(numKernels,1);

for ki = 1:numKernels
    [bestVal_rmse(ki),  idxR] = min(rmseErr(ki,:));
    [bestVal_mae(ki),   idxM] = min(meanAbsErr(ki,:));
    [bestVal_maxae(ki), idxX] = min(maxAbsErr(ki,:));

    bestFB_rmse(ki)  = FRAC_BITS_SWEEP(idxR);
    bestFB_mae(ki)   = FRAC_BITS_SWEEP(idxM);
    bestFB_maxae(ki) = FRAC_BITS_SWEEP(idxX);

    anyOverflow(ki) = any(overflowFB(ki,:));
end

kernelNames = {kernels.name}';

resultsTable = table(kernelNames, bestFB_rmse, bestFB_mae, bestFB_maxae, ...
    bestVal_rmse, bestVal_mae, bestVal_maxae, anyOverflow, ...
    'VariableNames', {'KernelName', 'BestFracBits_RMSE', 'BestFracBits_MAE', ...
    'BestFracBits_MaxAE', 'RMSE_at_Best', 'MAE_at_Best', 'MaxAE_at_Best', ...
    'OverflowAtSomeFracBits'});

fprintf('\n================ FRAC_BITS sweep results (per kernel) ================\n');
for ki = 1:numKernels
    fprintf(['%-26s | best FB (RMSE)=%2d (RMSE=%8.4f) | best FB (MAE)=%2d ' ...
        '(MAE=%8.4f) | best FB (MaxAE)=%2d (MaxAE=%8.4f) | overflow seen: %s\n'], ...
        kernelNames{ki}, bestFB_rmse(ki), bestVal_rmse(ki), ...
        bestFB_mae(ki), bestVal_mae(ki), ...
        bestFB_maxae(ki), bestVal_maxae(ki), ...
        mat2str(anyOverflow(ki)));
end
fprintf('========================================================================\n\n');

disp(resultsTable);

%% ---------------------------------------------------------------------
%  PLOT: GRID OF SUBPLOTS, ONE PER KERNEL
%  -----------------------------------------------------------------------
figure('Name', 'FRAC_BITS sweep', 'Position', [100 100 1200 700]);
ncols = ceil(sqrt(numKernels));
nrows = ceil(numKernels / ncols);

for ki = 1:numKernels
    subplot(nrows, ncols, ki);
    plot(FRAC_BITS_SWEEP, meanAbsErr(ki,:), '-o', 'LineWidth', 1.5); hold on;
    plot(FRAC_BITS_SWEEP, rmseErr(ki,:),    '-s', 'LineWidth', 1.5);
    plot(FRAC_BITS_SWEEP, maxAbsErr(ki,:),  '-^', 'LineWidth', 1.5);
    hold off;
    grid on;
    xlabel('FRAC\_BITS');
    ylabel('Error (output LSBs)');
    legend({'Mean Abs Err', 'RMSE', 'Max Abs Err'}, 'Location', 'best');
    title(sprintf('%s (best FB by RMSE = %d)', kernelNames{ki}, bestFB_rmse(ki)));
end
sgtitle('Fixed-point vs. floating-point error vs. FRAC\_BITS');

%% ---------------------------------------------------------------------
%  GLOBAL SUMMARY: SINGLE FRAC_BITS ACROSS ALL KERNELS
%  -----------------------------------------------------------------------
avgRmsePerFB = mean(rmseErr, 1);   % average across kernels, for each FRAC_BITS
[bestAvgRmse, idxGlobal] = min(avgRmsePerFB);
bestGlobalFB = FRAC_BITS_SWEEP(idxGlobal);

fprintf('\n================ Global (single, hardware-wide) FRAC_BITS ============\n');
fprintf('If a single FRAC_BITS must be shared by all kernels, FRAC_BITS = %d\n', bestGlobalFB);
fprintf('minimizes the average RMSE across all %d kernels (avg RMSE = %.4f).\n', ...
    numKernels, bestAvgRmse);
fprintf('Per-FRAC_BITS average RMSE across all kernels:\n');
for fi = 1:numFB
    fprintf('  FRAC_BITS=%2d : avg RMSE = %8.4f\n', FRAC_BITS_SWEEP(fi), avgRmsePerFB(fi));
end
fprintf('========================================================================\n');

%% =======================================================================
%  LOCAL FUNCTIONS
%  =======================================================================

function padded = pad_image(img, pad_before, pad_after)
% Zero-pads a 2D image symmetrically-or-asymmetrically by pad_before rows/
% cols at the top/left and pad_after rows/cols at the bottom/right.
    [H, W] = size(img);
    padded = zeros(H + pad_before + pad_after, W + pad_before + pad_after);
    padded(pad_before+1 : pad_before+H, pad_before+1 : pad_before+W) = img;
end

function out = compute_floating_point(img, kernel, relu_enable)
% Ideal floating-point (unquantized) convolution: real-valued kernel,
% double-precision accumulation, same-padding output size, optional ReLU.
% NOTE ON PADDING: for an odd kernel size N, symmetric same-padding
% requires pad_before = pad_after = (N-1)/2 (total pad = N-1), which is
% what is used below (pad_before = floor((N-1)/2), pad_after =
% floor(N/2), and the two are equal whenever N is odd). This is the
% formula that actually satisfies the "output same size as input for any
% odd N" requirement.
% NOTE ON conv2/CORRELATION: the target hardware accumulates
% sum_{i,j} kernel(i,j) * pixel(...) directly, i.e. CORRELATION, not
% flipped convolution. MATLAB's conv2 performs true convolution (it flips
% the kernel both horizontally and vertically before sliding). To make
% conv2 perform correlation instead, the kernel is pre-flipped with
% rot90(kernel,2) so that conv2's internal flip cancels out.
    N = size(kernel, 1);
    pad_before = floor((N - 1) / 2);
    pad_after  = floor(N / 2);

    padded = pad_image(img, pad_before, pad_after);
    out = conv2(padded, rot90(kernel, 2), 'valid');   % correlation via pre-flipped kernel

    if relu_enable
        out = max(out, 0);
    end
end

function [out, coeff_overflow] = compute_fixed_point(img, kernel, frac_bits, ...
        coeff_width, out_bits, relu_enable)
% Fixed-point pipeline: quantize kernel to coeff_width-bit signed fixed
% point at 'frac_bits' fractional bits, integer-accumulate (int64),
% round-half-up rescale by frac_bits, ReLU, saturate to signed out_bits.
    N = size(kernel, 1);
    pad_before = floor((N - 1) / 2);   % see note in compute_floating_point
    pad_after  = floor(N / 2);

    padded = pad_image(img, pad_before, pad_after);

    % --- Quantize the kernel coefficients ---
    scale     = 2^frac_bits;
    coeff_min = -2^(coeff_width - 1);
    coeff_max =  2^(coeff_width - 1) - 1;

    raw_q = round(kernel * scale);
    coeff_overflow = any(raw_q(:) < coeff_min | raw_q(:) > coeff_max);
    q_kernel = min(max(raw_q, coeff_min), coeff_max);

    % --- Integer-accumulated correlation (int64 semantics) ---
    % conv2 requires floating-point inputs, so the sum is carried out in
    % double precision and then rounded into int64. Every intermediate
    % value here (pixels <= 2^PIXEL_WIDTH-1, quantized coefficients
    % within +/-2^(COEFF_WIDTH-1), kernel taps <= 25) stays far below
    % double's 2^53 exact-integer limit, so this rounding step is exact
    % and faithfully reproduces true int64 accumulation.
    acc_double = conv2(padded, rot90(q_kernel, 2), 'valid');  % correlation, see note above
    acc = int64(round(acc_double));

    % --- Round-half-up rescale by frac_bits (arithmetic right shift) ---
    if frac_bits > 0
        half = int64(2^(frac_bits - 1));
        rescaled = bitshift(acc + half, -frac_bits);   % arithmetic right shift, sign-preserving
    else
        rescaled = acc;
    end

    out = double(rescaled);

    % --- ReLU ---
    if relu_enable
        out = max(out, 0);
    end

    % --- Saturate to signed out_bits range ---
    out_min = -2^(out_bits - 1);
    out_max =  2^(out_bits - 1) - 1;
    out = min(max(out, out_min), out_max);
end