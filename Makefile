# --- Configuration ---
# Leave these blank so they can be driven or overridden from the terminal
TB_FILE =
TOP     = 

# Safety Check: Only enforce TB_FILE if we are running the default simulation target
ifeq ($(MAKECMDGOALS),)
    ifeq ($(strip $(TB_FILE)),)
        $(error Error: You must specify a testbench file. Usage: make TB_FILE=tb/tb_Full_Adder.v)
    endif
endif

ifeq ($(MAKECMDGOALS),all)
    ifeq ($(strip $(TB_FILE)),)
        $(error Error: You must specify a testbench file. Usage: make TB_FILE=tb/tb_Full_Adder.v)
    endif
endif

# --- Targets ---

# Default target: Runs simulation via Tcl
all:
	vivado -mode tcl -source scripts/run_sim.tcl -tclargs $(TB_FILE)

# Elaborate target: Opens the RTL schematic view for the specified TOP module
elaborate:
	vivado -mode gui -source scripts/elaborate.tcl -tclargs $(TOP)

# Clean target to sweep away directory clutter
clean:
	@echo "Cleaning up simulation files..."
	rm -rf xsim.dir/ .Xil/
	rm -f xsim*.backup.log xsim*.backup.jou
	rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou vivado*.log vivado*.jou
