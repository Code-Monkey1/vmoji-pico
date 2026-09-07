include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <motor-base-common.scad>


/* [Motor] */
// Must match motor-collet.scad
motor_d = 24; // [20:0.1:40]
motor_h = 12; // [8:0.5:40]


/* [Gear train] */
gear_mod = 1.25; // [0.5:0.05:2]
pinion_teeth = 14; // [10:1:30]
driven_teeth = 28; // [16:1:60]
gear_helical = 25; // [0:1:40]
gear_backlash = 0.3; // [0:0.05:1]
gear_thickness = 10; // [6:0.5:20]
// Must match motor-pinion.scad hub under the teeth.
pinion_hub_h = 3; // [1:0.5:8]
// Must match driven-gear.scad hub above the teeth.
driven_hub_h = 6; // [3:0.5:12]


/* [Ring] */
ring_id = 21.5; // [10:0.1:60]
ring_od = 41; // [20:0.1:100]
ring_h = 1.2; // [0.6:0.1:4]
ring_standoff = 1.5; // [0.5:0.1:4]


/* [Collet pocket] */
// Must match motor-collet.scad
collet_wall = 4.5; // [2:0.5:6]
collet_flange_od = 48; // [30:0.5:60]
collet_flange_h = 3; // [2:0.5:6]
flange_bolt_r = 20; // [10:0.5:28]
flange_bolt_count = 3; // [3:1:6]
key_w = 8; // [4:0.5:16]
key_d = 2.5; // [1:0.5:6]
wire_slot_w = 4; // [2:0.5:10]
pocket_slop = 0.3; // [0.1:0.05:1]


/* [Bearings] */
bearing_fit = 0.15; // [0:0.05:0.5]
bearing_lip = 1.6; // [1:0.1:3]
shaft_d = 8; // [4:0.1:12]


