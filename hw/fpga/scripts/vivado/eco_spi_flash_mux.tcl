# ECO script to multiplex SPI flash signals between PS and X-HEEP
# This should run AFTER opt_design in the implementation flow

set PORT_SCK {spi_flash_sck_o}
set PORT_CS  {spi_flash_csb_o}
set PORT_SD0 {spi_flash_sd_io[0]}
set PORT_SD1 {spi_flash_sd_io[1]}

proc must1 {lst what} {
  if {[llength $lst] == 0} { 
    error "ECO: cannot find $what"
  }
  return [lindex $lst 0]
}

# Find PS wrapper
set ps_wrapper [must1 [get_cells -quiet -hier -filter {NAME =~ "*xilinx_ps_wizard_wrapper_i"}] "PS wrapper"]

# Find PS SPI pins
set ps_sck_pin  [must1 [get_pins -quiet -hier -filter {NAME =~ "*xilinx_ps_wizard_wrapper_i/ps_spi_flash_sck_o"}] "PS SCK pin"]
set ps_cs_pin   [must1 [get_pins -quiet -hier -filter {NAME =~ "*xilinx_ps_wizard_wrapper_i/ps_spi_flash_cs_o*"}] "PS CS pin"]
set ps_mosi_pin [must1 [get_pins -quiet -hier -filter {NAME =~ "*xilinx_ps_wizard_wrapper_i/ps_spi_flash_mosi_o"}] "PS MOSI pin"]
set ps_miso_pin [must1 [get_pins -quiet -hier -filter {NAME =~ "*xilinx_ps_wizard_wrapper_i/xilinx_ps_wizard_i/ps_spi_flash_miso_i"}] "PS MISO pin"]

# Get PS SPI nets (for outputs only - MISO is handled differently)
set PS_SCK  [must1 [get_nets -quiet -of_objects $ps_sck_pin] "PS SCK net"]
set PS_CS   [must1 [get_nets -quiet -of_objects $ps_cs_pin] "PS CS net"]
set PS_MOSI [must1 [get_nets -quiet -of_objects $ps_mosi_pin] "PS MOSI net"]

# Find selection signal (ps_gpio_o[4])
set sel_pin_candidates [list]
lappend sel_pin_candidates [get_pins -quiet -hier -filter {NAME =~ "*xilinx_ps_wizard_wrapper_i/ps_gpio_o[4]"}]
lappend sel_pin_candidates [get_pins -quiet -hier -filter {NAME =~ "*xilinx_ps_wizard_wrapper_i/xilinx_ps_wizard_i/ps_gpio_o[4]"}]
lappend sel_pin_candidates [get_pins -quiet -hier -filter {NAME =~ "*axi_gpio*/gpio_io_o[4]"}]

set sel_pin ""
foreach candidate $sel_pin_candidates {
  if {[llength $candidate] > 0} {
    set sel_pin $candidate
    break
  }
}

if {$sel_pin == ""} {
  set sel_net_candidates [get_nets -quiet -hier -filter {NAME =~ "*ps_gpio_o*4*" || NAME =~ "*ps_x_heep_o*4*"}]
  set SEL [must1 $sel_net_candidates "SEL net"]
} else {
  set SEL [must1 [get_nets -of_objects $sel_pin] "SEL net"]
}

# Get port nets
set NET_SCK_PORT [must1 [get_nets -of_objects [get_ports $PORT_SCK]] "SCK port net"]
set NET_CS_PORT  [must1 [get_nets -of_objects [get_ports $PORT_CS]] "CS port net"]
set NET_SD0_PORT [must1 [get_nets -of_objects [get_ports $PORT_SD0]] "SD0 port net"]
set NET_SD1_PORT [must1 [get_nets -of_objects [get_ports $PORT_SD1]] "SD1 port net"]

# SD0 (MOSI) IOBUF modifications - Master Output, Slave Input
set SD0_IOBUF [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ "*pad_spi_flash_sd_0*"}]
if {[llength $SD0_IOBUF] == 0} {
  set SD0_IOBUF [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ "*spi_flash_sd*0*"}]
}
set SD0_IOBUF [must1 $SD0_IOBUF "SD0 IOBUF"]

# Reconnect IO pin to port
set SD0_PIN_IO     [must1 [get_pins -of_objects $SD0_IOBUF -filter {REF_PIN_NAME=="IO"}] "SD0 IO pin"]
set SD0_NET_IO_OLD [must1 [get_nets -of_objects $SD0_PIN_IO] "SD0 IO net"]
disconnect_net -net $SD0_NET_IO_OLD -objects $SD0_PIN_IO
connect_net -hier -net $NET_SD0_PORT -objects [list $SD0_PIN_IO]

