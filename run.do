# ==============================================================================
# ModelSim / QuestaSim Compilation and Run Script (run.do) - UVM 1.2 Forced
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

# ------------------------------------------------------------------------------
# UVM 1.2 Setup
# Option A: Point to Questa's shipped UVM 1.2 package directory
# Adjust $MODEL_TECH/../verilog_src/uvm-1.2 to match your install directory if needed.
set UVM_12_PATH "$::env(MODEL_TECH)/../verilog_src/uvm-1.2"

# Compile UVM 1.2 source files explicitly
puts "\n--- Compiling UVM 1.2 Library ---"
vlog -work work +incdir+$UVM_12_PATH/src $UVM_12_PATH/src/uvm_pkg.sv
# ------------------------------------------------------------------------------

# 3. Compile RTL Source Files
puts "\n--- Compiling RTL Files ---"
vlog -work work "$SRC_PATH/control/conv_fsm.v"
vlog -work work "$SRC_PATH/control/pixel_counter.v"
vlog -work work "$SRC_PATH/datapath/adder_tree.v"
vlog -work work "$SRC_PATH/datapath/kernel_reg_bank.v"
vlog -work work "$SRC_PATH/datapath/line_buffer.v"
vlog -work work "$SRC_PATH/datapath/line_buffer_bank.v"
vlog -work work "$SRC_PATH/datapath/mac_array.v"
vlog -work work "$SRC_PATH/datapath/output_fifo.v"
vlog -work work "$SRC_PATH/datapath/sat_round_unit.v"
vlog -work work "$SRC_PATH/datapath/window_array.v"
vlog -work work "$SRC_PATH/multiplier/dsp_mult_r4.v"
vlog -work work "$SRC_PATH/top/accelerator_top.v"

# 4. Compile Testbench Files (Include UVM 1.2 source path)
puts "\n--- Compiling Testbench Files ---"
vlog -work work +incdir+$UVM_12_PATH/src +incdir+$TB_PATH "$TB_PATH/conv_pack.svh"
vlog -work work +incdir+$UVM_12_PATH/src +incdir+$TB_PATH "$TB_PATH/conv_top.sv"

# 5. Elaborate & Load Simulation (Explicitly link compiled UVM 1.2 dpi library)
puts "\n--- Loading Simulation with UVM 1.2 ---"
vsim -c -novopt -suppress 12110 work.conv_top \
     -sv_lib "$::env(MODEL_TECH)/uvm_dpi" \
     +UVM_TESTNAME=my_test \
     +UVM_VERBOSITY=UVM_MEDIUM

# 6. Add Signals to Wave
puts "\n--- Configuring Waves ---"
add wave -divider "System Signals"
add wave -hex /conv_top/clk_i
add wave -hex /conv_top/rst_n_i

add wave -divider "Interface Signals"
add wave -hex /conv_top/intf/start_i
add wave -hex /conv_top/intf/ready_o
add wave -hex /conv_top/intf/busy_o
add wave -hex /conv_top/intf/done_o
add wave -hex /conv_top/intf/state_o

add wave -divider "Input Data (Pixel & Kernel)"
add wave -hex /conv_top/intf/kernel_wr_valid_i
add wave -hex /conv_top/intf/kernel_wr_data_i
add wave -hex /conv_top/intf/pixel_valid_i
add wave -hex /conv_top/intf/pixel_in_i

add wave -divider "Output Stream"
add wave -hex /conv_top/intf/result_ready_i
add wave -hex /conv_top/intf/result_valid_o
add wave -hex /conv_top/intf/result_o
add wave -hex /conv_top/intf/result_tlast_o

# 7. Run Simulation
puts "\n--- Running Simulation ---"
run -all