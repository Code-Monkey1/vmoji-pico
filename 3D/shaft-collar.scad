include <BOSL2/std.scad>
include <BOSL2/screws.scad>


/* [Shaft] */
// Motor shaft bore (mm). Press-fit: squeeze the slightly oversized shaft in.
shaft_d = 1.0; // [0.5:0.05:3]

/* [Collar] */
collar_od = 16; // [10:0.5:30]
collar_h = 8;   // [4:0.5:20]
// Missing pizza-slice angle (degrees). Wider = easier to spread, weaker clamp.
slit_angle = 10; // [2:0.5:40]

/* [Clamp] */
clamp_screw = "M3";
// Distance from shaft axis to clamp-screw axis (mm). Must clear the bore.
clamp_offset = 4.5; // [2:0.1:12]
// How far the hex nut pocket goes into the jaw (mm).
nut_trap_depth = 3.2; // [2:0.1:8]
teardrop_clamp_hole = true;

/* [Hidden] */
// Smooth arcs
$fa = 2;
$fs = 0.25;
// Extra clearance BOSL2 adds to the nut pocket for printer over-extrusion
$slop = 0.2;


module shaft_collar(
    shaft_d = shaft_d,
    collar_od = collar_od,
    collar_h = collar_h,
    slit_angle = slit_angle,
    clamp_screw = clamp_screw,
    clamp_offset = clamp_offset,
    nut_trap_depth = nut_trap_depth,
    teardrop_clamp_hole = teardrop_clamp_hole
) {
    eps = 0.2;
    r = collar_od / 2;
    screw_d = struct_val(screw_info(clamp_screw), "diameter");
    jaw_half = sqrt(r * r - clamp_offset * clamp_offset);
    clamp_hole_l = 2 * jaw_half + 2;

    assert(clamp_offset + screw_d / 2 < r,
        "clamp_offset places the screw outside the collar");
    assert(clamp_offset - screw_d / 2 > shaft_d / 2 + 0.8,
        "clamp_offset is too close to the shaft bore");

    diff() {
        cyl(d = collar_od, h = collar_h, anchor = BOTTOM);

        tag("remove") {
            // Press-fit bore. Intentionally no slop: shaft is squeezed in.
            down(eps / 2)
                cyl(d = shaft_d, h = collar_h + eps, anchor = BOTTOM);

            // Pizza-slice slit along +X so the ring can spring open.
            down(eps / 2)
                pie_slice(
                    d = collar_od + 1,
                    h = collar_h + eps,
                    ang = slit_angle,
                    anchor = BOTTOM,
                    spin = -slit_angle / 2
                );

            // M3 clearance hole across the jaws, nut pocket on the -Y face.
            // orient=FWD puts the hole along Y; teardrop then points UP for printing.
            up(collar_h / 2)
                right(clamp_offset)
                    screw_hole(
                        clamp_screw,
                        l = clamp_hole_l,
                        teardrop = teardrop_clamp_hole,
                        orient = FWD
                    )
                        position(BOT)
                            nut_trap_inline(
                                l = nut_trap_depth + 1,
                                spec = clamp_screw,
                                anchor = BOT
                            );
        }
    }
}


shaft_collar();
