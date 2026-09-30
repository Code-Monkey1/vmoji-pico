// Driven herringbone gear — slit-clamp on plastic Ø8 shaft; seats on shaft flange.
// No set-screw into plastic (avoids crushing the dielectric shaft).
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Clamp] */
slit_width = 0.6; // [0.2:0.05:2]
clamp_screw = "M3";
clamp_offset = 7.2; // [4:0.1:16]
nut_trap_depth = 3.2; // [2:0.1:8]
teardrop_clamp_hole = true; // [true, false]
min_bore_to_clamp = 1.0; // [0.3:0.1:3]
hub_od = 18; // [12:0.5:40]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module driven_gear(
    shaft_d = vm_shaft_d,
    bore_extra = vm_shaft_bore_extra,
    gear_mod = vm_gear_mod,
    driven_teeth = vm_driven_teeth,
    gear_helical = vm_gear_helical,
    gear_backlash = vm_gear_backlash,
    gear_thickness = vm_gear_thickness,
    gear_pressure_angle = vm_gear_pressure_angle,
    gear_slices = vm_gear_slices,
    hub_h = vm_driven_hub_h,
    hub_od = hub_od,
    slit_width = slit_width,
    clamp_screw = clamp_screw,
    clamp_offset = clamp_offset,
    nut_trap_depth = nut_trap_depth,
    teardrop_clamp_hole = teardrop_clamp_hole,
    min_bore_to_clamp = min_bore_to_clamp
) {
    eps = cut_overlap;
    bore_d = shaft_d + bore_extra + 2 * $slop;
    screw_d = struct_val(screw_info(clamp_screw), "diameter");
    root_d = 2 * root_radius(
        mod = gear_mod,
        teeth = driven_teeth,
        helical = gear_helical,
        pressure_angle = gear_pressure_angle,
        backlash = gear_backlash
    );
    hub_d = min(hub_od, root_d - 1.5);
    r = hub_d / 2;
    jaw_half = sqrt(max(0.01, r * r - clamp_offset * clamp_offset));
    clamp_hole_l = 2 * jaw_half + 2;
    total_h = gear_thickness + hub_h;
    outer_d = mb_gear_outer_d(driven_teeth, gear_mod, gear_helical, gear_pressure_angle);
    slit_d = max(hub_d, outer_d) + 1;

    assert(hub_d > bore_d + 2 * min_bore_to_clamp + screw_d,
        "hub_od too small for clamp");
    assert(clamp_offset + screw_d / 2 < r,
        "clamp_offset places the screw outside the hub");
    assert(clamp_offset - screw_d / 2 > bore_d / 2 + min_bore_to_clamp,
        "clamp_offset is too close to the shaft bore");

    // Local z=0 = gear bottom (seats on driven-shaft flange top).
    diff() {
        union() {
            up(gear_thickness / 2)
                mb_herringbone_gear(
                    teeth = driven_teeth,
                    thickness = gear_thickness,
                    mod = gear_mod,
                    helical = gear_helical,
                    backlash = gear_backlash,
                    pressure_angle = gear_pressure_angle,
                    shaft_diam = 0,
                    slices = gear_slices
                );

            up(gear_thickness)
                cyl(d = hub_d, h = hub_h, anchor = BOTTOM);
        }

        tag("remove") {
            down(eps / 2)
                cyl(d = bore_d, h = total_h + eps, anchor = BOTTOM);

            down(eps / 2)
                left(eps)
                    cuboid(
                        [slit_d / 2 + eps, slit_width, total_h + eps],
                        anchor = LEFT + BOTTOM
                    );

            up(gear_thickness + hub_h / 2)
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


driven_gear();
