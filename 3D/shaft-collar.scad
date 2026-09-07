// Shaft collar on plastic Ø8 driven shaft — PCB hat + RX coil seat underneath.
// Upper axial stop for the spinning stack. Includes params for ring size sync.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <vmoji-mech-params.scad>


/* [Collar] */
collar_od = 26; // [14:0.5:40]
slit_width = 0.6; // [0.2:0.05:2]
clamp_screw = "M3";
clamp_offset = 8; // [4:0.1:16]
nut_trap_depth = 3.2; // [2:0.1:8]
teardrop_clamp_hole = true;
min_bore_to_clamp = 1.0; // [0.3:0.1:3]


/* [PCB mount] */
pcb_mount_enabled = true; // [true, false]
pcb_mount_screw = "M3";
pcb_hole_spacing = 11; // [4:0.5:20]
hat_wall = 2.5; // [1:0.5:6]
hat_od = 0; // [0:0.5:40]
pcb_nut_pocket_enabled = true; // [true, false]
pcb_collar_nut_pocket_enabled = true; // [true, false]
pcb_hat_nut_pocket_enabled = false; // [true, false]
pcb_hat_nut_pocket_depth = 2.8; // [0:0.1:8]
pcb_nut_pocket_d = 0; // [0:0.5:12]
pcb_nut_pocket_extra_d = 0.5; // [0:0.1:3]
pcb_omit_pos_x_hole = true; // [true, false]


/* [RX coil seat] */
rx_seat_enabled = true; // [true, false]


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
    shaft_d = vm_shaft_d,
    bore_extra = vm_shaft_bore_extra,
    collar_od = collar_od,
    collar_h = vm_collar_h,
    slit_width = slit_width,
    clamp_screw = clamp_screw,
    clamp_offset = clamp_offset,
    nut_trap_depth = nut_trap_depth,
    teardrop_clamp_hole = teardrop_clamp_hole,
    min_bore_to_clamp = min_bore_to_clamp,
    pcb_mount_enabled = pcb_mount_enabled,
    pcb_mount_screw = pcb_mount_screw,
    pcb_hole_spacing = pcb_hole_spacing,
    hat_h = vm_hat_h,
    hat_wall = hat_wall,
    hat_od = hat_od,
    pcb_nut_pocket_enabled = pcb_nut_pocket_enabled,
    pcb_collar_nut_pocket_enabled = pcb_collar_nut_pocket_enabled,
    pcb_hat_nut_pocket_enabled = pcb_hat_nut_pocket_enabled,
    pcb_hat_nut_pocket_depth = pcb_hat_nut_pocket_depth,
    pcb_nut_pocket_d = pcb_nut_pocket_d,
    pcb_nut_pocket_extra_d = pcb_nut_pocket_extra_d,
    pcb_omit_pos_x_hole = pcb_omit_pos_x_hole,
    rx_seat_enabled = rx_seat_enabled,
    ring_id = vm_ring_id,
    ring_od = vm_ring_od,
    ring_h = vm_ring_h,
    ring_standoff = vm_ring_standoff
) {
    eps = cut_overlap;
    bore_d = shaft_d + bore_extra + 2 * $slop;
    r = collar_od / 2;
    screw_d = struct_val(screw_info(clamp_screw), "diameter");
    jaw_half = sqrt(r * r - clamp_offset * clamp_offset);
    clamp_hole_l = 2 * jaw_half + 2;

    rx_seat_h = rx_seat_enabled ? ring_standoff + ring_h + 1.2 : 0;
    hat_outer_d = _hat_od(pcb_hole_spacing, pcb_mount_screw, hat_wall, hat_od);
    nut_pocket_d = _nut_pocket_d(
        pcb_mount_screw,
        pcb_nut_pocket_d,
        pcb_nut_pocket_extra_d
    );
    total_h = rx_seat_h + collar_h + (pcb_mount_enabled ? hat_h : 0);
    slit_d = max(collar_od, pcb_mount_enabled ? hat_outer_d : 0, ring_od + 2) + 1;
    pcb_hole_rots = _pcb_hole_rotations(pcb_omit_pos_x_hole);
    collar_z0 = rx_seat_h;

    assert(clamp_offset + screw_d / 2 < r,
        "clamp_offset places the screw outside the collar");
    assert(clamp_offset - screw_d / 2 > bore_d / 2 + min_bore_to_clamp,
        "clamp_offset is too close to the shaft bore");
    if (rx_seat_enabled)
        assert(collar_od > ring_id - 2, "collar_od too small to back the RX ring");

    if (pcb_mount_enabled) {
        assert(hat_outer_d >= collar_od,
            "hat_od is smaller than collar_od; widen hat_wall or set hat_od");
        assert(pcb_hole_spacing + _clearance_hole_d(pcb_mount_screw) / 2 < hat_outer_d / 2,
            "PCB holes are too close to the hat outer edge");

        if (pcb_nut_pocket_enabled && pcb_collar_nut_pocket_enabled) {
            assert(
                pcb_hole_spacing - nut_pocket_d / 2 < r,
                "collar nut pocket does not reach the collar"
            );
            assert(
                pcb_hole_spacing - nut_pocket_d / 2 > bore_d / 2 + min_bore_to_clamp,
                "collar nut pockets cut too close to the shaft bore"
            );
        }
    }

    diff() {
        union() {
            // RX seat disk + plastic standoffs (faces TX below).
            if (rx_seat_enabled) {
                cyl(d = ring_od + 4, h = rx_seat_h, anchor = BOTTOM);
                up(0)
                    zrot_copies(n = 3, sa = 90)
                        right((ring_id + ring_od) / 4)
                            cyl(d = 4.5, h = ring_standoff, anchor = BOTTOM);
            }

            up(collar_z0)
                cyl(d = collar_od, h = collar_h, anchor = BOTTOM);

            if (pcb_mount_enabled)
                up(collar_z0 + collar_h)
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

            // RX ring rebate in the seat disk.
            if (rx_seat_enabled) {
                up(ring_standoff)
                    difference() {
                        cyl(
                            d = ring_od + 2 * $slop + 1.2,
                            h = ring_h + eps,
                            anchor = BOTTOM
                        );
                        down(eps)
                            cyl(
                                d = max(bore_d + 2, ring_id),
                                h = ring_h + 3 * eps,
                                anchor = BOTTOM
                            );
                    }
            }

            up(collar_z0 + collar_h / 2)
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
                up(collar_z0 + collar_h - eps / 2)
                    zrot_copies(rots = pcb_hole_rots)
                        right(pcb_hole_spacing)
                            screw_hole(
                                pcb_mount_screw,
                                l = hat_h + eps,
                                anchor = BOTTOM,
                                orient = UP
                            );

                if (pcb_nut_pocket_enabled && pcb_collar_nut_pocket_enabled)
                    up(collar_z0)
                        zrot_copies(rots = pcb_hole_rots)
                            right(pcb_hole_spacing)
                                cyl(
                                    d = nut_pocket_d,
                                    h = collar_h + eps,
                                    anchor = BOTTOM,
                                    orient = UP
                                );

                if (pcb_nut_pocket_enabled && pcb_hat_nut_pocket_enabled)
                    up(collar_z0 + collar_h)
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
