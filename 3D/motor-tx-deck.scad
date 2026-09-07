// TX deck: flanged plastic bushing only — no steel bearing under the TX coil.
// Bolts into M3 heat-set inserts in motor-base column tops.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Hardware] */
mount_screw = "M3";
teardrop_holes = true; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_tx_deck(
    mount_screw = mount_screw,
    teardrop_holes = teardrop_holes
) {
    eps = cut_overlap;
    motor_y = mb_gear_center_dist();
    driven_od = mb_gear_outer_d(vm_driven_teeth);
    pinion_od = mb_gear_outer_d(vm_pinion_teeth);
    bearing_pocket_d = mb_bearing_pocket_d();
    bushing_id = mb_bushing_id();

    layout = mb_layout(
        motor_y, vm_motor_d, vm_collet_flange_od, driven_od, pinion_od,
        vm_ring_od, bearing_pocket_d, vm_deck_margin, vm_wall_t
    );
    deck_half_x = mb_layout_get(layout, "deck_half_x");
    deck_half_y = mb_layout_get(layout, "deck_half_y");
    col_d = mb_layout_get(layout, "col_d");
    col_coords = mb_layout_get(layout, "col_coords");
    deck_x = 2 * deck_half_x;
    deck_y = 2 * deck_half_y;

    // Part local z=0 = underside seated on column tops.
    flange_h = vm_bushing_flange_h;
    plate_z0 = flange_h;
    ring_z = plate_z0 + vm_deck_plate_t + vm_ring_standoff;
    seat_top_z = ring_z + vm_ring_h + 1.2;

    vm_assert_coil_gap_metal_free();
    assert(vm_ring_od > vm_ring_id, "ring_od must exceed ring_id");

    diff() {
        union() {
            // Flanged plastic bushing (flange on underside).
            cyl(d = vm_bushing_flange_d, h = flange_h, anchor = BOTTOM);
            up(flange_h - eps)
                cyl(
                    d = max(vm_bushing_flange_d - 2, bushing_id + 4),
                    h = vm_bushing_len + eps,
                    anchor = BOTTOM
                );

            // TX deck plate (plastic only under the coil).
            up(plate_z0)
                cuboid(
                    [deck_x, deck_y, vm_deck_plate_t + vm_ring_standoff + vm_ring_h + 1.5],
                    anchor = BOTTOM,
                    rounding = 6,
                    edges = "Z"
                );

            // Column registration bosses.
            for (c = col_coords)
                translate([c.x, c.y, 0])
                    cyl(d = col_d + 2, h = plate_z0 + eps, anchor = BOTTOM);

            // Plastic TX ring standoffs.
            up(plate_z0 + vm_deck_plate_t - eps)
                zrot_copies(n = 3, sa = 90)
                    right((vm_ring_id + vm_ring_od) / 4)
                        cyl(d = 4.5, h = vm_ring_standoff + eps, anchor = BOTTOM);
        }

        tag("remove") {
            // Bushing bore for plastic Ø8 shaft.
            down(eps / 2)
                cyl(d = bushing_id, h = seat_top_z + eps, anchor = BOTTOM);

            // TX ring rebate.
            up(ring_z)
                difference() {
                    cyl(
                        d = vm_ring_od + 2 * $slop + 1.2,
                        h = vm_ring_h + eps,
                        anchor = BOTTOM
                    );
                    down(eps)
                        cyl(
                            d = max(bushing_id + 2, vm_ring_id),
                            h = vm_ring_h + 3 * eps,
                            anchor = BOTTOM
                        );
                }
            up(ring_z + vm_ring_h - eps / 2)
                cyl(d = vm_ring_od + 2 * $slop, h = 3, anchor = BOTTOM);

            // Clearance bolts into column heat-set inserts.
            for (c = col_coords)
                translate([c.x, c.y, -eps / 2])
                    screw_hole(
                        mount_screw,
                        l = seat_top_z + eps,
                        teardrop = teardrop_holes,
                        anchor = BOTTOM,
                        orient = UP
                    );
        }
    }
}


motor_tx_deck();
