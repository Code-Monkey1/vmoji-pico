// Collision checks: each `check` renders the intersection of two assembled parts (or a
// part and a soldering-iron access cylinder). An empty / zero-volume result = OK.
// Run them all with ./check-collisions.sh (it measures the volume of each result).
// Spinning parts are checked with their swept envelopes (motor-base-common.scad), so a
// pass holds for every rotor angle. The gear mesh itself is reported separately ("mesh").
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>
include <vmoji-assembly.scad>


check = "base_deck";


/* [Hidden] */
$fa = 4;
$fs = 0.5;
$slop = 0.2;

vm_assert_layout();

// Motor ghost at the rib tips and inside the pinion bore: both press fits are intentional
// interference, everything else must clear.
module _motors_check()
    for (my = asm_motor_ys())
        asm_motor(my, d = 2 * mb_rib_inner_r() - 0.05, shaft_d = vm_motor_shaft_d - 0.05);
module _pinions_env() for (my = asm_motor_ys()) back(my) mb_pinion_envelope();
module _rotor_env() { mb_rotor_shaft_envelope(); mb_rotor_head_envelope(); asm_display_envelope(); }

module _iron_cols() {
    for (c = mb_layout_get(mb_layout(), "col_coords"))
        translate([c.x, c.y, vm_col_top_z() + vm_locate_h]) mb_iron_clearance();
}
module _iron_posts() {
    for (p = mb_post_coords()) translate([p.x, p.y, vm_porch_top_z()]) mb_iron_clearance();
}
module _iron_head() {
    for (sx = [1, -1], sy = [1, -1])
        translate([sx * vm_pcb_hole_dx / 2, sy * vm_pcb_hole_dy / 2, vm_head_z() + vm_head_pcb_z()])
            mb_iron_clearance();
}

module run_check(name) {
    if (name == "base_deck") intersection() { asm_base(); asm_deck(); }
    else if (name == "base_lid") intersection() { asm_base(); asm_lid(); }
    else if (name == "deck_lid") intersection() { asm_deck(); asm_lid(); }
    else if (name == "base_motors") intersection() { asm_base(); _motors_check(); }
    else if (name == "base_pinions") intersection() { asm_base(); _pinions_env(); }
    else if (name == "base_rotor") intersection() { asm_base(); _rotor_env(); }
    else if (name == "deck_rotor") intersection() { asm_deck(); _rotor_env(); }
    else if (name == "deck_pinions") intersection() { asm_deck(); _pinions_env(); }
    else if (name == "lid_rotor") intersection() { asm_lid(); _rotor_env(); }
    else if (name == "motors_rotor") intersection() { _motors_check(); _rotor_env(); }
    else if (name == "motors_pinions") intersection() { _motors_check(); for (my = asm_motor_ys()) asm_pinion(my); }
    else if (name == "bearings_base") intersection() { asm_base(); asm_bearing_bottom(); }
    else if (name == "bearings_deck") intersection() { asm_deck(); asm_bearing_top(); }
    else if (name == "bearings_rotor") intersection() { asm_rotor_shaft(); union() { asm_bearing_bottom(); asm_bearing_top(); } }
    else if (name == "stud_rotor") intersection() { asm_rotor_shaft(); asm_stud(); }
    else if (name == "stud_base") intersection() { asm_base(); asm_stud(); }
    else if (name == "stud_deck") intersection() { asm_deck(); asm_stud(); }
    else if (name == "head_rotor") intersection() { asm_head(); asm_rotor_shaft(); }
    else if (name == "coils") intersection() { union() { asm_deck(); asm_head(); } union() { asm_tx_coil(); asm_rx_coil(); } }
    else if (name == "ir_parts") intersection() { union() { asm_deck(); asm_head(); } union() { asm_ir_emitter(); asm_ir_receiver(); } }
    else if (name == "ir_sweep") intersection() { asm_ir_emitter(); asm_ir_receiver_envelope(); }
    else if (name == "iron_columns") intersection() { asm_base(); _iron_cols(); }
    else if (name == "iron_posts") intersection() { asm_base(); _iron_posts(); }
    else if (name == "iron_head") intersection() { asm_head(); _iron_head(); }
    // Informational: tooth overlap of the phased pinions with the rotor gear at angle 0.
    else if (name == "mesh") intersection() { asm_rotor_shaft(); for (my = asm_motor_ys()) asm_pinion(my); }
    else assert(false, str("Unknown check: ", name));
}


run_check(check);
