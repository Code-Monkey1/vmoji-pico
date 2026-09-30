// World placement of every part + hardware ghost (shared by assembly-preview.scad and
// collision-check.scad, so both always agree). Include after BOSL2, params and common.
// Rotating parts take the rotor angle `a` (degrees, world Z).

use <motor-base.scad>
use <motor-base-lid.scad>
use <motor-tx-deck.scad>
use <motor-pinion.scad>
use <rotor-shaft.scad>
use <rotor-head.scad>
use <bearing-spacer.scad>


function asm_motor_ys() = [mb_gear_center_dist(), -mb_gear_center_dist()];
// Pinion angle for a rotor angle `a`, phased so the teeth mesh (half-tooth offset).
function asm_pinion_angle(a) =
    -a * vm_gear_ratio() + 180 / vm_pinion_teeth;

module asm_base() motor_base();
module asm_lid() up(vm_porch_top_z()) motor_base_lid();
module asm_deck() up(vm_deck_z()) motor_tx_deck();

module asm_motor(my, d = vm_motor_d, shaft_d = 2) {
    translate([0, my, vm_motor_z0()]) {
        cyl(d = d, h = vm_motor_h, anchor = BOTTOM);
        up(vm_motor_h - 0.01) cyl(d = vm_motor_boss_d, h = vm_motor_boss_h, anchor = BOTTOM);
        up(vm_motor_h - 0.01) cyl(d = shaft_d, h = vm_motor_shaft_len, anchor = BOTTOM);
    }
}

module asm_pinion(my, a = 0) {
    translate([0, my, vm_gear_z0()])
        zrot(asm_pinion_angle(a))
            motor_pinion();
}

module asm_rotor_shaft(a = 0) up(vm_rotor_z0()) zrot(a) rotor_shaft();
module asm_head(a = 0) up(vm_head_z()) zrot(a) rotor_head();

module asm_bearing(z0) {
    up(z0)
        difference() {
            cyl(d = vm_bearing_od, h = vm_bearing_h, anchor = BOTTOM);
            down(0.1) cyl(d = vm_bearing_id, h = vm_bearing_h + 0.2, anchor = BOTTOM);
        }
}
module asm_bearing_bottom() asm_bearing(vm_bot_bearing_z0());
module asm_bearing_top() asm_bearing(vm_top_bearing_z0());

// M8x25 SHCS + 2 race spacers + M8 nut; turns with the bottom inner race and the rotor.
module asm_stud(a = 0) {
    zrot(a) {
        up(vm_shcs_head_z0()) cyl(d = vm_shcs_head_d, h = vm_shcs_head_h, anchor = BOTTOM);
        up(vm_shcs_head_z1() - 0.01) cyl(d = vm_shcs_d - 0.05, h = vm_shcs_len + 0.01, anchor = BOTTOM);
        up(vm_shcs_head_z1()) bearing_spacer();
        up(vm_bot_bearing_z1()) bearing_spacer();
        up(vm_nut_z0())
            difference() {
                cyl(d = mb_hex_circum_d(vm_nut_af), h = vm_nut_h, anchor = BOTTOM, $fn = 6);
                down(0.1) cyl(d = vm_shcs_d, h = vm_nut_h + 0.2, anchor = BOTTOM);
            }
    }
}

module asm_coil(z0) {
    up(z0)
        difference() {
            cyl(d = vm_ring_od, h = vm_ring_h, anchor = BOTTOM);
            down(0.05) cyl(d = vm_ring_id, h = vm_ring_h + 0.1, anchor = BOTTOM);
        }
}
module asm_tx_coil() asm_coil(vm_tx_ring_z());
module asm_rx_coil(a = 0) zrot(a) asm_coil(vm_rx_ring_z());

