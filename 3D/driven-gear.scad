include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <motor-base-common.scad>


/* [Shaft] */
// Driven shaft bore (mm). Matches 608ZZ ID / 8 mm rod.
shaft_d = 8; // [4:0.1:12]
// Extra diametral clearance beyond shaft_d for slip-on fit before clamp.
bore_extra = 0.15; // [0:0.05:0.6]


/* [Gear] */
gear_mod = 1.25; // [0.5:0.05:2]
driven_teeth = 28; // [16:1:60]
gear_helical = 25; // [0:1:40]
gear_backlash = 0.3; // [0:0.05:1]
gear_thickness = 10; // [6:0.5:20]
gear_pressure_angle = 20; // [14.5:0.5:25]
gear_slices = 6; // [3:1:12]


/* [Clamp hub] */
// Boss height above the gear for the M3 clamp (mm).
hub_h = 6; // [3:0.5:12]
// Hub OD (mm). 0 = auto from shaft + clamp clearance.
hub_od = 18; // [0:0.5:40]
slit_width = 0.6; // [0.2:0.05:2]
clamp_screw = "M3";
clamp_offset = 7.2; // [4:0.1:16]
nut_trap_depth = 3.2; // [2:0.1:8]
teardrop_clamp_hole = true; // [true, false]
min_bore_to_clamp = 1.0; // [0.3:0.1:3]
// Optional M3 set-screw through the hub (+Y). File a flat on the rod for best grip.
set_screw_enabled = true; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module driven_gear(
    shaft_d = shaft_d,
    bore_extra = bore_extra,
    gear_mod = gear_mod,
    driven_teeth = driven_teeth,
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
    min_bore_to_clamp = min_bore_to_clamp,
    set_screw_enabled = set_screw_enabled
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
    auto_hub = max(
        bore_d + 2 * (min_bore_to_clamp + screw_d + 1),
        mb_bearing_od() + 2
    );
    hub_d = hub_od > 0 ? hub_od : min(auto_hub, root_d - 1.5);
    r = hub_d / 2;
    jaw_half = sqrt(max(0.01, r * r - clamp_offset * clamp_offset));
    clamp_hole_l = 2 * jaw_half + 2;
    total_h = gear_thickness + hub_h;
    outer_d = mb_gear_outer_d(driven_teeth, gear_mod, gear_helical, gear_pressure_angle);
    slit_d = max(hub_d, outer_d) + 1;

    assert(hub_d > bore_d + 2 * min_bore_to_clamp + screw_d,
        "hub_od too small for clamp around 8 mm shaft");
    assert(clamp_offset + screw_d / 2 < r,
        "clamp_offset places the screw outside the hub");
    assert(clamp_offset - screw_d / 2 > bore_d / 2 + min_bore_to_clamp,
        "clamp_offset is too close to the shaft bore");
    assert(hub_d < root_d,
        "hub_od intersects gear roots; reduce hub_od or increase teeth/mod");

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

            // Clamp boss above the gear (toward top bearing / TX deck).
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

            // Radial set-screw: file a flat on the 8 mm rod under this hole.
            if (set_screw_enabled)
                up(gear_thickness + hub_h / 2)
                    back(hub_d / 4)
                        screw_hole(
                            clamp_screw,
                            l = hub_d / 2 + 2,
                            teardrop = teardrop_clamp_hole,
                            orient = BACK,
                            anchor = CENTER
                        );
        }
    }
}


driven_gear();
