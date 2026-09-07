include <BOSL2/std.scad>
include <BOSL2/screws.scad>


/* [Shaft] */
// Driven shaft bore (mm). Matches 608ZZ ID / 8 mm rod.
shaft_d = 8; // [4:0.1:12]
// Extra diametral clearance beyond shaft_d before the clamp closes.
bore_extra = 0.15; // [0:0.05:0.6]

/* [Collar] */
collar_od = 26; // [14:0.5:40]
collar_h = 12;   // [6:0.5:24]
// Kerf width of the rectangular slit (mm). Wider = easier to spread, weaker clamp.
slit_width = 0.6; // [0.2:0.05:2]

/* [Clamp] */
clamp_screw = "M3";
// Distance from shaft axis to clamp-screw axis (mm). Must clear the bore.
clamp_offset = 8; // [4:0.1:16]
// How far the hex nut pocket goes into the jaw (mm).
nut_trap_depth = 3.2; // [2:0.1:8]
teardrop_clamp_hole = true;
// Minimum solid wall between bore and clamp screw (mm).
min_bore_to_clamp = 1.0; // [0.3:0.1:3]

/* [PCB mount] */
pcb_mount_enabled = true; // [true, false]
pcb_mount_screw = "M3";
// Center-to-center spacing of the square hole pattern (mm).
pcb_hole_spacing = 11; // [4:0.5:20]
hat_h = 3.5; // [1:0.5:10]
// Minimum wall from hole edge to hat outer edge (mm).
hat_wall = 2.5; // [1:0.5:6]
// Hat outer diameter (mm). 0 = auto from spacing, screw size, and hat_wall.
hat_od = 0; // [0:0.5:40]
// Cylindrical nut clearance under each mount hole.
pcb_nut_pocket_enabled = true; // [true, false]
// Vertical notches cut into the collar under each hole (full collar height).
pcb_collar_nut_pocket_enabled = true; // [true, false]
// Optional extra pockets upward from the hat underside (keeps flange thinner).
pcb_hat_nut_pocket_enabled = false; // [true, false]
pcb_hat_nut_pocket_depth = 2.8; // [0:0.1:8]
// Pocket diameter (mm). 0 = auto from nut size + pcb_nut_pocket_extra_d.
pcb_nut_pocket_d = 0; // [0:0.5:12]
// Extra diameter beyond the nut's circumscribed circle (mm).
pcb_nut_pocket_extra_d = 0.5; // [0:0.1:3]
// Omit the +X mount hole (conflicts with the clamp screw). Three-screw mount.
pcb_omit_pos_x_hole = true; // [true, false]

/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


function _clearance_hole_d(screw_spec) =
    struct_val(screw_info(screw_spec), "diameter") + 0.4 + 2 * $slop;

function _hat_od(spacing, screw_spec, wall, override = 0) =
    override > 0
        ? override
        : 2 * (spacing + _clearance_hole_d(screw_spec) / 2 + wall);

function _nut_circum_d(screw_spec) =
    struct_val(nut_info(screw_spec), "width") / cos(30);

function _nut_pocket_d(screw_spec, override = 0, extra_d = 0) =
    override > 0
        ? override
        : _nut_circum_d(screw_spec) + extra_d + 2 * $slop;

function _pcb_hole_rotations(omit_pos_x) =
    omit_pos_x ? [90, 180, 270] : [0, 90, 180, 270];


