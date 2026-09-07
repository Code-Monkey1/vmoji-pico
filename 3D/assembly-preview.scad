// Coil-safe dual-motor assembly preview (F5).
// Metal only below gears (608 + M8x16 SHCS journal). Plastic shaft through TX–RX gap.
// Base skirt contact is at -vm_skirt_h; SHCS head stays above the table.
//
// Animate: View → Animate. Start with FPS=30, Steps=180.
// $t runs 0→1; the rotor turns once per cycle, pinions twice (2:1) the other way.
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
show_display = true; // [true, false]
explode = 0; // [0:0.5:20]


/* [Hidden] */
$fa = 2;
$fs = 0.4;
$slop = 0.2;

vm_assert_coil_gap_metal_free();

motor_y = mb_gear_center_dist();
driven_a = vm_driven_spin($t);
pinion_a = vm_pinion_spin($t);


module _preview_bearing() {
    color("silver")
        difference() {
            cyl(d = mb_bearing_od(), h = mb_bearing_h(), anchor = BOTTOM);
            down(0.1)
                cyl(d = mb_bearing_id(), h = mb_bearing_h() + 0.2, anchor = BOTTOM);
        }
}


module _preview_journal() {
    // M8x16 SHCS: head + washer inside the skirt, shank through 608 into the shaft.
    head_h = vm_shcs_head_h;
    wash_h = vm_washer_h;
    color("lightsteelblue") {
        up(vm_bot_bearing_z0() - head_h - wash_h)
            cyl(d = vm_shcs_head_d, h = head_h, anchor = BOTTOM, $fn = 48);
        up(vm_bot_bearing_z0() - wash_h)
            cyl(d = vm_washer_od, h = wash_h, anchor = BOTTOM);
        up(vm_bot_bearing_z0())
            cyl(d = vm_journal_d - 0.05, h = vm_journal_len, anchor = BOTTOM);
    }
}


module _preview_motor() {
    color("dimgray")
        cyl(d = vm_motor_d, h = vm_motor_h, anchor = BOTTOM);
    color("gray")
        up(vm_motor_h)
            zrot(pinion_a)
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


// Approximate swept-volume top: horizontal 60×40 mm PCB + vertical 8×8 matrix
// in the XZ plane (Z up), facing +Y. Offset in Y so LEDs clear the shaft.
module _preview_display() {
    span = (vm_led_n - 1) * vm_led_pitch;
    face_y = -(vm_shaft_d / 2 + vm_led_h + 1);
    color("forestgreen")
        cuboid(
            [vm_display_pcb_x, vm_display_pcb_y, vm_display_pcb_t],
            anchor = BOTTOM,
            rounding = 1,
            edges = "Z"
        );
    // Thin carrier of the LED module, standing on the PCB.
    color("darkgreen")
        translate([0, face_y - 0.6, vm_display_pcb_t])
            cuboid(
                [span + vm_led_xy + 2, 1.2, span + vm_led_xy + 2],
                anchor = BOTTOM
            );
    color("red")
        for (col = [0:vm_led_n - 1], row = [0:vm_led_n - 1])
            translate([
                (col - (vm_led_n - 1) / 2) * vm_led_pitch,
                face_y,
                vm_display_pcb_t + vm_led_xy / 2 + row * vm_led_pitch
            ])
                cuboid([vm_led_xy, vm_led_h, vm_led_xy], anchor = CENTER);
    assert(span + vm_led_xy < vm_display_pcb_x - 2,
        "LED matrix does not fit on the preview PCB width");
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
                        zrot(pinion_a)
                            motor_pinion();
        }
    }

if (show_shaft)
    color("ivory", 0.9)
        up(vm_shaft_z0() + explode * 0.3)
            zrot(driven_a)
                driven_shaft();

if (show_gears)
    color("mediumseagreen")
        up(vm_gear_seat_z() + explode * 0.5)
            zrot(driven_a)
                driven_gear();

if (show_bearing)
    up(vm_bot_bearing_z0() - explode * 0.15)
        _preview_bearing();

if (show_journal)
    zrot(driven_a)
        _preview_journal();

if (show_coils) {
    up(vm_tx_ring_z() + explode * 0.55)
        _preview_coil(vm_ring_id, vm_ring_od, vm_ring_h);
    up(vm_rx_ring_z() + explode * 0.7)
        zrot(driven_a)
            _preview_coil(vm_ring_id, vm_ring_od, vm_ring_h);
}

if (show_collar)
    color("tomato")
        up(vm_collar_z() + explode)
            zrot(driven_a)
                shaft_collar();

if (show_display)
    up(vm_display_z() + explode)
        zrot(driven_a)
            _preview_display();