# Mux the I pin (data to pad): sel ? PS_MOSI : XHEEP_MOSI
set SD0_PIN_I     [must1 [get_pins -of_objects $SD0_IOBUF -filter {REF_PIN_NAME=="I"}] "SD0 I pin"]
set SD0_NET_I_OLD [must1 [get_nets -of_objects $SD0_PIN_I] "SD0 I net"]
disconnect_net -net $SD0_NET_I_OLD -objects $SD0_PIN_I

create_net SD0_ECO_I
create_cell -reference LUT3 SD0_LUTI
set_property INIT 8'hCA [get_cells SD0_LUTI]
connect_net -hier -net $SD0_NET_I_OLD -objects [list [get_pins SD0_LUTI/I0]]
connect_net -hier -net $PS_MOSI       -objects [list [get_pins SD0_LUTI/I1]]
connect_net -hier -net $SEL           -objects [list [get_pins SD0_LUTI/I2]]
connect_net -hier -net SD0_ECO_I      -objects [list [get_pins SD0_LUTI/O] $SD0_PIN_I]

# Mux the T pin (tristate control): sel ? 0 (drive) : XHEEP_T
set SD0_PIN_T     [must1 [get_pins -of_objects $SD0_IOBUF -filter {REF_PIN_NAME=="T"}] "SD0 T pin"]
set SD0_NET_T_OLD [must1 [get_nets -of_objects $SD0_PIN_T] "SD0 T net"]
disconnect_net -net $SD0_NET_T_OLD -objects $SD0_PIN_T

create_net SD0_ECO_T
create_cell -reference LUT2 SD0_LUTT
set_property INIT 4'h8 [get_cells SD0_LUTT]
connect_net -hier -net $SD0_NET_T_OLD -objects [list [get_pins SD0_LUTT/I0]]
connect_net -hier -net $SEL           -objects [list [get_pins SD0_LUTT/I1]]
connect_net -hier -net SD0_ECO_T      -objects [list [get_pins SD0_LUTT/O] $SD0_PIN_T]

# SD1 (MISO) IOBUF modifications - Master Input, Slave Output
set SD1_IOBUF [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ "*pad_spi_flash_sd_1*"}]
if {[llength $SD1_IOBUF] == 0} {
  set SD1_IOBUF [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ "*spi_flash_sd*1*"}]
}
set SD1_IOBUF [must1 $SD1_IOBUF "SD1 IOBUF"]

# Reconnect IO pin to port
set SD1_PIN_IO     [must1 [get_pins -of_objects $SD1_IOBUF -filter {REF_PIN_NAME=="IO"}] "SD1 IO pin"]
set SD1_NET_IO_OLD [must1 [get_nets -of_objects $SD1_PIN_IO] "SD1 IO net"]
disconnect_net -net $SD1_NET_IO_OLD -objects $SD1_PIN_IO
connect_net -hier -net $NET_SD1_PORT -objects [list $SD1_PIN_IO]

# Get the O pin (data from pad) - this is the MISO signal from flash
set SD1_PIN_O     [must1 [get_pins -of_objects $SD1_IOBUF -filter {REF_PIN_NAME=="O"}] "SD1 O pin"]
set SD1_NET_O_OLD [must1 [get_nets -of_objects $SD1_PIN_O] "SD1 O net (XHEEP MISO)"]

# Disconnect the old MISO net and connect to PS MISO input
# The O pin will now drive both X-HEEP's MISO receiver and PS MISO input
connect_net -hier -net $SD1_NET_O_OLD -objects [list $ps_miso_pin]

# SD1 tristate: Both PS and X-HEEP want this as input (tristated)
# No need to modify T pin - flash drives this line

# SCK IOBUF modifications
set SCK_IOBUF [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ "*pad_spi_flash_sck*"}]
if {[llength $SCK_IOBUF] == 0} {
  set SCK_IOBUF [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ "*spi_flash_sck*"}]
}
set SCK_IOBUF [must1 $SCK_IOBUF "SCK IOBUF"]

# Reconnect IO pin to port
set SCK_PIN_IO     [must1 [get_pins -of_objects $SCK_IOBUF -filter {REF_PIN_NAME=="IO"}] "SCK IO pin"]
set SCK_NET_IO_OLD [must1 [get_nets -of_objects $SCK_PIN_IO] "SCK IO net"]
disconnect_net -net $SCK_NET_IO_OLD -objects $SCK_PIN_IO
connect_net -hier -net $NET_SCK_PORT -objects [list $SCK_PIN_IO]

