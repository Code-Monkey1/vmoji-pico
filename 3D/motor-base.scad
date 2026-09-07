// Dual-motor base: bottom 608 only, plastic shaft through coils (see driven-shaft.scad).
// Column tops take M3 heat-set inserts for the TX deck bolts.
// Printed skirt under the floor clears the M8 SHCS head so the base sits flush/stable.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Base-only] */
wire_slot_w = 4; // [2:0.5:10]
ear_w = 12; // [8:0.5:20]
ear_stick = 8; // [4:0.5:16]
switch_cutout_w = 16.4; // [8:0.1:40]
switch_cutout_h = 27.4; // [10:0.1:50]
switch_body_depth = 25; // [10:0.5:40]
cable_hole_d = 8; // [4:0.5:16]
mount_screw = "M3";
lid_screw = "M3";
post_d = 8; // [6:0.5:14]
nut_trap_depth = 2.7; // [2:0.1:8]
teardrop_holes = true; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_base(
    motor_d = vm_motor_d,
    motor_h = vm_motor_h,
    collet_wall = vm_collet_wall,
    collet_flange_od = vm_collet_flange_od,
    collet_flange_h = vm_collet_flange_h,
    flange_bolt_r = vm_flange_bolt_r,
    flange_bolt_count = vm_flange_bolt_count,
    key_w = vm_key_w,
    key_d = vm_key_d,
    wire_slot_w = wire_slot_w,
    pocket_slop = vm_pocket_slop,
    floor_h = vm_floor_h,
    wall_t = vm_wall_t,
    deck_margin = vm_deck_margin,
    porch_inner_x = vm_porch_inner_x,
    porch_inner_y = vm_porch_inner_y,
    porch_inner_z = vm_porch_inner_z,
    ear_w = ear_w,
    ear_stick = ear_stick,
    switch_cutout_w = switch_cutout_w,
    switch_cutout_h = switch_cutout_h,
    switch_body_depth = switch_body_depth,
    cable_hole_d = cable_hole_d,
    mount_screw = mount_screw,
    lid_screw = lid_screw,
    post_d = post_d,
    nut_trap_depth = nut_trap_depth,
    teardrop_holes = teardrop_holes,
    skirt_h = vm_skirt_h,
    skirt_wall = vm_skirt_wall
) {
    eps = cut_overlap;
    collet_od = mb_collet_od(motor_d, collet_wall);
    well_d = collet_od + 2 * pocket_slop;
    bolt_angles = mb_flange_bolt_angles(flange_bolt_count);

    motor_y = mb_gear_center_dist();
    driven_od = mb_gear_outer_d(vm_driven_teeth);
    pinion_od = mb_gear_outer_d(vm_pinion_teeth);
    bearing_h = mb_bearing_h();
    bearing_pocket_d = mb_bearing_pocket_d();
    shaft_clear = mb_shaft_clear_d();

    gear_z0 = vm_gear_z0();
    bot_bearing_z0 = vm_bot_bearing_z0();
    bot_bearing_z1 = vm_bot_bearing_z1();
    col_top_z = vm_col_top_z();

    layout = mb_layout(
        motor_y, motor_d, collet_flange_od, driven_od, pinion_od,
        vm_ring_od, bearing_pocket_d, deck_margin, wall_t
    );
    deck_half_x = mb_layout_get(layout, "deck_half_x");
    deck_half_y = mb_layout_get(layout, "deck_half_y");
    col_d = mb_layout_get(layout, "col_d");
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

    vm_assert_coil_gap_metal_free();
    assert(floor_h > collet_flange_h, "floor_h must exceed collet_flange_h");
    assert(porch_inner_x > switch_body_depth + 5, "porch too shallow for switch");
    assert(porch_inner_z > switch_cutout_h + 2, "porch too short for switch");
    assert(
        motor_y - motor_d / 2 > (bearing_pocket_d + 2 * wall_t) / 2 + 0.5,
        "motor can intersects bottom bearing boss"
    );
    assert(skirt_h > 0, "skirt_h must be positive for flush underside");

    diff() {
        union() {
            cuboid(
                [deck_x, deck_y, floor_h],
                anchor = BOTTOM,
                rounding = 6,
                edges = "Z"
            );

            for (c = col_coords)
                translate([c.x, c.y, floor_h - eps])
                    cyl(
                        d = col_d,
                        h = col_top_z - floor_h + eps,
                        anchor = BOTTOM
                    );

            // Bottom 608 boss up to shaft seat.
            cyl(
                d = bearing_pocket_d + 2 * wall_t,
                h = bot_bearing_z1,
                anchor = BOTTOM
            );

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

            // Continuous skirt: table contact at z=-skirt_h; SHCS head stays above it.
            down(skirt_h) {
                cuboid(
                    [deck_x, deck_y, skirt_h],
                    anchor = BOTTOM,
                    rounding = 6,
                    edges = "Z"
                );
                right(porch_x0)
                    cuboid(
                        [porch_outer_x, porch_outer_y, skirt_h],
                        anchor = LEFT + BOTTOM,
                        chamfer = 1,
                        edges = [FRONT + RIGHT, BACK + RIGHT]
                    );
                for (p = ear_pts)
                    translate([p.x, p.y, 0])
                        cuboid(
                            [ear_stick + 1, ear_w, skirt_h],
                            anchor = (p.x > 0 ? LEFT : RIGHT) + BOTTOM,
                            rounding = 2,
                            edges = "Z"
                        );
            }
        }

        tag("remove") {
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

            for (my = motor_ys)
                down(eps / 2)
                    right(porch_x0 + wall_t + 3)
                        back(my * 0.35)
                            cuboid(
                                [max(wire_slot_w + 4, 10), wire_slot_w + 6, floor_h + 2 * eps],
                                anchor = BOTTOM
                            );

            // Gear cavity (open ±Y for pinion mesh).
            up(bot_bearing_z1 - 0.5)
                cuboid(
                    [
                        2 * cavity_half_x,
                        2 * cavity_half_y,
                        vm_gear_thickness + vm_driven_hub_h + 1.2
                    ],
                    anchor = BOTTOM,
                    rounding = 2,
                    edges = "Z"
                );

            // 608 OD pocket. Outer race sits on the z=0 annulus outside bearing_lip_id.
            up(bot_bearing_z0)
                cyl(d = bearing_pocket_d, h = bearing_h + eps, anchor = BOTTOM);

            // Journal clearance through the bearing ID.
            down(eps / 2)
                cyl(d = shaft_clear, h = bot_bearing_z1 + eps, anchor = BOTTOM);

            // Skirt hollow (leave a solid core under the 608 boss for the OD lip).
            down(skirt_h + eps / 2) {
                difference() {
                    union() {
                        cuboid(
                            [
                                max(eps, deck_x - 2 * skirt_wall),
                                max(eps, deck_y - 2 * skirt_wall),
                                skirt_h + eps
                            ],
                            anchor = BOTTOM,
                            rounding = 4,
                            edges = "Z"
                        );
                        right(porch_x0 + skirt_wall)
                            cuboid(
                                [
                                    max(eps, porch_outer_x - 2 * skirt_wall),
                                    max(eps, porch_outer_y - 2 * skirt_wall),
                                    skirt_h + eps
                                ],
                                anchor = LEFT + BOTTOM
                            );
                    }
                    // Protected core = boss footprint; lip annulus survives around lip_id.
                    cyl(
                        d = bearing_pocket_d + 2 * wall_t,
                        h = skirt_h + 2 * eps,
                        anchor = BOTTOM
                    );
                }

                // Through the lip: washer seats up against the 608 inner race.
                cyl(
                    d = vm_bearing_lip_id,
                    h = skirt_h + eps,
                    anchor = BOTTOM
                );

                // Head well (narrower than lip; keeps the screw centered).
                cyl(
                    d = vm_bolt_head_pocket_d,
                    h = skirt_h + eps,
                    anchor = BOTTOM
                );
            }

            // M3 heat-set insert pilots in column tops (not threads in plastic).
            for (c = col_coords)
                translate([c.x, c.y, col_top_z + eps])
                    cyl(
                        d = vm_insert_hole_d + 2 * $slop,
                        h = vm_insert_depth + eps,
                        anchor = TOP
                    );

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

            up(floor_h)
                right(deck_half_x - wall_t - eps)
                    cuboid(
                        [wall_t + 4, max(wire_slot_w + 16, 20), min(porch_inner_z, motor_h) + eps],
                        anchor = LEFT + BOTTOM
                    );

            up(floor_h + porch_inner_z / 2)
                right(porch_x1)
                    cuboid(
                        [wall_t + 2, switch_cutout_w, switch_cutout_h],
                        anchor = RIGHT + CENTER,
                        rounding = 1,
                        edges = "X"
                    );

            up(floor_h + porch_inner_z / 2)
                right(porch_x0 + wall_t + porch_inner_x / 2)
                    back(porch_outer_y / 2)
                        cyl(
                            d = cable_hole_d,
                            h = wall_t + 2,
                            anchor = CENTER,
                            orient = BACK
                        );

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

            // Optional bench-mount holes through floor + skirt.
            for (p = ear_pts) {
                ear_dir = p.x > 0 ? 1 : -1;
                translate([p.x + ear_dir * (ear_stick + 1) / 2, p.y, 0])
                    down(skirt_h + eps / 2)
                        screw_hole(
                            mount_screw,
                            l = floor_h + skirt_h + eps,
                            teardrop = teardrop_holes,
                            anchor = BOTTOM,
                            orient = UP
                        );
            }
        }
    }
}


motor_base();
