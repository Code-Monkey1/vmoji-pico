include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <motor-base-common.scad>


/* [Shaft] */
// Proven RF-300 press-fit bore (mm). Do not change without re-calibrating.
shaft_d = 1.0; // [0.5:0.05:3]


/* [Gear] */
gear_mod = 1.25; // [0.5:0.05:2]
pinion_teeth = 14; // [10:1:30]
gear_helical = 25; // [0:1:40]
gear_backlash = 0.3; // [0:0.05:1]
gear_thickness = 10; // [6:0.5:20]
gear_pressure_angle = 20; // [14.5:0.5:25]
gear_slices = 6; // [3:1:12]


/* [Hub / clamp] */
// Axial hub below the teeth so the pinion clears the motor face (mm).
hub_h = 3; // [1:0.5:8]
// Hub OD (mm). 0 = auto just under root diameter.
hub_od = 0; // [0:0.5:30]
slit_width = 0.5; // [0.2:0.05:2]
clamp_screw = "M3";
// Distance from shaft axis to clamp-screw axis (mm).
clamp_offset = 3.8; // [2:0.1:12]
nut_trap_depth = 3.2; // [2:0.1:8]
teardrop_clamp_hole = true; // [true, false]
min_bore_to_clamp = 0.8; // [0.3:0.1:2]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_pinion(
    shaft_d = shaft_d,
    gear_mod = gear_mod,
    pinion_teeth = pinion_teeth,
    gear_helical = gear_helical,
    gear_backlash = gear_backlash,
    gear_thickness = gear_thickness,
    gear_pressure_angle = gear_pressure_angle,
    gear_slices = gear_slices,
    hub_h = hub_h,
    hub_od = hub_od,
    slit_width = slit_width,
    clamp_screw = clamp_screw,
    clamp_offset = clamp_offset,
    nut_trap_depth = nut_trap_depth,
    teardrop_clamp_hole = teardrop_clamp_hole,
    min_bore_to_clamp = min_bore_to_clamp
) {
    eps = cut_overlap;
    root_d = 2 * root_radius(
        mod = gear_mod,
        teeth = pinion_teeth,
        helical = gear_helical,
        pressure_angle = gear_pressure_angle,
        backlash = gear_backlash
    );
    // Prefer a clampable hub; allow it to sit just inside the root circle.
    hub_d = hub_od > 0 ? hub_od : max(shaft_d + 8, min(root_d - 0.4, 14));
    r = hub_d / 2;
    screw_d = struct_val(screw_info(clamp_screw), "diameter");
    jaw_half = sqrt(max(0.01, r * r - clamp_offset * clamp_offset));
    clamp_hole_l = 2 * jaw_half + 2;
    total_h = hub_h + gear_thickness;
    slit_d = max(hub_d, mb_gear_outer_d(pinion_teeth, gear_mod, gear_helical, gear_pressure_angle)) + 1;

    assert(clamp_offset + screw_d / 2 < r,
        "clamp_offset places the screw outside the hub");
    assert(clamp_offset - screw_d / 2 > shaft_d / 2 + min_bore_to_clamp,
        "clamp_offset is too close to the shaft bore");
    assert(hub_d > shaft_d + 2 * min_bore_to_clamp + screw_d,
        "hub_od too small for clamp");

    diff() {
        union() {
            // Hub under the gear (sits toward the motor face).
            cyl(d = hub_d, h = hub_h, anchor = BOTTOM);

            // Herringbone teeth centered above the hub.
            up(hub_h + gear_thickness / 2)
                mb_herringbone_gear(
                    teeth = pinion_teeth,
                    thickness = gear_thickness,
                    mod = gear_mod,
                    helical = gear_helical,
                    backlash = gear_backlash,
                    pressure_angle = gear_pressure_angle,
                    shaft_diam = 0,
                    slices = gear_slices
                );
        }

        tag("remove") {
            down(eps / 2)
                cyl(d = shaft_d, h = total_h + eps, anchor = BOTTOM);

            // Slit along +X through hub + gear.
            down(eps / 2)
                left(eps)
                    cuboid(
                        [slit_d / 2 + eps, slit_width, total_h + eps],
                        anchor = LEFT + BOTTOM
                    );

            // M3 clamp across the hub jaws; nut trap on -Y.
            up(hub_h / 2)
                right(clamp_offset)
                    screw_hole(
                        clamp_screw,
                        l = clamp_hole_l,
                        teardrop = teardrop_clamp_hole,
                        orient = FWD
                    )
                        position(BOT)
                            nut_trap_inline(
                                l = nut_trap_depth + eps,
                                spec = clamp_screw,
                                anchor = BOT
                            );
        }
    }
}


motor_pinion();
