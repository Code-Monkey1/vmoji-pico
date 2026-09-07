include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <motor-base-common.scad>


/* [Motor] */
// Must match motor-collet.scad
motor_d = 24; // [20:0.1:40]
motor_h = 12; // [8:0.5:40]


/* [Ring] */
// Copper induction ring diameters (mm).
ring_id = 21.5; // [10:0.1:60]
ring_od = 41; // [20:0.1:100]
ring_h = 1.2; // [0.6:0.1:4]
ring_standoff = 1.5; // [0.5:0.1:4]


/* [Collet pocket] */
// Must match motor-collet.scad
collet_wall = 4.5; // [2:0.5:6]
collet_flange_od = 54; // [36:0.5:70]
collet_flange_h = 3; // [2:0.5:6]
flange_bolt_r = 23.5; // [14:0.5:35]
flange_bolt_count = 3; // [3:1:6]
key_w = 8; // [4:0.5:16]
key_d = 2.5; // [1:0.5:6]
wire_slot_w = 4; // [2:0.5:10]
wire_slot_h = 5; // [3:0.5:10]
pocket_slop = 0.3; // [0.1:0.05:1]


/* [Base] */
deck_od = 60; // [45:0.5:90]
floor_h = 4; // [2:0.5:10]
wall_t = 2.5; // [1.5:0.5:5]
porch_inner_x = 50; // [30:1:100]
porch_inner_y = 72; // [40:1:120]
porch_inner_z = 32; // [18:1:50]
ear_w = 12; // [8:0.5:20]
ear_stick = 8; // [4:0.5:16]
glue_foot_d = 12; // [8:0.5:20]
glue_foot_h = 0.8; // [0.4:0.1:2]


/* [Switch] */
switch_cutout_w = 16.4; // [8:0.1:40]
switch_cutout_h = 27.4; // [10:0.1:50]
switch_body_depth = 25; // [10:0.5:40]


/* [Cable] */
cable_hole_d = 8; // [4:0.5:16]


