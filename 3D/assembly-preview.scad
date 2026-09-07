// Coil-safe dual-motor assembly preview (F5).
// Metal only below gears (608 + short journal). Plastic shaft through TX–RX gap.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>

use <motor-base.scad>
use <motor-base-lid.scad>
use <motor-tx-deck.scad>
use <motor-collet.scad>
use <motor-pinion.scad>
use <driven-gear.scad>
use <driven-shaft.scad>
use <shaft-collar.scad>


/* [Preview] */
show_base = true; // [true, false]
show_tx_deck = true; // [true, false]
show_lid = true; // [true, false]
show_motors = true; // [true, false]
show_gears = true; // [true, false]
show_shaft = true; // [true, false]
show_bearing = true; // [true, false]
show_journal = true; // [true, false]
show_coils = true; // [true, false]
show_collar = true; // [true, false]
explode = 0; // [0:0.5:20]


/* [Hidden] */
$fa = 2;
$fs = 0.4;
$slop = 0.2;

vm_assert_coil_gap_metal_free();

motor_y = mb_gear_center_dist();


module _preview_bearing() {
    color("silver")
        difference() {
            cyl(d = mb_bearing_od(), h = mb_bearing_h(), anchor = BOTTOM);
            down(0.1)
                cyl(d = mb_bearing_id(), h = mb_bearing_h() + 0.2, anchor = BOTTOM);
        }
}


module _preview_journal() {
    // Metal only in the bottom zone (must end below TX deck).
    color("lightsteelblue")
        up(vm_bot_bearing_z0() - 3)
            cyl(d = vm_journal_d - 0.05, h = vm_journal_len, anchor = BOTTOM);
}


module _preview_motor() {
    color("dimgray")
        cyl(d = vm_motor_d, h = vm_motor_h, anchor = BOTTOM);
    color("gray")
        up(vm_motor_h)
            cyl(d = vm_motor_shaft_d, h = vm_pinion_hub_h + vm_gear_thickness + 3, anchor = BOTTOM);
}


module _preview_coil(id, od, h) {
    color("goldenrod")
        difference() {
            cyl(d = od, h = h, anchor = BOTTOM);
            down(0.05)
                cyl(d = id, h = h + 0.1, anchor = BOTTOM);
        }
}


if (show_base)
    color("royalblue", 0.5)
        motor_base();

if (show_tx_deck)
    color("dodgerblue", 0.65)
        up(vm_tx_deck_z() + explode)
            motor_tx_deck();

if (show_lid)
    color("steelblue", 0.7)
        up(vm_floor_h + vm_porch_inner_z + explode)
            motor_base_lid();

if (show_motors)
    for (my = [motor_y, -motor_y]) {
        back(my) {
            color("orange", 0.85)
                down(explode)
                    motor_collet();
            up(explode * 0.2)
                _preview_motor();
            if (show_gears)
                color("seagreen")
                    up(vm_motor_h + explode * 0.4)
                        motor_pinion();
        }
    }

if (show_shaft)
    color("ivory", 0.9)
        up(vm_shaft_z0() + explode * 0.3)
            driven_shaft();

if (show_gears)
    color("mediumseagreen")
        up(vm_gear_seat_z() + explode * 0.5)
            driven_gear();

if (show_bearing)
    up(vm_bot_bearing_z0() - explode * 0.15)
        _preview_bearing();

if (show_journal)
    _preview_journal();

if (show_coils) {
    up(vm_tx_ring_z() + explode * 0.55)
        _preview_coil(vm_ring_id, vm_ring_od, vm_ring_h);
    up(vm_rx_ring_z() + explode * 0.7)
        _preview_coil(vm_ring_id, vm_ring_od, vm_ring_h);
}

if (show_collar)
    color("tomato")
        up(vm_collar_z() + explode)
            shaft_collar();
