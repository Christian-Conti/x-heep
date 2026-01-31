# Sourced by FuseSoC/Edalize during project setup
set here [file dirname [info script]]
set eco  [file normalize [file join $here "eco_spi_flash_mux.tcl"]]

# Attach ECO to implementation run (post opt_design)
set_property -name {STEPS.OPT_DESIGN.TCL.POST} -value $eco -objects [get_runs impl_1]