module shaft_collar(
    shaft_d = shaft_d,
    bore_extra = bore_extra,
    collar_od = collar_od,
    collar_h = collar_h,
    slit_width = slit_width,
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
    hat_od = hat_od,
    pcb_nut_pocket_enabled = pcb_nut_pocket_enabled,
    pcb_collar_nut_pocket_enabled = pcb_collar_nut_pocket_enabled,
    pcb_hat_nut_pocket_enabled = pcb_hat_nut_pocket_enabled,
    pcb_hat_nut_pocket_depth = pcb_hat_nut_pocket_depth,
    pcb_nut_pocket_d = pcb_nut_pocket_d,
    pcb_nut_pocket_extra_d = pcb_nut_pocket_extra_d,
    pcb_omit_pos_x_hole = pcb_omit_pos_x_hole
) {
    eps = cut_overlap;
    bore_d = shaft_d + bore_extra + 2 * $slop;
    r = collar_od / 2;
    screw_d = struct_val(screw_info(clamp_screw), "diameter");
    jaw_half = sqrt(r * r - clamp_offset * clamp_offset);
    clamp_hole_l = 2 * jaw_half + 2;

    hat_outer_d = _hat_od(pcb_hole_spacing, pcb_mount_screw, hat_wall, hat_od);
    nut_pocket_d = _nut_pocket_d(
        pcb_mount_screw,
        pcb_nut_pocket_d,
        pcb_nut_pocket_extra_d
    );
    total_h = collar_h + (pcb_mount_enabled ? hat_h : 0);
    slit_d = max(collar_od, pcb_mount_enabled ? hat_outer_d : 0) + 1;
    pcb_hole_rots = _pcb_hole_rotations(pcb_omit_pos_x_hole);

    assert(clamp_offset + screw_d / 2 < r,
        "clamp_offset places the screw outside the collar");
    assert(clamp_offset - screw_d / 2 > bore_d / 2 + min_bore_to_clamp,
        "clamp_offset is too close to the shaft bore");

    if (pcb_mount_enabled) {
        assert(hat_outer_d >= collar_od,
            "hat_od is smaller than collar_od; widen hat_wall or set hat_od");
        assert(pcb_hole_spacing + _clearance_hole_d(pcb_mount_screw) / 2 < hat_outer_d / 2,
            "PCB holes are too close to the hat outer edge");

        if (pcb_nut_pocket_enabled) {
            if (pcb_collar_nut_pocket_enabled) {
                assert(
                    pcb_hole_spacing - nut_pocket_d / 2 < r,
                    str(
                        "collar nut pocket (d=", nut_pocket_d,
                        ") does not reach the collar; increase pcb_nut_pocket_extra_d ",
                        "or pcb_nut_pocket_d"
                    )
                );
                assert(
                    pcb_hole_spacing - nut_pocket_d / 2 > bore_d / 2 + min_bore_to_clamp,
                    "collar nut pockets cut too close to the shaft bore"
                );
            }

            if (pcb_hat_nut_pocket_enabled)
                assert(pcb_hat_nut_pocket_depth > 0,
                    "pcb_hat_nut_pocket_depth must be positive");
        }
    }

    diff() {
        union() {
            cyl(d = collar_od, h = collar_h, anchor = BOTTOM);

            if (pcb_mount_enabled)
                up(collar_h)
                    cyl(d = hat_outer_d, h = hat_h, anchor = BOTTOM);
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

            if (pcb_mount_enabled) {
                up(collar_h - eps / 2)
                    zrot_copies(rots = pcb_hole_rots)
                        right(pcb_hole_spacing)
                            screw_hole(
                                pcb_mount_screw,
                                l = hat_h + eps,
                                anchor = BOTTOM,
                                orient = UP
                            );

                if (pcb_nut_pocket_enabled && pcb_collar_nut_pocket_enabled)
                    zrot_copies(rots = pcb_hole_rots)
                        right(pcb_hole_spacing)
                            cyl(
                                d = nut_pocket_d,
                                h = collar_h + eps,
                                anchor = BOTTOM,
                                orient = UP
                            );

                if (pcb_nut_pocket_enabled && pcb_hat_nut_pocket_enabled)
                    up(collar_h)
                        zrot_copies(rots = pcb_hole_rots)
                            right(pcb_hole_spacing)
                                cyl(
                                    d = nut_pocket_d,
                                    h = pcb_hat_nut_pocket_depth + eps,
                                    anchor = BOTTOM,
                                    orient = UP
                                );
            }
        }
    }
}


shaft_collar();
