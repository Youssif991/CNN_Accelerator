%% generate_golden_vectors.m
% Generate pixel, kernel, and expected-output files for QuestaSim.
%
% Flow:
%   1. Read a real image from disk.
%   2. Convert it to grayscale.
%   3. Resize it to the RTL input dimensions.
%   4. Quantize the fractional kernel to a fixed-point integer format.
%   5. Calculate padded convolution in MATLAB using the quantized kernel.
%   6. Rescale the accumulator back down by FRAC_BITS (round-half-up).
%   7. Apply optional ReLU and output saturation.
%   8. Generate pixel_input.hex, kernel_coeff.hex, and expected_output.hex.

clear;
clc;
close all;

%% ------------------------------------------------------------------------
% Parameters: these values must match the RTL/UVM configuration.
% -------------------------------------------------------------------------
N            = 5;       % Kernel size: N x N
IMAGE_WIDTH  = 8;       % RTL image width
IMAGE_HEIGHT = 8;       % RTL image height
PIXEL_WIDTH  = 8;       % Unsigned grayscale pixel width
COEFF_WIDTH  = 8;       % Signed coefficient width (integer, fixed-point container)
OUT_BITS     = 16;      % Signed output width
RELU_ENABLE  = true;    % Must match the RTL ReLU enable
PADDING      = 0;       % Zero padding
STRIDE       = 1;       % Convolution stride

% --- Fixed-point spec for the kernel -------------------------------------
% The kernel below is defined in real (floating-point) coefficients that
% sum to ~1 (a normalized Gaussian blur). COEFF_WIDTH-bit signed integers
% cannot represent values like 0.0030 directly, so we quantize into a
% Q(COEFF_WIDTH-1-FRAC_BITS).FRAC_BITS fixed-point format:
%   quantized_int = round(real_value * 2^FRAC_BITS)
% This quantized integer is what actually gets written to kernel_coeff.hex
% and is what the RTL must treat as the coefficient. Since the datapath
% itself (MAC array / adder tree / sat_round_unit) has no built-in notion
% of a fractional scale, the RTL must explicitly rescale the accumulated
% sum back down by FRAC_BITS (round-half-up, then saturate) to recover a
% real-valued result in OUT_BITS. This FRAC_BITS rescale is DISTINCT from
% the guard-bit headroom bits used purely to prevent integer overflow
% during accumulation -- do not conflate the two.
FRAC_BITS = 4;           % Q1.7: kernel values must lie in [-1, 1)

%% ------------------------------------------------------------------------
% File paths.
% Change source_image_path to the real image you want to test.
% -------------------------------------------------------------------------
source_image_path = ...
    'D:\IEEE_SSCS\CNN_prjt\CNN_Accelerator\Golden_model\input_image.jpg';

output_dir = ...
    'D:\IEEE_SSCS\CNN_prjt\CNN_Accelerator\testbench';

if ~isfile(source_image_path)
    error('Input image does not exist: %s', source_image_path);
end

if ~isfolder(output_dir)
    mkdir(output_dir);
end

%% ------------------------------------------------------------------------
% Read and preprocess the source image.
% -------------------------------------------------------------------------
source_image = imread(source_image_path);

% Convert RGB/RGBA images to grayscale.
if ndims(source_image) == 3
    source_image = source_image(:,:,1:3);
    source_image = rgb2gray(source_image);
end

% Resize to exactly the dimensions expected by the RTL.
% Nearest-neighbor resizing is simple and reproducible for verification.
image_pixels = imresize(source_image, ...
                         [IMAGE_HEIGHT IMAGE_WIDTH], ...
                         'nearest');

% Ensure the input is an unsigned 8-bit grayscale image.
image_pixels = uint8(image_pixels);

