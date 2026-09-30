// Fit-test coupons: print small samples of every press / snug fit before the real parts,
// try them on the real hardware, then copy the winning value into vmoji-mech-params.scad.
// Labels are the parameter value under test (engraved on the top face).
// Pick one coupon with `coupon` (quick prints), or "all" for the full sheet
// (~170 x 190 mm, fits a 220 bed).
include <BOSL2/std.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Coupon] */
coupon = "all"; // [all, motor_shaft, journal, bearing_od, nut_socket, tip_bore, key, well, insert, locate, ir]
motor_shaft_bores = [1.70, 1.75, 1.80, 1.85, 1.90, 1.95, 2.00];
journal_ds = [7.85, 7.90, 7.95, 8.00, 8.05];
bearing_fits = [0.05, 0.15, 0.25];
nut_socket_extras = [0.2, 0.4, 0.6];
tip_bore_extras = [0.05, 0.15, 0.25, 0.35];
key_fits = [0.15, 0.25, 0.35];
well_interfs = [0.05, 0.15, 0.25];
insert_hole_ds = [3.8, 4.0, 4.2];
locate_fits = [0.1, 0.15, 0.25, 0.8];
ir_hole_extras = [0.2, 0.3, 0.4];


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
eps = 0.2;


function _fmt(v) = str(v);

module _label(s, size = 2.4) {
    down(0.6)
        linear_extrude(0.6 + eps)
            text(s, size = size, halign = "center", valign = "center");
}

// Row of blocks, each with one feature; child(0) = feature cut at the block top center.
module _row(vals, pitch, block, label_dy) {
    n = len(vals);
    for (i = [0:n - 1])
        right((i - (n - 1) / 2) * pitch)
            difference() {
                cuboid(block, anchor = BOTTOM, rounding = 1, edges = "Z");
                up(block.z) {
                    back(label_dy) _label(_fmt(vals[i]));
                    children();
                }
            }
}

module coupon_motor_shaft() {
    // Blind bores, same depth as the pinion.
    depth = vm_motor_shaft_len - vm_pinion_face_gap + 0.4;
    for (i = [0:len(motor_shaft_bores) - 1])
        right((i - (len(motor_shaft_bores) - 1) / 2) * 7)
            difference() {
                cuboid([7, 14, 7], anchor = BOTTOM, rounding = 1, edges = "Z");
                down(eps) back(2) cyl(d = motor_shaft_bores[i], h = depth + eps, anchor = BOTTOM, chamfer1 = -0.3);
                up(7) fwd(3.5) _label(str(round(motor_shaft_bores[i] * 100)), 2.2);
            }
}

module coupon_journal() {
    for (i = [0:len(journal_ds) - 1])
        right((i - (len(journal_ds) - 1) / 2) * 14) {
            difference() {
                cuboid([14, 18, 2], anchor = BOTTOM, rounding = 1, edges = "Z");
                up(2) fwd(6) _label(_fmt(journal_ds[i]), 2.2);
            }
            up(2 - 0.01) back(2) cyl(d = journal_ds[i], h = vm_bearing_h + 1, anchor = BOTTOM, chamfer2 = 0.15);
        }
}

module coupon_bearing_od() {
    for (i = [0:len(bearing_fits) - 1])
        right((i - (len(bearing_fits) - 1) / 2) * 30)
            difference() {
                cuboid([30, 34, 5], anchor = BOTTOM, rounding = 1, edges = "Z");
                down(eps) back(2) cyl(d = mb_bearing_pocket_d(bearing_fits[i]), h = 5 + 2 * eps, anchor = BOTTOM);
                up(5) fwd(14) _label(_fmt(bearing_fits[i]));
            }
}

module coupon_nut_socket() {
    for (i = [0:len(nut_socket_extras) - 1])
        right((i - (len(nut_socket_extras) - 1) / 2) * 22)
            difference() {
                cuboid([22, 26, 5], anchor = BOTTOM, rounding = 1, edges = "Z");
                down(eps) back(2) cyl(d = mb_hex_circum_d(vm_nut_af + nut_socket_extras[i]), h = 5 + 2 * eps, anchor = BOTTOM, $fn = 6);
                up(5) fwd(10.5) _label(_fmt(nut_socket_extras[i]));
            }
}

module coupon_tip_bore() {
    for (i = [0:len(tip_bore_extras) - 1])
        right((i - (len(tip_bore_extras) - 1) / 2) * 14)
            difference() {
                cuboid([14, 18, 8], anchor = BOTTOM, rounding = 1, edges = "Z");
                down(eps) back(2) cyl(d = vm_shcs_d + tip_bore_extras[i], h = 8 + 2 * eps, anchor = BOTTOM);
                up(8) fwd(6.5) _label(_fmt(tip_bore_extras[i]));
            }
}