/* [Base] */
floor_h = 5; // [3:0.5:10]
wall_t = 3; // [2:0.5:6]
deck_margin = 4; // [2:0.5:10]
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
    gear_mod = gear_mod,
    pinion_teeth = pinion_teeth,
    driven_teeth = driven_teeth,
    gear_helical = gear_helical,
    gear_backlash = gear_backlash,
    gear_thickness = gear_thickness,
    pinion_hub_h = pinion_hub_h,
    driven_hub_h = driven_hub_h,
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
    pocket_slop = pocket_slop,
    bearing_fit = bearing_fit,
    bearing_lip = bearing_lip,
    shaft_d = shaft_d,
    floor_h = floor_h,
    wall_t = wall_t,
    deck_margin = deck_margin,
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
    nut_trap_depth = nut_trap_depth,
    teardrop_holes = teardrop_holes
) {
    eps = cut_overlap;
    collet_od = mb_collet_od(motor_d, collet_wall);
    well_d = collet_od + 2 * pocket_slop;
    bolt_angles = mb_flange_bolt_angles(flange_bolt_count);
    mount_hole_d = mb_clearance_hole_d(mount_screw);

    motor_y = mb_gear_center_dist(
        gear_mod, pinion_teeth, driven_teeth, gear_helical, gear_backlash
    );
    driven_od = mb_gear_outer_d(driven_teeth, gear_mod, gear_helical);
    pinion_od = mb_gear_outer_d(pinion_teeth, gear_mod, gear_helical);

    bearing_od = mb_bearing_od();
    bearing_h = mb_bearing_h();
    bearing_pocket_d = mb_bearing_pocket_d(bearing_fit);
    shaft_clear = mb_shaft_clear_d(shaft_d);

    // Z stack: motor face → pinion hub → meshing teeth → driven hub → TX deck.
    gear_z0 = motor_h + pinion_hub_h;
    gear_z1 = gear_z0 + gear_thickness;
    driven_hub_z1 = gear_z1 + driven_hub_h;
    bot_bearing_z1 = gear_z0;
    bot_bearing_z0 = bot_bearing_z1 - bearing_h;

    layout = mb_layout(
        motor_y, motor_d, collet_flange_od, driven_od, pinion_od,
        ring_od, bearing_pocket_d, deck_margin, wall_t
    );
    deck_half_x = mb_layout_get(layout, "deck_half_x");
    deck_half_y = mb_layout_get(layout, "deck_half_y");
    col_d = mb_layout_get(layout, "col_d");
    col_inset = mb_layout_get(layout, "col_inset");
    col_coords = mb_layout_get(layout, "col_coords");
    cavity_half_x = mb_layout_get(layout, "cavity_half_x");
    cavity_half_y = mb_layout_get(layout, "cavity_half_y");
    deck_x = 2 * deck_half_x;
    deck_y = 2 * deck_half_y;

    porch_x0 = deck_half_x - wall_t;
    porch_outer_x = porch_inner_x + 2 * wall_t;
    porch_outer_y = porch_inner_y + 2 * wall_t;
    porch_x1 = porch_x0 + porch_outer_x;
    porch_h = floor_h + porch_inner_z;

    post_inset = wall_t + post_d / 2 + 1;
    post_coords = [
        [porch_x0 + post_inset,  porch_inner_y / 2 - post_d / 2 - 1],
        [porch_x0 + post_inset, -(porch_inner_y / 2 - post_d / 2 - 1)],
        [porch_x1 - post_inset,  porch_inner_y / 2 - post_d / 2 - 1],
        [porch_x1 - post_inset, -(porch_inner_y / 2 - post_d / 2 - 1)]
    ];

    motor_ys = [motor_y, -motor_y];
    ear_pts = [
        [-deck_half_x,  deck_half_y - ear_w / 2 - 2],
        [-deck_half_x, -(deck_half_y - ear_w / 2 - 2)],
        [porch_x1,  porch_outer_y / 2 - ear_w / 2],
        [porch_x1, -(porch_outer_y / 2 - ear_w / 2)]
    ];

    assert(ring_od > ring_id, "ring_od must exceed ring_id");
    assert(floor_h > collet_flange_h,
        "floor_h must exceed collet_flange_h so the underside pocket has a shelf");
    assert(porch_inner_x > switch_body_depth + 5,
        "porch_inner_x too shallow for switch body");
    assert(porch_inner_z > switch_cutout_h + 2,
        "porch_inner_z too short for switch cutout");
    assert(bot_bearing_z0 > 1,
        "bottom bearing collides with floor; reduce pinion_hub_h or raise motor_h stack");
    assert(gear_z0 > motor_h,
        "gear mesh must clear motor face");
    // Motor cans sit below the driven gear; ensure they clear the bottom bearing boss.
    assert(
        motor_y - motor_d / 2 > (bearing_pocket_d + 2 * wall_t) / 2 + 0.5,
        "motor can intersects bottom bearing boss; increase gear_mod or tooth counts"
    );

    // Columns end at the driven-hub plane; separate TX deck bolts on above.
    col_top_z = driven_hub_z1;

    diff() {
        union() {
            // Main deck floor footprint (rounded rect).
            cuboid(
                [deck_x, deck_y, floor_h],
                anchor = BOTTOM,
                rounding = 6,
                edges = "Z"
            );

            // Corner columns up to the driven-hub plane (TX deck bolts on top).
            for (c = col_coords)
                translate([c.x, c.y, floor_h - eps])
                    cyl(
                        d = col_d,
                        h = col_top_z - floor_h + eps,
                        anchor = BOTTOM
                    );

            // Bottom bearing boss (from floor up to the gear mesh plane).
            cyl(
                d = bearing_pocket_d + 2 * wall_t,
                h = bot_bearing_z1,
                anchor = BOTTOM
            );

            // Porch for electronics.
            right(porch_x0)
                cuboid(
                    [porch_outer_x, porch_outer_y, porch_h],
                    anchor = LEFT + BOTTOM,
                    chamfer = 1,
                    edges = [FRONT + RIGHT, BACK + RIGHT]
                );

            for (p = post_coords)
                translate([p.x, p.y, floor_h - eps])
                    cyl(d = post_d, h = porch_inner_z + eps, anchor = BOTTOM);

            for (p = ear_pts)
                translate([p.x, p.y, 0])
                    cuboid(
                        [ear_stick + 1, ear_w, floor_h],
                        anchor = (p.x > 0 ? LEFT : RIGHT) + BOTTOM,
                        rounding = 2,
                        edges = "Z"
                    );
        }

        tag("remove") {
            // Dual motor wells + keyed flange pockets.
            for (my = motor_ys) {
                back(my) {
                    down(eps / 2)
                        linear_extrude(height = collet_flange_h + eps)
                            offset(delta = pocket_slop)
                                mb_flange_profile(collet_flange_od, key_w, key_d);

                    down(eps / 2)
                        cyl(d = well_d, h = motor_h + eps, anchor = BOTTOM);

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

                    // Wire chase from each motor toward +X porch.
                    up(collet_flange_h / 2)
                        right(well_d / 4)
                            cuboid(
                                [
                                    porch_x0 + wall_t + 4 - well_d / 4,
                                    wire_slot_w + 2 * pocket_slop,
                                    collet_flange_h + 1
                                ],
                                anchor = LEFT + CENTER
                            );
                }
            }

            // Chimneys into porch for motor leads.
            for (my = motor_ys)
                down(eps / 2)
                    right(porch_x0 + wall_t + 3)
                        back(my * 0.35)
                            cuboid(
                                [max(wire_slot_w + 4, 10), wire_slot_w + 6, floor_h + 2 * eps],
                                anchor = BOTTOM
                            );

            // Gear cavity between bearings (open toward ±Y for pinion mesh).
            up(bot_bearing_z1 - 0.5)
                cuboid(
                    [
                        2 * cavity_half_x,
                        2 * cavity_half_y,
                        gear_thickness + driven_hub_h + 1.2
                    ],
                    anchor = BOTTOM,
                    rounding = 2,
                    edges = "Z"
                );

            // Bottom 608 pocket + shaft clearance + underside nut/e-clip access.
            up(bot_bearing_z0)
                cyl(d = bearing_pocket_d, h = bearing_h + eps, anchor = BOTTOM);
            down(eps / 2)
                cyl(
                    d = shaft_clear,
                    h = bot_bearing_z1 + eps,
                    anchor = BOTTOM
                );
            // Countersink under floor for M8 nylock / e-clip.
            down(eps / 2)
                cyl(d = 14, h = 2.5 + eps, anchor = BOTTOM);

            // M3 screw holes down the corner columns for the TX deck.
            for (c = col_coords)
                translate([c.x, c.y, col_top_z + eps])
                    screw_hole(
                        mount_screw,
                        l = 12 + eps,
                        teardrop = teardrop_holes,
                        anchor = TOP,
                        orient = UP
                    );

            // Porch cavity.
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

            // Passage from gear / motor area into porch.
            up(floor_h)
                right(deck_half_x - wall_t - eps)
                    cuboid(
                        [wall_t + 4, max(wire_slot_w + 16, 20), min(porch_inner_z, motor_h) + eps],
                        anchor = LEFT + BOTTOM
                    );

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

            // Lid screw holes + nut traps.
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

            // Ear holes + glue feet.
            for (p = ear_pts) {
                ear_dir = p.x > 0 ? 1 : -1;
                translate([p.x + ear_dir * (ear_stick + 1) / 2, p.y, 0]) {
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
}


motor_base();
