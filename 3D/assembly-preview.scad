// Non-printed assembly preview for the dual-motor offset gear drive.
// Open in OpenSCAD and press F5 (preview). Use F6 only if you need a full CGAL render.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <motor-base-common.scad>

use <motor-base.scad>
use <motor-base-lid.scad>
use <motor-tx-deck.scad>
use <motor-collet.scad>
use <motor-pinion.scad>
use <driven-gear.scad>
use <shaft-collar.scad>


/* [Preview] */
show_base = true; // [true, false]
show_tx_deck = true; // [true, false]
show_lid = true; // [true, false]
show_motors = true; // [true, false]
show_gears = true; // [true, false]
show_bearings = true; // [true, false]
show_coils = true; // [true, false]
show_collar = true; // [true, false]
explode = 0; // [0:0.5:20]


/* [Synced params] */
motor_d = 24;
motor_h = 12;
gear_mod = 1.25;
pinion_teeth = 14;
driven_teeth = 28;
gear_helical = 25;
gear_backlash = 0.3;
gear_thickness = 10;
pinion_hub_h = 3;
driven_hub_h = 6;
ring_id = 21.5;
ring_od = 41;
ring_h = 1.2;
shaft_d = 8;
floor_h = 5;
porch_inner_z = 32;


/* [Hidden] */
$fa = 2;
$fs = 0.4;
$slop = 0.2;


motor_y = mb_gear_center_dist(
    gear_mod, pinion_teeth, driven_teeth, gear_helical, gear_backlash
);
gear_z0 = motor_h + pinion_hub_h;
gear_z1 = gear_z0 + gear_thickness;
bot_bearing_z0 = gear_z0 - mb_bearing_h();
driven_hub_z1 = gear_z1 + driven_hub_h;
top_bearing_z0 = driven_hub_z1 + 0.5;
tx_deck_z = driven_hub_z1;
ring_z = tx_deck_z + mb_bearing_h() + 1.6 + 4 + 1.5;
collar_z = ring_z + ring_h + 2;


module _preview_bearing(h = mb_bearing_h()) {
    color("silver")
        difference() {
            cyl(d = mb_bearing_od(), h = h, anchor = BOTTOM);
            down(0.1)
                cyl(d = mb_bearing_id(), h = h + 0.2, anchor = BOTTOM);
        }
}


module _preview_motor() {
    color("dimgray")
        cyl(d = motor_d, h = motor_h, anchor = BOTTOM);
    color("gray")
        up(motor_h)
            cyl(d = 1.0, h = pinion_hub_h + gear_thickness + 4, anchor = BOTTOM);
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
    color("royalblue", 0.55)
        motor_base();

if (show_tx_deck)
    color("dodgerblue", 0.7)
        up(tx_deck_z + explode)
            motor_tx_deck();

if (show_lid)
    color("steelblue", 0.7)
        up(floor_h + porch_inner_z + explode)
            motor_base_lid();

if (show_motors)
    for (my = [motor_y, -motor_y]) {
        back(my) {
            color("orange", 0.85)
                down(explode)
                    motor_collet();
            up(explode * 0.25)
                _preview_motor();
            if (show_gears)
                color("seagreen")
                    up(motor_h + explode * 0.5)
                        motor_pinion();
        }
    }

if (show_gears)
    color("mediumseagreen")
        up(gear_z0 + explode)
            driven_gear();

if (show_bearings) {
    up(bot_bearing_z0 - explode * 0.2)
        _preview_bearing();
    up(top_bearing_z0 + explode * 0.3)
        _preview_bearing();
}

if (show_coils) {
    up(ring_z + explode * 0.4)
        _preview_coil(ring_id, ring_od, ring_h);
    up(collar_z + explode * 0.7)
        _preview_coil(ring_id + 1, ring_od - 1, ring_h);
}

if (show_collar)
    color("tomato")
        up(collar_z + explode)
            shaft_collar();

color("lightgray")
    down(2)
        cyl(d = shaft_d - 0.2, h = collar_z + 20, anchor = BOTTOM);
