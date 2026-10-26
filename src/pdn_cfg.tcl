# Custom PDN for the RM_IHPSG13_1P_256x16_c2_bm_bist SRAM macro on IHP CMOS5L.
#
# Adapted (Apache-2.0) from 2AMLogic/sg13cmos5l-protocol-emulator src/pdn_cfg.tcl
# (https://github.com/2AMLogic/sg13cmos5l-protocol-emulator), which is itself
# based on LibreLane's default pdn_cfg.tcl. Changes: shortened comments, die
# notes for this project's 6x4 tile.
#
# Why not the urish/ttihp-sram-test recipe (macro grid Metal4 <-> TopMetal1):
# on CMOS5L the TT precheck forbids TopMetal1.drawing/pin (tt-support-tools
# precheck/tech_data.py, forbidden_layers), and the core grid's vertical layer
# is already Metal4. The macro's VDD!/VSS!/VDDARRAY! pins are vertical Metal4
# stripes (2.81 um wide, 11.24 um same-net pitch) and every other x over the
# macro is Metal4 OBS, so pdngen cannot place legal shapes over it. Instead:
#
# 1. Bridges: before pdngen runs, draw one special-net Metal4 STRIPE per macro
#    power-pin stripe, on that pin's net, coincident with the pin and extended
#    out of the macro edge(s) it touches to the core edge. VDD! touches the
#    bottom edge, VDDARRAY! the top edge (OBS band between them, LEF y
#    39.085..45.205), VSS! and four VDD! stripes are full height. pdngen keeps
#    these as fixed shapes and its Metal1 <-> Metal4 connect drops vias from
#    them onto the standard-cell rails.
# 2. The core strap lattice is re-pitched in config.json (FP_PDN_VPITCH 44.96 =
#    4 x 11.24, FP_PDN_VOFFSET 93.985) so no core strap overlaps an
#    opposite-net bridge, for the macro at (91.2, 173.88) N.
# 3. Power pins: TT precheck wants every VPWR/VGND LEF pin to span the die
#    height, but straps crossing the macro are split. So the two pins are made
#    directly on one strap pair right of the macro (x = 366.6 / 370.7 um),
#    which runs edge to edge.

proc pdn_bridge_draw {} {
    set block [ord::get_db_block]
    set m4 [[$block getTech] findLayer Metal4]
    set core [$block getCoreArea]
    set y0 [$core yMin]
    set y1 [$core yMax]
    set drawn 0
    array set seen {}
    foreach conn $::env(PDN_MACRO_CONNECTIONS) {
        set iname [lindex $conn 0]
        set inst [$block findInst $iname]
        if {$inst eq "NULL"} {
            puts stderr "pdn_bridge: instance '$iname' not found"
            exit 1
        }
        set iy0 [[$inst getBBox] yMin]
        set iy1 [[$inst getBBox] yMax]
        foreach iterm [$inst getITerms] {
            set sig [[$iterm getMTerm] getSigType]
            if {$sig ne "POWER" && $sig ne "GROUND"} { continue }
            set net [$iterm getNet]
            if {$net eq "NULL"} {
                puts stderr "pdn_bridge: [[$iterm getMTerm] getName] of $iname has no net"
                exit 1
            }
            foreach geom [$iterm getGeometries] {
                lassign $geom glayer r
                if {[$glayer getName] ne "Metal4"} { continue }
                set at_bottom [expr {abs([$r yMin] - $iy0) <= 1}]
                set at_top [expr {abs([$r yMax] - $iy1) <= 1}]
                if {!$at_bottom && !$at_top} {
                    puts stderr "pdn_bridge: stripe at x=[$r xMin] reaches no macro edge"
                    exit 1
                }
                set by0 [expr {$at_bottom ? $y0 : [$r yMin]}]
                set by1 [expr {$at_top ? $y1 : [$r yMax]}]
                set key "[$r xMin],[$r xMax],$by0,$by1"
                if {[info exists seen($key)]} { continue }
                set seen($key) 1
                odb::dbSBox_create [odb::dbSWire_create $net ROUTED] $m4 \
                    [$r xMin] $by0 [$r xMax] $by1 STRIPE
                incr drawn
            }
        }
    }
    puts "\[INFO\] pdn_bridge: drew $drawn Metal4 bridge stripes"
}