# Mux the I pin: sel ? PS_SCK : XHEEP_SCK
set SCK_PIN_I     [must1 [get_pins -of_objects $SCK_IOBUF -filter {REF_PIN_NAME=="I"}] "SCK I pin"]
set SCK_NET_I_OLD [must1 [get_nets -of_objects $SCK_PIN_I] "SCK I net"]
disconnect_net -net $SCK_NET_I_OLD -objects $SCK_PIN_I

create_net SCK_ECO_I
create_cell -reference LUT3 SCK_LUTI
set_property INIT 8'hCA [get_cells SCK_LUTI]
connect_net -hier -net $SCK_NET_I_OLD -objects [list [get_pins SCK_LUTI/I0]]
connect_net -hier -net $PS_SCK        -objects [list [get_pins SCK_LUTI/I1]]
connect_net -hier -net $SEL           -objects [list [get_pins SCK_LUTI/I2]]
connect_net -hier -net SCK_ECO_I      -objects [list [get_pins SCK_LUTI/O] $SCK_PIN_I]

# Mux the T pin: sel ? 0 (drive) : XHEEP_T
set SCK_PIN_T     [must1 [get_pins -of_objects $SCK_IOBUF -filter {REF_PIN_NAME=="T"}] "SCK T pin"]
set SCK_NET_T_OLD [must1 [get_nets -of_objects $SCK_PIN_T] "SCK T net"]
disconnect_net -net $SCK_NET_T_OLD -objects $SCK_PIN_T

create_net SCK_ECO_T
create_cell -reference LUT2 SCK_LUTT
set_property INIT 4'h8 [get_cells SCK_LUTT]
connect_net -hier -net $SCK_NET_T_OLD -objects [list [get_pins SCK_LUTT/I0]]
connect_net -hier -net $SEL           -objects [list [get_pins SCK_LUTT/I1]]
connect_net -hier -net SCK_ECO_T      -objects [list [get_pins SCK_LUTT/O] $SCK_PIN_T]

# CS IOBUF modifications
set CS_IOBUF [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ "*pad_spi_flash_cs*"}]
if {[llength $CS_IOBUF] == 0} {
  set CS_IOBUF [get_cells -hier -filter {REF_NAME == IOBUF && NAME =~ "*spi_flash_csb*"}]
}
set CS_IOBUF [must1 $CS_IOBUF "CS IOBUF"]

# Reconnect IO pin to port
set CS_PIN_IO     [must1 [get_pins -of_objects $CS_IOBUF -filter {REF_PIN_NAME=="IO"}] "CS IO pin"]
set CS_NET_IO_OLD [must1 [get_nets -of_objects $CS_PIN_IO] "CS IO net"]
disconnect_net -net $CS_NET_IO_OLD -objects $CS_PIN_IO
connect_net -hier -net $NET_CS_PORT -objects [list $CS_PIN_IO]

# Mux the I pin: sel ? PS_CS : XHEEP_CS
set CS_PIN_I     [must1 [get_pins -of_objects $CS_IOBUF -filter {REF_PIN_NAME=="I"}] "CS I pin"]
set CS_NET_I_OLD [must1 [get_nets -of_objects $CS_PIN_I] "CS I net"]
disconnect_net -net $CS_NET_I_OLD -objects $CS_PIN_I

create_net CS_ECO_I
create_cell -reference LUT3 CS_LUTI
set_property INIT 8'hCA [get_cells CS_LUTI]
connect_net -hier -net $CS_NET_I_OLD -objects [list [get_pins CS_LUTI/I0]]
connect_net -hier -net $PS_CS        -objects [list [get_pins CS_LUTI/I1]]
connect_net -hier -net $SEL          -objects [list [get_pins CS_LUTI/I2]]
connect_net -hier -net CS_ECO_I      -objects [list [get_pins CS_LUTI/O] $CS_PIN_I]

# Mux the T pin: sel ? 0 (drive) : XHEEP_T
set CS_PIN_T     [must1 [get_pins -of_objects $CS_IOBUF -filter {REF_PIN_NAME=="T"}] "CS T pin"]
set CS_NET_T_OLD [must1 [get_nets -of_objects $CS_PIN_T] "CS T net"]
disconnect_net -net $CS_NET_T_OLD -objects $CS_PIN_T

create_net CS_ECO_T
create_cell -reference LUT2 CS_LUTT
set_property INIT 4'h8 [get_cells CS_LUTT]
connect_net -hier -net $CS_NET_T_OLD -objects [list [get_pins CS_LUTT/I0]]
connect_net -hier -net $SEL          -objects [list [get_pins CS_LUTT/I1]]
connect_net -hier -net CS_ECO_T      -objects [list [get_pins CS_LUTT/O] $CS_PIN_T]