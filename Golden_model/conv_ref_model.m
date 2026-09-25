%% generate_golden_vectors.m
% Generate pixel, kernel, and expected-output files for QuestaSim.
% Includes support for NUM_KERNELS multi-channel processing.

clear;
clc;
close all;

%% ------------------------------------------------------------------------
% Parameters: these values must match the RTL/UVM configuration.
% -------------------------------------------------------------------------
N            = 3;       % Kernel size: N x N
IMAGE_WIDTH  = 32;       % RTL image width
IMAGE_HEIGHT = 32;       % RTL image height
PIXEL_WIDTH  = 8;       % Unsigned grayscale pixel width
COEFF_WIDTH  = 8;       % Signed coefficient width (integer, fixed-point container)
OUT_BITS     = 16;      % Signed output width
RELU_ENABLE  = true;    % Must match the RTL ReLU enable
STRIDE       = 1;       % Convolution stride
NUM_KERNELS  = 1;       % Number of kernels / output channels per job

% --- Zero padding, derived automatically to match the RTL -----------------
PAD_ROWS_BEFORE = floor((N - 1) / 2);
PAD_ROWS_AFTER  = floor((N + 1) / 2);
PAD_COLS_BEFORE = 1;
PAD_COLS_AFTER  = 1;

% --- Fixed-point spec for the kernel -------------------------------------
FRAC_BITS = 4;

%% ------------------------------------------------------------------------
% File paths.
% -------------------------------------------------------------------------
source_image_path = 'input_image.jpg';
output_dir = '..\src\tb';

if ~isfile(source_image_path)
    % Create a dummy image for testing if the file doesn't exist
    warning('Input image not found. Creating a synthetic checkerboard pattern for testing.');
    source_image = uint8(checkerboard(1, IMAGE_HEIGHT, IMAGE_WIDTH) * 255);
else
    source_image = imread(source_image_path);
end

if ~isfolder(output_dir)
    mkdir(output_dir);
end

%% ------------------------------------------------------------------------
% Read and preprocess the source image.
% -------------------------------------------------------------------------
if ndims(source_image) == 3
    source_image = source_image(:,:,1:3);
    source_image = rgb2gray(source_image);
end

image_pixels = imresize(source_image, ...
                         [IMAGE_HEIGHT IMAGE_WIDTH], ...
                         'nearest');
image_pixels = uint8(image_pixels);

%% ------------------------------------------------------------------------
% Define the real-valued (floating-point) convolution kernels.
% -------------------------------------------------------------------------
% Kernel 0: Vertical Edge Detection
kernels(:,:,1) = [1 0 -1 ; 1 0 -1 ; 1 0 -1];

% Kernel 1: Horizontal Edge Detection (if NUM_KERNELS > 1)
if NUM_KERNELS > 1
    kernels(:,:,2) = 1/9 *[ ...
        1,  1,  1; ...
        1,  1,  1; ...
        1,  1,  1];

   kernels(:,:,3) =[ ...
        0 , -1 , 0; ...
       -1 , 5 , -1; ...
        0, -1 , 0];


end

% Add more kernel definitions here if NUM_KERNELS > 2

%% ------------------------------------------------------------------------
% Quantize the kernels into fixed-point COEFF_WIDTH-bit signed integers.
% -------------------------------------------------------------------------
coeff_max = 2^(COEFF_WIDTH-1) - 1;
coeff_min = -2^(COEFF_WIDTH-1);

quant_kernels_raw = round(kernels * 2^FRAC_BITS);

if any(quant_kernels_raw(:) > coeff_max) || any(quant_kernels_raw(:) < coeff_min)
    warning('One or more quantized kernel values overflow COEFF_WIDTH=%d.', COEFF_WIDTH);
end

quant_kernels = int32(min(max(quant_kernels_raw, coeff_min), coeff_max));