pdn_bridge_draw

# Standard-cell grid: LibreLane's default (PDN_MULTILAYER=0 path), without the
# default macro grid (the bridges replace it) and without -pins (see 3.).
source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

set secondary []
foreach vdd $::env(VDD_NETS) gnd $::env(GND_NETS) {
    if { $vdd != $::env(VDD_NET)} {
        lappend secondary $vdd
        set db_net [[ord::get_db_block] findNet $vdd]
        if {$db_net == "NULL"} {
            set net [odb::dbNet_create [ord::get_db_block] $vdd]
            $net setSpecial
            $net setSigType "POWER"
        }
    }
    if { $gnd != $::env(GND_NET)} {
        lappend secondary $gnd
        set db_net [[ord::get_db_block] findNet $gnd]
        if {$db_net == "NULL"} {
            set net [odb::dbNet_create [ord::get_db_block] $gnd]
            $net setSpecial
            $net setSigType "GROUND"
        }
    }
}

set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET) \
    -secondary_power $secondary

if { $::env(PDN_MULTILAYER) == 1 || $::env(PDN_CORE_RING) == 1 } {
    error "pdn_cfg: PDN_MULTILAYER / PDN_CORE_RING not supported (no TopMetal1 on CMOS5L TT)"
}

define_pdn_grid -name stdcell_grid -starts_with POWER -voltage_domain CORE

set extend []
if { $::env(PDN_EXTEND_TO) eq "core_ring" } {
    set extend -extend_to_core_ring
} elseif { $::env(PDN_EXTEND_TO) eq "boundary" } {
    set extend -extend_to_boundary
}

add_pdn_stripe \
    -grid stdcell_grid \
    -layer $::env(PDN_VERTICAL_LAYER) \
    -width $::env(PDN_VWIDTH) \
    -pitch $::env(PDN_VPITCH) \
    -offset $::env(PDN_VOFFSET) \
    -spacing $::env(PDN_VSPACING) \
    -starts_with POWER \
    {*}$extend

if { $::env(PDN_ENABLE_RAILS) == 1 } {
    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(PDN_RAIL_LAYER) \
        -width $::env(PDN_RAIL_WIDTH) \
        -followpins
    add_pdn_connect \
        -grid stdcell_grid \
        -layers "$::env(PDN_RAIL_LAYER) $::env(PDN_VERTICAL_LAYER)"
}

proc pdn_pins_create {} {
    set block [ord::get_db_block]
    set m4 [[$block getTech] findLayer Metal4]
    set dbu [$block getDbUnitsPerMicron]
    set die [$block getDieArea]
    set core [$block getCoreArea]
    # Strap pair 6 of the lattice: first strap right of the macro (x <= 328).
    set cx_vdd [expr {[$core xMin] + ($::env(PDN_VOFFSET) + 6 * $::env(PDN_VPITCH)) * $dbu}]
    set cx_vss [expr {$cx_vdd + ($::env(PDN_VWIDTH) + $::env(PDN_VSPACING)) * $dbu}]
    set halfw [expr {int($::env(PDN_VWIDTH) * $dbu / 2)}]
    foreach {net_name cx} [list $::env(VDD_NET) $cx_vdd $::env(GND_NET) $cx_vss] {
        set net [$block findNet $net_name]
        if {$net eq "NULL"} {
            puts stderr "pdn_pins: net '$net_name' not found"
            exit 1
        }
        set bterm [$net get1stBTerm]
        if {$bterm eq "NULL"} {
            set bterm [odb::dbBTerm_create $net $net_name]
            $bterm setIoType INOUT
            $bterm setSpecial
            $bterm setSigType [$net getSigType]
        }
        set bpin [odb::dbBPin_create $bterm]
        $bpin setPlacementStatus FIRM
        odb::dbBox_create $bpin $m4 [expr {int($cx) - $halfw}] [$die yMin] \
            [expr {int($cx) + $halfw}] [$die yMax]
        puts "\[INFO\] pdn_pins: $net_name pin at x=[expr {$cx / $dbu}] um"
    }
}

if { $::env(PDN_ENABLE_PINS) } {
    pdn_pins_create
}
