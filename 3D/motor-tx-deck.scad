include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <motor-base-common.scad>


/* [Gear train — must match motor-base.scad] */
gear_mod = 1.25; // [0.5:0.05:2]
pinion_teeth = 14; // [10:1:30]
driven_teeth = 28; // [16:1:60]
gear_helical = 25; // [0:1:40]
gear_backlash = 0.3; // [0:0.05:1]
motor_h = 12; // [8:0.5:40]
pinion_hub_h = 3; // [1:0.5:8]
gear_thickness = 10; // [6:0.5:20]
driven_hub_h = 6; // [3:0.5:12]


/* [Ring] */
ring_id = 21.5; // [10:0.1:60]
ring_od = 41; // [20:0.1:100]
ring_h = 1.2; // [0.6:0.1:4]
ring_standoff = 1.5; // [0.5:0.1:4]


/* [Layout — must match motor-base.scad] */
collet_flange_od = 48; // [30:0.5:60]
deck_margin = 4; // [2:0.5:10]
wall_t = 3; // [2:0.5:6]
bearing_fit = 0.15; // [0:0.05:0.5]
bearing_lip = 1.6; // [1:0.1:3]
shaft_d = 8; // [4:0.1:12]


/* [Hardware] */
mount_screw = "M3";
teardrop_holes = true; // [true, false]
deck_plate_t = 4; // [2:0.5:8]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_tx_deck(
    gear_mod = gear_mod,
    pinion_teeth = pinion_teeth,
    driven_teeth = driven_teeth,
    gear_helical = gear_helical,
    gear_backlash = gear_backlash,
    motor_h = motor_h,
    pinion_hub_h = pinion_hub_h,
    gear_thickness = gear_thickness,
    driven_hub_h = driven_hub_h,
    ring_id = ring_id,
    ring_od = ring_od,
    ring_h = ring_h,
    ring_standoff = ring_standoff,
    collet_flange_od = collet_flange_od,
    deck_margin = deck_margin,
    wall_t = wall_t,
    bearing_fit = bearing_fit,
    bearing_lip = bearing_lip,
    shaft_d = shaft_d,
    mount_screw = mount_screw,
    teardrop_holes = teardrop_holes,
    deck_plate_t = deck_plate_t
) {
    eps = cut_overlap;
    motor_y = mb_gear_center_dist(
        gear_mod, pinion_teeth, driven_teeth, gear_helical, gear_backlash
    );
    driven_od = mb_gear_outer_d(driven_teeth, gear_mod, gear_helical);
    pinion_od = mb_gear_outer_d(pinion_teeth, gear_mod, gear_helical);
    bearing_od = mb_bearing_od();
    bearing_h = mb_bearing_h();
    bearing_pocket_d = mb_bearing_pocket_d(bearing_fit);
    shaft_clear = mb_shaft_clear_d(shaft_d);

    layout = mb_layout(
        motor_y, 0, collet_flange_od, driven_od, pinion_od,
        ring_od, bearing_pocket_d, deck_margin, wall_t
    );
    deck_half_x = mb_layout_get(layout, "deck_half_x");
    deck_half_y = mb_layout_get(layout, "deck_half_y");
    col_d = mb_layout_get(layout, "col_d");
    col_coords = mb_layout_get(layout, "col_coords");
    deck_x = 2 * deck_half_x;
    deck_y = 2 * deck_half_y;

    // Part is modeled with its underside (column seat) at z=0.
    // Bearing pocket sits above a thin lip, then plate, then TX ring land.
    plate_z0 = bearing_h + bearing_lip;
    ring_z = plate_z0 + deck_plate_t + ring_standoff;
    seat_top_z = ring_z + ring_h + 1.2;

    assert(ring_od > ring_id, "ring_od must exceed ring_id");

    diff() {
        union() {
            // Top bearing housing (bearing inserts from below into this pocket).
            cyl(
                d = bearing_pocket_d + 2 * wall_t,
                h = bearing_h + bearing_lip + eps,
                anchor = BOTTOM
            );

            // Main TX deck plate.
            up(plate_z0)
                cuboid(
                    [deck_x, deck_y, deck_plate_t + ring_standoff + ring_h + 1.5],
                    anchor = BOTTOM,
                    rounding = 6,
                    edges = "Z"
                );

            // Column registration bosses (sit on motor-base column tops).
            for (c = col_coords)
                translate([c.x, c.y, 0])
                    cyl(d = col_d + 2, h = plate_z0 + eps, anchor = BOTTOM);

            // Plastic TX ring standoffs.
            up(plate_z0 + deck_plate_t - eps)
                zrot_copies(n = 3, sa = 90)
                    right((ring_id + ring_od) / 4)
                        cyl(d = 4.5, h = ring_standoff + eps, anchor = BOTTOM);
        }

        tag("remove") {
            // 608 pocket from below, with shaft clearance through.
            up(bearing_lip)
                cyl(d = bearing_pocket_d, h = bearing_h + eps, anchor = BOTTOM);
            down(eps / 2)
                cyl(d = shaft_clear, h = seat_top_z + eps, anchor = BOTTOM);

            // TX ring rebate.
            up(ring_z)
                difference() {
                    cyl(
                        d = ring_od + 2 * $slop + 1.2,
                        h = ring_h + eps,
                        anchor = BOTTOM
                    );
                    down(eps)
                        cyl(
                            d = max(shaft_clear + 2, ring_id),
                            h = ring_h + 3 * eps,
                            anchor = BOTTOM
                        );
                }
            up(ring_z + ring_h - eps / 2)
                cyl(d = ring_od + 2 * $slop, h = 3, anchor = BOTTOM);

            // Bolt through to motor-base columns.
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