%% ------------------------------------------------------------------------
% Define the real-valued (floating-point) convolution kernel.
% -------------------------------------------------------------------------
kernel = [ ...
0.0030, 0.0133, 0.0219, 0.0133, 0.0030; ...
0.0133, 0.0596, 0.0983, 0.0596, 0.0133; ...
0.0219, 0.0983, 0.1621, 0.0983, 0.0219; ...
0.0133, 0.0596, 0.0983, 0.0596, 0.0133; ...
0.0030, 0.0133, 0.0219, 0.0133, 0.0030];

if size(kernel,1) ~= N || size(kernel,2) ~= N
    error('Kernel dimensions do not match N.');
end

%% ------------------------------------------------------------------------
% Quantize the kernel into fixed-point COEFF_WIDTH-bit signed integers.
% -------------------------------------------------------------------------
coeff_max = 2^(COEFF_WIDTH-1) - 1;
coeff_min = -2^(COEFF_WIDTH-1);

quant_kernel_raw = round(kernel * 2^FRAC_BITS);

if any(quant_kernel_raw(:) > coeff_max) || any(quant_kernel_raw(:) < coeff_min)
    warning(['One or more quantized kernel values overflow COEFF_WIDTH=%d ' ...
             'with FRAC_BITS=%d. They will be clamped, which will distort ' ...
             'the golden result. Consider raising COEFF_WIDTH or lowering ' ...
             'FRAC_BITS.'], COEFF_WIDTH, FRAC_BITS);
end

quant_kernel = int32(min(max(quant_kernel_raw, coeff_min), coeff_max));

quant_error = double(quant_kernel) / 2^FRAC_BITS - kernel;
fprintf('Max kernel quantization error: %.6f\n', max(abs(quant_error(:))));
fprintf('Quantized kernel gain (sum)  : %.6f (ideal ~2^FRAC_BITS = %d)\n', ...
    sum(double(quant_kernel(:))), 2^FRAC_BITS);

%% ------------------------------------------------------------------------
% Calculate padded-convolution output dimensions.
% -------------------------------------------------------------------------
OUTPUT_HEIGHT = floor((IMAGE_HEIGHT + 2*PADDING - N)/STRIDE) + 1;
OUTPUT_WIDTH  = floor((IMAGE_WIDTH  + 2*PADDING - N)/STRIDE) + 1;

expected = zeros(OUTPUT_HEIGHT, OUTPUT_WIDTH, 'int32');

%% ------------------------------------------------------------------------
% MATLAB golden convolution model (fixed-point).
% Zero values are used outside the image boundary.
% -------------------------------------------------------------------------
round_bias = int64(0);
if FRAC_BITS > 0
    round_bias = int64(bitshift(int64(1), FRAC_BITS-1)); % round-half-up
end

for out_row = 1:OUTPUT_HEIGHT
    for out_col = 1:OUTPUT_WIDTH

        accumulator = int64(0);

        for kernel_row = 1:N
            for kernel_col = 1:N

                % Coordinates in the original image.
                image_row = (out_row-1)*STRIDE + kernel_row - PADDING;
                image_col = (out_col-1)*STRIDE + kernel_col - PADDING;

                % Zero-padding boundary behavior.
                if image_row < 1 || image_row > IMAGE_HEIGHT || ...
                   image_col < 1 || image_col > IMAGE_WIDTH
                    pixel_value = int64(0);
                else
                    pixel_value = int64(image_pixels(image_row, image_col));
                end

                coefficient_value = int64(quant_kernel(kernel_row, kernel_col));

                accumulator = accumulator + ...
                    pixel_value * coefficient_value;
            end
        end

        % Rescale back down by FRAC_BITS (round-half-up), since the
        % accumulator is currently in the same fixed-point scale as the
        % quantized kernel (pixel is integer, coefficient is Q.FRAC_BITS,
        % so the product/sum is also Q.FRAC_BITS).
        if FRAC_BITS > 0
            accumulator = bitshift(accumulator + round_bias, -FRAC_BITS);
        end

        accumulator = int32(accumulator);

        % Optional ReLU activation.
        if RELU_ENABLE && accumulator < 0
            accumulator = 0;
        end

        % Signed output saturation.
        max_output = int32(2^(OUT_BITS-1) - 1);
        min_output = int32(-2^(OUT_BITS-1));

        accumulator = min(max(accumulator, min_output), max_output);
        expected(out_row, out_col) = accumulator;
    end