/* [Hardware] */
mount_screw = "M3";
lid_screw = "M3";
lid_t = 2.5; // [1.5:0.5:5]
post_d = 8; // [6:0.5:14]
post_hole_extra_d = 0.5; // [0:0.1:3]
nut_trap_depth = 2.7; // [2:0.1:8]
teardrop_holes = true; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_base(
    motor_d = motor_d,
    motor_h = motor_h,
    ring_id = ring_id,
    ring_od = ring_od,
    ring_h = ring_h,
    ring_standoff = ring_standoff,
    collet_wall = collet_wall,
    collet_flange_od = collet_flange_od,
    collet_flange_h = collet_flange_h,
    flange_bolt_r = flange_bolt_r,
    flange_bolt_count = flange_bolt_count,
    key_w = key_w,
    key_d = key_d,
    wire_slot_w = wire_slot_w,
    wire_slot_h = wire_slot_h,
    pocket_slop = pocket_slop,
    deck_od = deck_od,
    floor_h = floor_h,
    wall_t = wall_t,
    porch_inner_x = porch_inner_x,
    porch_inner_y = porch_inner_y,
    porch_inner_z = porch_inner_z,
    ear_w = ear_w,
    ear_stick = ear_stick,
    glue_foot_d = glue_foot_d,
    glue_foot_h = glue_foot_h,
    switch_cutout_w = switch_cutout_w,
    switch_cutout_h = switch_cutout_h,
    switch_body_depth = switch_body_depth,
    cable_hole_d = cable_hole_d,
    mount_screw = mount_screw,
    lid_screw = lid_screw,
    lid_t = lid_t,
    post_d = post_d,
    post_hole_extra_d = post_hole_extra_d,
    nut_trap_depth = nut_trap_depth,
    teardrop_holes = teardrop_holes
) {
    eps = cut_overlap;
    collet_od = mb_collet_od(motor_d, collet_wall);
    well_d = collet_od + 2 * pocket_slop;
    bolt_angles = mb_flange_bolt_angles(flange_bolt_count);
    mount_hole_d = mb_clearance_hole_d(mount_screw);

    deck_top_z = floor_h + motor_h;
    ring_z = deck_top_z + ring_standoff;
    seat_top_z = ring_z + ring_h + 1.2;
    porch_h = floor_h + porch_inner_z;

    porch_x0 = deck_od / 2 - wall_t;
    porch_outer_x = porch_inner_x + 2 * wall_t;
    porch_outer_y = porch_inner_y + 2 * wall_t;
    porch_x1 = porch_x0 + porch_outer_x;

    post_inset = wall_t + post_d / 2 + 1;
    post_coords = [
        [porch_x0 + post_inset,  porch_inner_y / 2 - post_d / 2 - 1],
        [porch_x0 + post_inset, -(porch_inner_y / 2 - post_d / 2 - 1)],
        [porch_x1 - post_inset,  porch_inner_y / 2 - post_d / 2 - 1],
        [porch_x1 - post_inset, -(porch_inner_y / 2 - post_d / 2 - 1)]
    ];

    // Ears on deck rim (-X) and porch front corners (+X).
    deck_ear_angles = [150, 210];
    porch_ear_pts = [
        [porch_x1,  (porch_outer_y / 2 - ear_w / 2)],
        [porch_x1, -(porch_outer_y / 2 - ear_w / 2)]
    ];

    assert(ring_od > ring_id, "ring_od must exceed ring_id");
    assert(ring_od < deck_od - 2, "deck_od too small for ring_od");
    assert(flange_bolt_r > ring_od / 2 + mount_hole_d / 2,
        "flange_bolt_r must sit outside the ring");
    assert(floor_h > collet_flange_h,
        "floor_h must exceed collet_flange_h so the underside pocket has a shelf");
    assert(porch_inner_x > switch_body_depth + 5,
        "porch_inner_x too shallow for switch body");
    assert(porch_inner_z > switch_cutout_h + 2,
        "porch_inner_z too short for switch cutout");
    // well_d > ring_id: ring has no full inner lip; collet-top standoffs carry it.
    assert(well_d < ring_od,
        "collet well must leave an outer ring land on the deck");

    diff() {
        union() {
            cyl(d = deck_od, h = seat_top_z, anchor = BOTTOM);

            right(porch_x0)
                cuboid(
                    [porch_outer_x, porch_outer_y, porch_h],
                    anchor = LEFT + BOTTOM,
                    chamfer = 1,
                    edges = [FRONT + RIGHT, BACK + RIGHT]
                );

            for (a = deck_ear_angles)
                zrot(a)
                    right(deck_od / 2 - 1)
                        cuboid(
                            [ear_stick + 1, ear_w, floor_h],
                            anchor = LEFT + BOTTOM,
                            rounding = 2,
                            edges = "Z"
                        );

            for (p = porch_ear_pts)
                translate([p.x, p.y, 0])
                    cuboid(
                        [ear_stick + 1, ear_w, floor_h],
                        anchor = LEFT + BOTTOM,
                        rounding = 2,
                        edges = "Z"
                    );

            // Lid posts in the main union so they stay connected.
            for (p = post_coords)
                translate([p.x, p.y, floor_h - eps])
                    cyl(d = post_d, h = porch_inner_z + eps, anchor = BOTTOM);
        }

        tag("remove") {
            // Underside keyed flange pocket (collet inserts from below).
            down(eps / 2)
                linear_extrude(height = collet_flange_h + eps)
                    offset(delta = pocket_slop)
                        mb_flange_profile(collet_flange_od, key_w, key_d);

            // Barrel well through floor + deck (flange stays under the floor).
            down(eps / 2)
                cyl(
                    d = well_d,
                    h = seat_top_z + eps,
                    anchor = BOTTOM
                );

            // Flange bolts from above (outside the ring) into the underside flange.
            for (a = bolt_angles)
                zrot(a)
                    right(flange_bolt_r)
                        down(eps / 2)
                            screw_hole(
                                mount_screw,
                                l = floor_h + eps,
                                teardrop = teardrop_holes,
                                anchor = BOTTOM,
                                orient = UP
                            );

            // Wire chase: underside flange pocket → under porch → up into porch cavity.
            up(collet_flange_h / 2)
                right(well_d / 4)
                    cuboid(
                        [
                            porch_x0 + wall_t + 6 - well_d / 4,
                            wire_slot_w + 2 * pocket_slop,
                            collet_flange_h + 1
                        ],
                        anchor = LEFT + CENTER
                    );
            // Vertical chimney into the porch.
            down(eps / 2)
                right(porch_x0 + wall_t + 3)
                    cuboid(
                        [
                            max(wire_slot_w + 4, 10),
                            wire_slot_w + 6,
                            floor_h + 2 * eps
                        ],
                        anchor = BOTTOM
                    );

            // Porch cavity (posts are subtracted through then… avoid eating posts:
            // cavity is a cuboid that does not include post cylinders — use
            // difference in the remove tag).
            up(floor_h)
                difference() {
                    right(porch_x0 + wall_t)
                        cuboid(
                            [porch_inner_x, porch_inner_y, porch_inner_z + eps],
                            anchor = LEFT + BOTTOM
                        );
                    for (p = post_coords)
                        translate([p.x, p.y, -eps])
                            cyl(d = post_d + 0.2, h = porch_inner_z + 3 * eps, anchor = BOTTOM);
                }

            // Passage from well into porch (above the floor).
            up(floor_h)
                right(well_d / 2 - eps)
                    cuboid(
                        [
                            porch_x0 + wall_t - well_d / 2 + 2 * eps,
                            max(wire_slot_w + 8, 12),
                            min(porch_inner_z, motor_h) + eps
                        ],
                        anchor = LEFT + BOTTOM
                    );

            // Outer ring rebate land (groove). Inner span is open to the well;
            // collet-top standoffs carry the ring across the middle.
            up(ring_z)
                difference() {
                    cyl(
                        d = ring_od + 2 * $slop + 1.2,
                        h = ring_h + eps,
                        anchor = BOTTOM
                    );
                    down(eps)
                        cyl(
                            d = max(well_d, ring_id),
                            h = ring_h + 3 * eps,
                            anchor = BOTTOM
                        );
                }

            up(ring_z + ring_h - eps / 2)
                cyl(d = ring_od + 2 * $slop, h = 3, anchor = BOTTOM);

            // Switch cutout on porch +X face.
            up(floor_h + porch_inner_z / 2)
                right(porch_x1)
                    cuboid(
                        [wall_t + 2, switch_cutout_w, switch_cutout_h],
                        anchor = RIGHT + CENTER,
                        rounding = 1,
                        edges = "X"
                    );

            // Cable hole on porch +Y wall.
            up(floor_h + porch_inner_z / 2)
                right(porch_x0 + wall_t + porch_inner_x / 2)
                    back(porch_outer_y / 2)
                        cyl(
                            d = cable_hole_d,
                            h = wall_t + 2,
                            anchor = CENTER,
                            orient = BACK
                        );

            // Lid screw holes through posts + nut traps from below.
            for (p = post_coords) {
                translate([p.x, p.y, floor_h - eps])
                    screw_hole(
                        lid_screw,
                        l = porch_inner_z + 2 * eps,
                        teardrop = teardrop_holes,
                        anchor = BOTTOM,
                        orient = UP
                    )
                        position(BOT)
                            nut_trap_inline(
                                l = nut_trap_depth + eps,
                                spec = lid_screw,
                                anchor = BOT
                            );
            }

            // Ear M3 holes + hot-glue foot recesses.
            for (a = deck_ear_angles)
                zrot(a)
                    right(deck_od / 2 - 1 + (ear_stick + 1) / 2) {
                        down(eps / 2)
                            screw_hole(
                                mount_screw,
                                l = floor_h + eps,
                                teardrop = teardrop_holes,
                                anchor = BOTTOM,
                                orient = UP
                            );
                        down(eps / 2)
                            cyl(d = glue_foot_d, h = glue_foot_h + eps, anchor = BOTTOM);
                    }
            for (p = porch_ear_pts)
                translate([p.x + (ear_stick + 1) / 2, p.y, 0]) {
                    down(eps / 2)
                        screw_hole(
                            mount_screw,
                            l = floor_h + eps,
                            teardrop = teardrop_holes,
                            anchor = BOTTOM,
                            orient = UP
                        );
                    down(eps / 2)
                        cyl(d = glue_foot_d, h = glue_foot_h + eps, anchor = BOTTOM);
                }
        }
    }
}


motor_base();