// 5 mm (or 3 mm) IR part: flange at the base, body, dome tip at `tip_z`, pointing `dir`.
module _ir_part(tip_z, dir) {
    body = vm_ir_len - vm_ir_flange_h;
    up(tip_z)
        if (dir > 0) {
            down(body) cyl(d = vm_ir_d, h = body - vm_ir_d / 2, anchor = BOTTOM);
            down(vm_ir_d / 2) spheroid(d = vm_ir_d, $fn = 24);
            down(body + vm_ir_flange_h) cyl(d = vm_ir_flange_d, h = vm_ir_flange_h, anchor = BOTTOM);
        } else {
            up(vm_ir_d / 2) cyl(d = vm_ir_d, h = body - vm_ir_d / 2, anchor = BOTTOM);
            up(vm_ir_d / 2) spheroid(d = vm_ir_d, $fn = 24);
            up(body) cyl(d = vm_ir_flange_d, h = vm_ir_flange_h, anchor = BOTTOM);
        }
}
module asm_ir_emitter() {
    xy = mb_ir_xy();
    translate([xy.x, xy.y, 0]) _ir_part(vm_ir_tx_tip_z(), 1);
}
module asm_ir_receiver(a = 0) {
    xy = mb_ir_xy();
    zrot(a) translate([xy.x, xy.y, 0]) _ir_part(vm_ir_rx_tip_z(), -1);
}

// Approximate top: horizontal 60×40 mm PCB + vertical 8×8 matrix in the XZ plane (Z up),
// facing +Y, offset in Y so the LEDs clear the center screw.
module asm_display(a = 0, colored = false) {
    span = (vm_led_n - 1) * vm_led_pitch;
    face_y = -(vm_head_hub_d / 2 + vm_led_h + 1);
    zrot(a) up(vm_pcb_z()) {
        color(colored ? "forestgreen" : undef)
            difference() {
                cuboid(
                    [vm_display_pcb_x, vm_display_pcb_y, vm_display_pcb_t],
                    anchor = BOTTOM,
                    rounding = vm_pcb_corner_r,
                    edges = "Z"
                );
                for (sx = [1, -1], sy = [1, -1])
                    translate([sx * vm_pcb_hole_dx / 2, sy * vm_pcb_hole_dy / 2, -0.1])
                        cyl(d = 3.2, h = vm_display_pcb_t + 0.2, anchor = BOTTOM);
            }
        // Thin carrier of the LED module, standing on the PCB.
        color(colored ? "darkgreen" : undef)
            translate([0, face_y - 0.6, vm_display_pcb_t])
                cuboid(
                    [span + vm_led_xy + 2, 1.2, span + vm_led_xy + 2],
                    anchor = BOTTOM
                );
        color(colored ? "red" : undef)
            for (col = [0:vm_led_n - 1], row = [0:vm_led_n - 1])
                translate([
                    (col - (vm_led_n - 1) / 2) * vm_led_pitch,
                    face_y,
                    vm_display_pcb_t + vm_led_xy / 2 + row * vm_led_pitch
                ])
                    cuboid([vm_led_xy, vm_led_h, vm_led_xy], anchor = CENTER);
    }
    assert(span + vm_led_xy < vm_display_pcb_x - 2,
        "LED matrix does not fit on the preview PCB width");
}

// Swept volume of the display over a full turn.
module asm_display_envelope() {
    span = (vm_led_n - 1) * vm_led_pitch;
    up(vm_pcb_z())
        cyl(r = mb_head_sweep_r(), h = vm_display_pcb_t + span + vm_led_xy + 2, anchor = BOTTOM);
}

// Swept ring of the IR receiver.
module asm_ir_receiver_envelope() {
    z0 = vm_ir_rx_tip_z();
    h = vm_ir_len;
    up(z0)
        difference() {
            cyl(r = vm_ir_r + vm_ir_flange_d / 2, h = h, anchor = BOTTOM);
            down(0.1) cyl(r = vm_ir_r - vm_ir_flange_d / 2, h = h + 0.2, anchor = BOTTOM);
        }
}