end

%% ------------------------------------------------------------------------
% Convert matrices to raster-scan vectors.
%
% The transpose before reshape gives this order:
%   row 0, col 0 ... row 0, col W-1,
%   row 1, col 0 ... row 1, col W-1,
%   etc.
%
% This order must match the order used by the UVM sequence and RTL.
% -------------------------------------------------------------------------
input_stream    = reshape(image_pixels.', [], 1);
kernel_stream   = reshape(quant_kernel.', [], 1);   % quantized integers, not raw floats
expected_stream = reshape(expected.', [], 1);

%% ------------------------------------------------------------------------
% Write hexadecimal files.
% -------------------------------------------------------------------------
write_hex_file( ...
    fullfile(output_dir, 'pixel_input.hex'), ...
    input_stream, ...
    PIXEL_WIDTH);

write_hex_file( ...
    fullfile(output_dir, 'kernel_coeff.hex'), ...
    kernel_stream, ...
    COEFF_WIDTH);

write_hex_file( ...
    fullfile(output_dir, 'expected_output.hex'), ...
    expected_stream, ...
    OUT_BITS);

%% ------------------------------------------------------------------------
% Display information and verification plots.
% -------------------------------------------------------------------------
fprintf('\nGolden files generated successfully.\n');
fprintf('Source image           : %s\n', source_image_path);
fprintf('Input image size       : %d x %d\n', IMAGE_HEIGHT, IMAGE_WIDTH);
fprintf('Kernel size            : %d x %d\n', N, N);
fprintf('Padding                : %d pixel(s), zero padding\n', PADDING);
fprintf('Stride                 : %d\n', STRIDE);
fprintf('Output image size      : %d x %d\n', OUTPUT_HEIGHT, OUTPUT_WIDTH);
fprintf('Input pixels generated : %d\n', length(input_stream));
fprintf('Kernel values generated: %d\n', length(kernel_stream));
fprintf('Expected outputs       : %d\n', length(expected_stream));
fprintf('ReLU enabled           : %d\n', RELU_ENABLE);
fprintf('Fixed-point FRAC_BITS  : %d\n', FRAC_BITS);
fprintf('Output directory       : %s\n\n', output_dir);

disp('Processed grayscale image sent to the RTL:');
disp(image_pixels);

disp('Real-valued kernel (reference):');
disp(kernel);

disp('Quantized integer kernel (what the RTL actually sees):');
disp(quant_kernel);

disp('MATLAB expected convolution output (post-rescale, ReLU, saturate):');
disp(expected);

figure('Name', 'MATLAB Golden Model');
subplot(1,2,1);
imagesc(image_pixels);
colormap gray;
axis image;
colorbar;
title('Input grayscale image');

subplot(1,2,2);
imagesc(expected);
axis image;
colorbar;
title('Expected padded convolution output');

%% ------------------------------------------------------------------------
% Local helper function for hexadecimal output.
% Negative values are written in two's-complement form.
% -------------------------------------------------------------------------
function write_hex_file(filename, values, width_bits)

    file_id = fopen(filename, 'w');

    if file_id == -1
        error('Could not open file for writing: %s', filename);
    end

    hex_digits = ceil(width_bits/4);
    format_string = ['%0', num2str(hex_digits), 'X\n'];

    for index = 1:length(values)
        unsigned_value = mod(double(values(index)), 2^width_bits);
        fprintf(file_id, format_string, unsigned_value);
    end

    fclose(file_id);
end