%% ------------------------------------------------------------------------
% Calculate padded-convolution output dimensions.
% -------------------------------------------------------------------------
OUTPUT_HEIGHT = IMAGE_HEIGHT ;
OUTPUT_WIDTH  = IMAGE_WIDTH  ;

% Expected output is now a 3D volume: [Height x Width x NUM_KERNELS]
expected = zeros(OUTPUT_HEIGHT, OUTPUT_WIDTH, NUM_KERNELS, 'int32');

%% ------------------------------------------------------------------------
% MATLAB golden convolution model (fixed-point).
% -------------------------------------------------------------------------
round_bias = int64(0);
if FRAC_BITS > 0
    round_bias = int64(bitshift(int64(1), FRAC_BITS-1)); % round-half-up
end

for k_idx = 1:NUM_KERNELS
    for out_row = 1:OUTPUT_HEIGHT
        for out_col = 1:OUTPUT_WIDTH

            accumulator = int64(0);

            for kernel_row = 1:N
                for kernel_col = 1:N

                    image_row = (out_row-1)*STRIDE + kernel_row - PAD_ROWS_BEFORE;
                    image_col = (out_col-1)*STRIDE + kernel_col - PAD_COLS_BEFORE;

                    if image_row < 1 || image_row > IMAGE_HEIGHT || ...
                       image_col < 1 || image_col > IMAGE_WIDTH
                        pixel_value = int64(0);
                    else
                        pixel_value = int64(image_pixels(image_row, image_col));
                    end

                    % Fetch the coefficient for the current kernel index
                    coefficient_value = int64(quant_kernels(kernel_row, kernel_col, k_idx));

                    accumulator = accumulator + ...
                        pixel_value * coefficient_value;
                end
            end

            if FRAC_BITS > 0
                accumulator = bitshift(accumulator + round_bias, -FRAC_BITS);
            end

            accumulator = int32(accumulator);

            if RELU_ENABLE && accumulator < 0
                accumulator = 0;
            end

            max_output = int32(2^(OUT_BITS-1) - 1);
            min_output = int32(-2^(OUT_BITS-1));

            accumulator = min(max(accumulator, min_output), max_output);
            expected(out_row, out_col, k_idx) = accumulator;
        end
    end
end

%% ------------------------------------------------------------------------
% Convert matrices to raster-scan vectors.
% -------------------------------------------------------------------------
input_stream = reshape(image_pixels.', [], 1);

% Flatten kernels back-to-back: kernel 0, then kernel 1, etc.
kernel_stream = [];
for k_idx = 1:NUM_KERNELS
    k_slice = quant_kernels(:,:,k_idx).'; 
    kernel_stream = [kernel_stream; k_slice(:)];
end

% Flatten expected outputs back-to-back per kernel pass
expected_stream = [];
for k_idx = 1:NUM_KERNELS
    e_slice = expected(:,:,k_idx).';
    expected_stream = [expected_stream; e_slice(:)];
end

%% ------------------------------------------------------------------------
% Write hexadecimal files.
% -------------------------------------------------------------------------
write_hex_file(fullfile(output_dir, 'pixel_input.hex'), input_stream, PIXEL_WIDTH);
write_hex_file(fullfile(output_dir, 'kernel_coeff.hex'), kernel_stream, COEFF_WIDTH);
write_hex_file(fullfile(output_dir, 'expected_output.hex'), expected_stream, OUT_BITS);

%% ------------------------------------------------------------------------
% Display information
% -------------------------------------------------------------------------
fprintf('\nGolden files generated successfully for %d kernel(s).\n', NUM_KERNELS);
fprintf('Input image size       : %d x %d\n', IMAGE_HEIGHT, IMAGE_WIDTH);
fprintf('Output volume size     : %d x %d x %d\n', OUTPUT_HEIGHT, OUTPUT_WIDTH, NUM_KERNELS);
fprintf('Kernel values generated: %d\n', length(kernel_stream));
fprintf('Expected outputs       : %d\n', length(expected_stream));

%% ------------------------------------------------------------------------
% Helper function for hexadecimal output
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