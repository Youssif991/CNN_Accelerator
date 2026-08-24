# 1. Create an in-memory project
create_project -in_memory -part xczu3eg-sbva484-1-e

# 2. Read ALL Verilog files recursively
set verilog_files [glob -nocomplain "src/*.v" "src/**/*.v"]

if {[llength $verilog_files] > 0} {
    read_verilog $verilog_files
} else {
    error "ERROR: No Verilog files found in src/ or its subdirectories!"
}

# 3. Dynamic Elaboration
if { $argc > 0 } {
    set top_module [lindex $argv 0]
} else {
    set top_module "mux_bus"
}

puts "Elaborating design with top module: $top_module"
synth_design -top $top_module -rtl

# 4. Open the interactive schematic GUI
start_gui