module coupon_key() {
    // Socket samples (head side) + one key stub at the real shaft size.
    for (i = [0:len(key_fits) - 1])
        right((i - (len(key_fits) - 1) / 2) * 14)
            difference() {
                cuboid([14, 18, vm_key_len], anchor = BOTTOM, rounding = 1, edges = "Z");
                down(eps) back(2)
                    intersection() {
                        cyl(d = vm_rotor_shaft_d + key_fits[i], h = vm_key_len + 2 * eps, anchor = BOTTOM);
                        cuboid([vm_key_flat + key_fits[i], 20, vm_key_len + 2 * eps], anchor = BOTTOM);
                    }
                up(vm_key_len) fwd(6.5) _label(_fmt(key_fits[i]));
            }
    fwd(16) {
        cuboid([14, 14, 2], anchor = BOTTOM, rounding = 1, edges = "Z");
        up(2 - 0.01)
            intersection() {
                cyl(d = vm_rotor_shaft_d, h = vm_key_len + 1, anchor = BOTTOM, chamfer2 = 0.5);
                cuboid([vm_key_flat, 20, vm_key_len + 1], anchor = BOTTOM);
            }
    }
}

module coupon_well() {
    bore_d = mb_well_bore_d();
    h = 8;
    for (i = [0:len(well_interfs) - 1])
        right((i - (len(well_interfs) - 1) / 2) * 34)
            difference() {
                cuboid([34, 40, h], anchor = BOTTOM, rounding = 1, edges = "Z");
                back(2) down(eps)
                    difference() {
                        cyl(d = bore_d, h = h + 2 * eps, anchor = BOTTOM);
                        for (k = [0:vm_well_rib_n - 1])
                            zrot(k * 360 / vm_well_rib_n + 30)
                                right(vm_motor_d / 2 - well_interfs[i])
                                    down(eps)
                                        cuboid(
                                            [bore_d / 2 - vm_motor_d / 2 + well_interfs[i] + 0.3, vm_well_rib_w, h - vm_well_leadin],
                                            anchor = LEFT + BOTTOM,
                                            chamfer = 0.5,
                                            edges = [TOP + LEFT]
                                        );
                    }
                up(h) fwd(17) _label(_fmt(well_interfs[i]));
            }
}

module coupon_insert() {
    depth = vm_insert_depth(vm_insert_len_col);
    for (i = [0:len(insert_hole_ds) - 1])
        right((i - (len(insert_hole_ds) - 1) / 2) * 12)
            difference() {
                cuboid([12, 16, depth + 2], anchor = BOTTOM, rounding = 1, edges = "Z");
                up(depth + 2) back(2) down(depth) cyl(d = insert_hole_ds[i] + 2 * $slop, h = depth + eps, anchor = BOTTOM);
                up(depth + 2) fwd(5.5) _label(_fmt(insert_hole_ds[i]));
            }
}

module coupon_locate() {
    // Spigot (as on the column tops) + recesses (as on the deck underside).
    left(34) {
        cuboid([14, 14, 3], anchor = BOTTOM, rounding = 1, edges = "Z");
        up(3 - 0.01) cyl(d = vm_locate_d, h = vm_locate_h, anchor = BOTTOM, chamfer2 = 0.4);
    }
    right(8)
        for (i = [0:len(locate_fits) - 1])
            right((i - (len(locate_fits) - 1) / 2) * 14)
                difference() {
                    cuboid([14, 18, 3], anchor = BOTTOM, rounding = 1, edges = "Z");
                    down(eps) back(2) cyl(d = vm_locate_d + locate_fits[i], h = vm_locate_h + vm_locate_depth_extra + eps, anchor = BOTTOM);
                    up(3) fwd(6.5) _label(_fmt(locate_fits[i]));
                }
}

module coupon_ir() {
    for (i = [0:len(ir_hole_extras) - 1])
        right((i - (len(ir_hole_extras) - 1) / 2) * 12)
            difference() {
                cuboid([12, 16, 5], anchor = BOTTOM, rounding = 1, edges = "Z");
                down(eps) back(2) cyl(d = vm_ir_d + ir_hole_extras[i], h = 5 + 2 * eps, anchor = BOTTOM);
                down(eps) back(2) cyl(d = vm_ir_flange_d + 0.4, h = 1.2 + eps, anchor = BOTTOM);
                up(5) fwd(5.5) _label(_fmt(ir_hole_extras[i]));
            }
}

// Sheet position of each coupon when printing "all".
function _sheet_pos(name) =
    name == "insert" ? [-50, 80, 0] :
    name == "motor_shaft" ? [0, 80, 0] :
    name == "ir" ? [50, 80, 0] :
    name == "journal" ? [0, 56, 0] :
    name == "bearing_od" ? [-48, 22, 0] :
    name == "nut_socket" ? [45, 22, 0] :
    name == "tip_bore" ? [-40, -12, 0] :
    name == "key" ? [40, -12, 0] :
    name == "well" ? [0, -62, 0] :
    name == "locate" ? [10, -96, 0] :
    [0, 0, 0];

module _place(name, which) {
    if (which == name || which == "all")
        translate(which == "all" ? _sheet_pos(name) : [0, 0, 0])
            children();
}

module fit_test(which = coupon) {
    _place("motor_shaft", which) coupon_motor_shaft();
    _place("journal", which) coupon_journal();
    _place("bearing_od", which) coupon_bearing_od();
    _place("nut_socket", which) coupon_nut_socket();
    _place("tip_bore", which) coupon_tip_bore();
    _place("key", which) coupon_key();
    _place("well", which) coupon_well();
    _place("insert", which) coupon_insert();
    _place("locate", which) coupon_locate();
    _place("ir", which) coupon_ir();
}


fit_test();
