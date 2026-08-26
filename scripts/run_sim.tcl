# run_sim.tcl - Simulation script for Vivado
if {[llength $argv] == 0} {
    puts "Error: No testbench file specified."
    puts "Usage: vivado -mode tcl -source run_sim.tcl -tclargs <testbench_name_or_path>"
    exit 1
}

set TB_ARG [lindex $argv 0]

# --- Resolve TB_ARG to an actual file path ---
if {[string first "/" $TB_ARG] >= 0} {
    set TB_FILE $TB_ARG
} else {
    set bare_name [file rootname $TB_ARG]
    # Search in src/tb/ and its subdirectories
    set matches [glob -nocomplain "src/tb/*/${bare_name}.v" "src/tb/${bare_name}.v"]

    if {[llength $matches] == 0} {
        puts "Error: Could not find a testbench matching '$TB_ARG' under src/tb/"
        exit 1
    }

    set TB_FILE [lindex $matches 0]
}

set TOP_TB [file rootname [file tail $TB_FILE]]
set SNAPSHOT "${TOP_TB}_snapshot"

puts " Target Testbench: $TOP_TB"

# --- Collect design files (excluding testbenches) ---
set all_design_files [glob -nocomplain "src/*.v" "src/**/*.v"]
set design_files {}
foreach f $all_design_files {
    # Exclude any file under src/tb/ and also the explicit testbench file
    if {[string match "src/tb/*" $f] || $f eq $TB_FILE} {
        continue
    }
    lappend design_files $f
}

# --- 1. Compile Verilog files ---
puts "--> 1. Parsing Verilog Files..."
exec xvlog {*}$design_files $TB_FILE

# --- 2. Set LIBRARY_PATH to help the linker find crt1.o/crti.o ---
#     This is needed on some systems where Vivado's xelab fails to locate
#     the standard C runtime startup files.
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
} else {
    puts "    Warning: crt1.o not found. Linking may fail."
    # Fallback to a typical path (adjust if needed)
    if {[file exists "/usr/lib/x86_64-linux-gnu/crt1.o"]} {
        set ::env(LIBRARY_PATH) "/usr/lib/x86_64-linux-gnu"
        puts "    Using fallback: /usr/lib/x86_64-linux-gnu"
    }
}

# --- 3. Elaborate the design ---
puts "--> 3. Elaborating Design..."
exec xelab -debug typical -snapshot $SNAPSHOT "work.$TOP_TB"

# --- 4. Launch simulation with waveform viewer ---
puts "--> 4. Launching Vivado Waveform Viewer..."
exec xsim $SNAPSHOT -gui &

exit