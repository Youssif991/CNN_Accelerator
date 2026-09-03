# run_synth.tcl - Synthesis and implementation of accelerator_top on PYNQ-Z2
# Usage: vivado -mode batch -source scripts/run_synth.tcl
# Outputs: synth_out/ (utilization, timing, power reports + routed DCP)

set top accelerator_top
set part xc7z020clg400-1
set out_dir synth_out
file mkdir $out_dir

# --- Collect RTL sources (excluding testbenches) ---
set all_files [glob -nocomplain "src/*.v" "src/**/*.v"]
set rtl_files {}
foreach f $all_files {
    if {[string match "src/tb/*" $f]} {
        continue
    }
    lappend rtl_files $f
}
puts "--> Reading RTL sources: $rtl_files"
read_verilog $rtl_files
read_xdc src/constraints/pynq_z2.xdc

# --- Synthesize ---
puts "--> Synthesizing $top on $part"
synth_design -top $top -part $part

# --- Optimize, place, route ---
puts "--> Optimizing and placing"
opt_design
place_design
puts "--> Routing"
route_design

# --- Reports ---
puts "--> Writing reports"
report_utilization -hierarchical -file $out_dir/utilization.rpt
report_timing_summary -file $out_dir/timing_summary.rpt
report_timing -max_paths 5 -file $out_dir/timing_worst.rpt

# Annotate switching activity from the end-to-end simulation, if available
if {[file exists synth_out/activity.saif]} {
    puts "--> Annotating switching activity (synth_out/activity.saif)"
    read_saif synth_out/activity.saif -strip_path tb_accelerator_top/dut
    # The RTL-scope SAIF cannot map this post-optimization net name; shift_valid
    # (state_o_OBUF[1]) is high during FILL+COMPUTE (~99% of a frame) and
    # toggles twice per frame, so replace the vector-less default (0/0). The net
    # name depends on how the FSM output is optimized, so this is best-effort.
    set saif_nets [get_nets -quiet u_fsm/state_o_OBUF[1]]
    if {[llength $saif_nets] > 0} {
        set_switching_activity -toggle_rate 0.002 -static_probability 0.99 $saif_nets
    } else {
        puts "    NOTE: net u_fsm/state_o_OBUF[1] not found post-route; SAIF used as-is"
    }
}
report_power -file $out_dir/power.rpt
report_clock_utilization -file $out_dir/clock_util.rpt
write_checkpoint -force $out_dir/${top}_routed.dcp

# --- Key numbers to stdout ---
puts "=================================================================="
puts " UTILIZATION"
puts "=================================================================="
report_utilization
puts "=================================================================="
puts " TIMING SUMMARY"
puts "=================================================================="
report_timing_summary -max_paths 5
puts "=================================================================="
puts " POWER"
puts "=================================================================="
report_power

puts "--> SYNTHESIS DONE"
exit
