# ==============================================================================
# ModelSim / QuestaSim Compilation and Run Script (run.do) - Fixed Elaboration
# ==============================================================================

# 1. Create and map work library
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# 2. Define Base Paths
set SRC_PATH "D:/IEEE_SSCS/CNN_prjt/CNN_Accelerator/src"
set TB_PATH  "D:/IEEE_SSCS/CNN_prjt/CNN_Accelerator/testbench"

# Set UVM Paths
set UVM_12_PATH "$::env(MODEL_TECH)/../verilog_src/uvm-1.2"
set UVM_DPI_LIB "C:/questasim64_2021.1/uvm-1.2/win64/uvm_dpi"

# 3. Compile UVM 1.2 Package with Default Timescale
puts "\n--- Compiling UVM 1.2 Library ---"
vlog -work work -timescale "1ns/1ps" +incdir+$UVM_12_PATH/src $UVM_12_PATH/src/uvm_pkg.sv

# 4. Compile RTL Source Files with Global Timescale
puts "\n--- Compiling RTL Files ---"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/control/conv_fsm.v"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/control/pixel_counter.v"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/datapath/kernel_reg_bank.v"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/datapath/mac_chain.v"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/datapath/output_fifo.v"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/datapath/pixel_pad_inserter.v"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/datapath/row_buffer_bank.v"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/datapath/sat_round_unit.v"
vlog -work work -timescale "1ns/1ps" "$SRC_PATH/top/accelerator_top.v"

# 5. Compile Testbench Files
puts "\n--- Compiling Testbench Files ---"
vlog -work work -timescale "1ns/1ps" +incdir+$UVM_12_PATH/src +incdir+$TB_PATH "$TB_PATH/conv_pack.svh"
vlog -work work -timescale "1ns/1ps" +incdir+$UVM_12_PATH/src +incdir+$TB_PATH "$TB_PATH/conv_top.sv"

# 6. Elaborate & Load Simulation
# Using -voptargs="+acc" allows full waveform visibility without disabling the optimization engine
puts "\n--- Loading Simulation ---"
vsim -c -voptargs="+acc" -suppress 3009,12110 work.conv_top \
     -sv_lib $UVM_DPI_LIB \
     +UVM_TESTNAME=conv_test \
     +UVM_VERBOSITY=UVM_MEDIUM

# 7. Run Simulation
puts "\n--- Running Simulation ---"
run -all