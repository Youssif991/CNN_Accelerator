# run_power_sim.tcl - Batch xsim run of tb_accelerator_top with SAIF dump
# Produces synth_out/activity.saif for the Vivado power report.
# Usage: vivado -mode batch -source scripts/run_power_sim.tcl

set TB_FILE src/tb/tb_accelerator_top.v
set TOP_TB tb_accelerator_top
set SNAPSHOT "${TOP_TB}_snapshot"

# --- Collect design files (excluding testbenches) ---
set all_design_files [glob -nocomplain "src/*.v" "src/**/*.v"]
set design_files {}
foreach f $all_design_files {
    if {[string match "src/tb/*" $f]} {
        continue
    }
    lappend design_files $f
}

# --- 1. Compile Verilog files ---
puts "--> 1. Parsing Verilog Files..."
exec xvlog {*}$design_files $TB_FILE

# --- 2. Set LIBRARY_PATH to help the linker find crt1.o/crti.o ---
puts "--> 2. Setting up library path for linker..."
set crt_path [exec find /usr/lib -name crt1.o -print -quit 2>/dev/null]
if {$crt_path ne ""} {
    set crt_dir [file dirname $crt_path]
    if {[info exists ::env(LIBRARY_PATH)]} {
        set ::env(LIBRARY_PATH) "$crt_dir:$::env(LIBRARY_PATH)"
    } else {
        set ::env(LIBRARY_PATH) $crt_dir
    }
    puts "    LIBRARY_PATH = $::env(LIBRARY_PATH)"
}

# --- 3. Elaborate ---
puts "--> 3. Elaborating Design..."
exec xelab -debug typical -snapshot $SNAPSHOT "work.$TOP_TB"

# --- 4. Run in batch, logging SAIF switching activity for the DUT scope ---
puts "--> 4. Running simulation with SAIF logging..."
set saif_script /tmp/saif_run.tcl
set fh [open $saif_script w]
puts $fh "open_saif synth_out/activity.saif"
puts $fh "current_scope tb_accelerator_top/dut"
puts $fh "log_saif \[get_objects -r *\]"
puts $fh "run all"
puts $fh "close_saif"
puts $fh "quit"
close $fh
exec xsim $SNAPSHOT -t $saif_script

puts "--> 5. SAIF written to synth_out/activity.saif"
exit
