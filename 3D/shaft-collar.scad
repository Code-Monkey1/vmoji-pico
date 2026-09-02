include <BOSL2/std.scad>
include <BOSL2/screws.scad>


/* [Shaft] */
// Motor shaft bore (mm). Press-fit: squeeze the slightly oversized shaft in.
shaft_d = 1.0; // [0.5:0.05:3]

/* [Collar] */
collar_od = 16; // [10:0.5:30]
collar_h = 10;   // [4:0.5:20]
// Missing pizza-slice angle (degrees). Wider = easier to spread, weaker clamp.
slit_angle = 8; // [2:0.5:40]

/* [Clamp] */
clamp_screw = "M3";
// Distance from shaft axis to clamp-screw axis (mm). Must clear the bore.
clamp_offset = 4.5; // [2:0.1:12]
// How far the hex nut pocket goes into the jaw (mm).
nut_trap_depth = 3.2; // [2:0.1:8]
teardrop_clamp_hole = true;
// Minimum solid wall between bore and clamp screw (mm).
min_bore_to_clamp = 0.8; // [0.3:0.1:2]

/* [PCB mount] */
pcb_mount_enabled = true; // [true, false]
pcb_mount_screw = "M3";
// Center-to-center spacing of the square hole pattern (mm).
pcb_hole_spacing = 8; // [4:0.5:20]
hat_h = 3.5; // [1:0.5:10]
// Minimum wall from hole edge to hat outer edge (mm).
hat_wall = 2; // [1:0.5:6]
// Hat outer diameter (mm). 0 = auto from spacing, screw size, and hat_wall.
hat_od = 0; // [0:0.5:40]

/* [Hidden] */
// Smooth arcs
$fa = 2;
$fs = 0.25;
// Extra clearance BOSL2 adds to nut pockets for printer over-extrusion
$slop = 0.2;
// Tiny overlap so boolean cuts are watertight
cut_overlap = 0.2;


// ISO close-fit clearance is roughly nominal diameter + 0.4 mm.
function _clearance_hole_d(screw_spec) =
    struct_val(screw_info(screw_spec), "diameter") + 0.4 + 2 * $slop;

function _hat_od(spacing, screw_spec, wall, override = 0) =
    override > 0
        ? override
        : 2 * (spacing + _clearance_hole_d(screw_spec) / 2 + wall);


module shaft_collar(
    shaft_d = shaft_d,
    collar_od = collar_od,
    collar_h = collar_h,
    slit_angle = slit_angle,
    clamp_screw = clamp_screw,
    clamp_offset = clamp_offset,
    nut_trap_depth = nut_trap_depth,
    teardrop_clamp_hole = teardrop_clamp_hole,
    min_bore_to_clamp = min_bore_to_clamp,
    pcb_mount_enabled = pcb_mount_enabled,
    pcb_mount_screw = pcb_mount_screw,
    pcb_hole_spacing = pcb_hole_spacing,
    hat_h = hat_h,
    hat_wall = hat_wall,
    hat_od = hat_od
) {
    eps = cut_overlap;
    r = collar_od / 2;
    screw_d = struct_val(screw_info(clamp_screw), "diameter");
    jaw_half = sqrt(r * r - clamp_offset * clamp_offset);
    clamp_hole_l = 2 * jaw_half + 2;

    hat_outer_d = _hat_od(pcb_hole_spacing, pcb_mount_screw, hat_wall, hat_od);
    total_h = collar_h + (pcb_mount_enabled ? hat_h : 0);
    slit_d = max(collar_od, pcb_mount_enabled ? hat_outer_d : 0) + 1;

    assert(clamp_offset + screw_d / 2 < r,
        "clamp_offset places the screw outside the collar");
    assert(clamp_offset - screw_d / 2 > shaft_d / 2 + min_bore_to_clamp,
        "clamp_offset is too close to the shaft bore");

    if (pcb_mount_enabled) {
        assert(hat_outer_d >= collar_od,
            "hat_od is smaller than collar_od; widen hat_wall or set hat_od");
        assert(pcb_hole_spacing + _clearance_hole_d(pcb_mount_screw) / 2 < hat_outer_d / 2,
            "PCB holes are too close to the hat outer edge");
    }

    diff() {
        union() {
            cyl(d = collar_od, h = collar_h, anchor = BOTTOM);

            if (pcb_mount_enabled)
                up(collar_h)
                    cyl(d = hat_outer_d, h = hat_h, anchor = BOTTOM);
        }

        tag("remove") {
            // Press-fit bore through the full stack.
            down(eps / 2)
                cyl(d = shaft_d, h = total_h + eps, anchor = BOTTOM);

            // Pizza-slice slit along +X through the full stack.
            down(eps / 2)
                pie_slice(
                    d = slit_d,
                    h = total_h + eps,
                    ang = slit_angle,
                    anchor = BOTTOM,
                    spin = -slit_angle / 2
                );

            // M3 clearance hole across the collar jaws, nut pocket on the -Y face.
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
                                l = nut_trap_depth + eps,
                                spec = clamp_screw,
                                anchor = BOT
                            );

            // Four PCB mounting holes in a square (axis-aligned, 90° apart).
            if (pcb_mount_enabled)
                up(collar_h - eps / 2)
                    zrot_copies(n = 4)
                        right(pcb_hole_spacing)
                            screw_hole(
                                pcb_mount_screw,
                                l = hat_h + eps,
                                anchor = BOTTOM,
                                orient = UP
                            );
        }
    }
}


shaft_collar();
