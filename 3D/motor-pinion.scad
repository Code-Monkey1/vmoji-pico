// Motor pinion — single helical, plain press-fit on the Ø2 motor shaft (no slit clamp).
// Blind bore: the shaft is only ~4–5 mm long; the gear sits vm_pinion_face_gap above the
// motor face (press down onto a shim of that thickness). Underside relieved for the motor
// boss. Print underside down. If a pinion ever slips, a drop of CA glue fixes it.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Press-fit] */
// Bore extra depth past the shaft tip (shaft must not bottom out).
bore_extra_depth = 0.4; // [0:0.1:2]
boss_relief_extra = 0.6; // [0:0.1:2]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_pinion(
    shaft_d = vm_motor_shaft_d,
    shaft_len = vm_motor_shaft_len,
    face_gap = vm_pinion_face_gap,
    gear_thickness = vm_gear_thickness,
    bore_extra_depth = bore_extra_depth,
    boss_relief_extra = boss_relief_extra
) {
    eps = cut_overlap;
    bore_depth = shaft_len - face_gap + bore_extra_depth;
    relief_h = max(0, vm_motor_boss_h - face_gap) + 0.3;

    assert(bore_depth < gear_thickness - 1, "Pinion bore breaks through the top");
    assert(vm_motor_boss_d + boss_relief_extra < mb_gear_root_d(vm_pinion_teeth) - 2,
        "Motor boss relief too wide for the pinion root");

    // Local z=0 = pinion underside (world vm_gear_z0()).
    diff() {
        up(gear_thickness / 2)
            mb_helical_gear(
                teeth = vm_pinion_teeth,
                helical = vm_pinion_helical(),
                thickness = gear_thickness
            );

        tag("remove") {
            down(eps)
                cyl(d = shaft_d, h = bore_depth + eps, anchor = BOTTOM, chamfer1 = -0.3);
            down(eps)
                cyl(d = vm_motor_boss_d + boss_relief_extra, h = relief_h + eps, anchor = BOTTOM);
        }
    }
}


motor_pinion();
