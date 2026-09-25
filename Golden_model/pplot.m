% Read hex data dynamically from file paths
dut_lines = readlines('../src/tb/dut_output.hex');
expected_lines = readlines('../src/tb/expected_output.hex');

% Clean whitespace and empty entries
dut_lines = strtrim(dut_lines(dut_lines ~= ""));
expected_lines = strtrim(expected_lines(expected_lines ~= ""));

% Convert hex to decimal
dut_data = hex2dec(dut_lines);
expected_data = hex2dec(expected_lines);

% Plot both series on top of each other
figure;
builtin('plot', dut_data, '-o', 'LineWidth', 1.5, 'DisplayName', 'DUT Output');
hold on;
builtin('plot', expected_data, '-s', 'LineWidth', 1.5, 'DisplayName', 'Expected Output');
hold off;

% Formatting
title('Comparison: DUT Output vs Expected Output');
xlabel('Sample Index');
ylabel('Value (Decimal)');
legend('Location', 'best');
grid on;