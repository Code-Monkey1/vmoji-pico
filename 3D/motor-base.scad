// Dual-motor base: bottom 608 on an M8 stud, crush-rib motor wells, insert columns, box (+X).
// Column tops take M3 heat-set inserts (with locating spigots) for the TX deck bolts.
// Printed skirt under the floor clears the M8 SHCS head so the base sits flush/stable.
// Motors press into the wells from above (no collets, no clamp screws); their terminals
// and wires drop through the well ledge into the skirt and run to the box floor slots.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Base-only] */
wire_slot_w = 8; // [2:0.5:10]
ear_w = 12; // [8:0.5:20]
ear_stick = 8; // [4:0.5:16]
switch_cutout_d = 12.4; // [8:0.1:40]
switch_body_depth = 30; // [10:0.5:40]
cable_hole_d = 8; // [4:0.5:16]
mount_screw = "M3";
teardrop_holes = true; // [true, false]
// Notch at the top of the box wall facing the deck (TX coil + IR emitter leads).
deck_wire_notch_w = 12; // [6:0.5:30]
deck_wire_notch_h = 8; // [3:0.5:20]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_base(
    wire_slot_w = wire_slot_w,
    floor_h = vm_floor_h,
    wall_t = vm_wall_t,
    porch_inner_x = vm_porch_inner_x,
    porch_inner_y = vm_porch_inner_y,
    porch_inner_z = vm_porch_inner_z,
    ear_w = ear_w,
    ear_stick = ear_stick,
    switch_cutout_d = switch_cutout_d,
    switch_body_depth = switch_body_depth,
    cable_hole_d = cable_hole_d,
    mount_screw = mount_screw,
    post_d = vm_post_d,
    teardrop_holes = teardrop_holes,
    skirt_h = vm_skirt_h,
    skirt_wall = vm_skirt_wall
) {
    eps = cut_overlap;
    motor_y = mb_gear_center_dist();
    bearing_h = mb_bearing_h();
    bearing_pocket_d = mb_bearing_pocket_d();
    boss_d = mb_bearing_boss_d();
    well_bore_d = mb_well_bore_d();
    well_od = mb_well_od();

    bot_bearing_z0 = vm_bot_bearing_z0();
    bot_bearing_z1 = vm_bot_bearing_z1();
    col_top_z = vm_col_top_z();
    motor_z0 = vm_motor_z0();
    well_floor_z = vm_well_floor_z();
    well_rim_z = vm_well_rim_z();

    layout = mb_layout();
    deck_half_x = mb_layout_get(layout, "deck_half_x");
    deck_half_y = mb_layout_get(layout, "deck_half_y");
    col_d = mb_layout_get(layout, "col_d");
    col_coords = mb_layout_get(layout, "col_coords");
    deck_x = 2 * deck_half_x;
    deck_y = 2 * deck_half_y;

    // Box sits vm_porch_gap beyond the deck edge; a floor bridge joins them.
    porch_x0 = mb_porch_x0(layout);
    porch_outer_x = mb_porch_outer_x();
    porch_outer_y = mb_porch_outer_y();
    porch_x1 = porch_x0 + porch_outer_x;
    porch_h = floor_h + porch_inner_z;
    bridge_x0 = deck_half_x - 8;
    bridge_len = porch_x0 - bridge_x0 + 1;

    post_coords = mb_post_coords(layout, post_d);
    motor_ys = [motor_y, -motor_y];
    ear_pts = [
        [-deck_half_x,  deck_half_y - ear_w / 2 - 2],
        [-deck_half_x, -(deck_half_y - ear_w / 2 - 2)],
        [porch_x1,  porch_outer_y / 2 - ear_w / 2],
        [porch_x1, -(porch_outer_y / 2 - ear_w / 2)]
    ];
    rib_len = well_bore_d / 2 - mb_rib_inner_r() + 0.3;

    vm_assert_layout();
    assert(porch_inner_x > switch_body_depth + 5, "porch too shallow for switch");
    assert(skirt_h > 0, "skirt_h must be positive for flush underside");

    diff() {
        union() {
            cuboid(
                [deck_x, deck_y, floor_h],
                anchor = BOTTOM,
                rounding = 6,
                edges = "Z"
            );

            // Floor bridge across the deck ↔ box gap.
            right(bridge_x0)
                cuboid([bridge_len, porch_outer_y, floor_h], anchor = LEFT + BOTTOM);

            // Columns + locating spigots (deck recesses: diagonal pair tight).
            for (c = col_coords)
                translate([c.x, c.y, floor_h - eps]) {
                    cyl(
                        d = col_d,
                        h = col_top_z - floor_h + eps,
                        anchor = BOTTOM
                    );
                    up(col_top_z - floor_h + eps - 0.01)
                        cyl(
                            d = vm_locate_d,
                            h = vm_locate_h,
                            anchor = BOTTOM,
                            chamfer2 = 0.4
                        );
                }

            // Bottom 608 boss up to the bearing top.
            cyl(
                d = boss_d,
                h = bot_bearing_z1,
                anchor = BOTTOM
            );

            // Motor well tubes: ledge in the skirt, rim below the gear plane.
            for (my = motor_ys)
                translate([0, my, well_floor_z])
                    cyl(d = well_od, h = well_rim_z - well_floor_z, anchor = BOTTOM);

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
                right(bridge_x0)
                    cuboid([bridge_len, porch_outer_y, skirt_h], anchor = LEFT + BOTTOM);
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
                    // Smooth bore minus crush ribs; ribs stop below the lead-in.
                    up(motor_z0)
                        difference() {
                            cyl(d = well_bore_d, h = well_rim_z - motor_z0 + eps, anchor = BOTTOM);
                            for (i = [0:vm_well_rib_n - 1])
                                zrot(i * 360 / vm_well_rib_n + 30)
                                    right(mb_rib_inner_r())
                                        down(eps)
                                            cuboid(
                                                [rib_len, vm_well_rib_w, well_rim_z - motor_z0 - vm_well_leadin - 0.5 + eps],
                                                anchor = LEFT + BOTTOM,
                                                chamfer = 0.5,
                                                edges = [TOP + LEFT]
                                            );
                        }
                    up(well_rim_z - vm_well_leadin)
                        cyl(
                            d1 = well_bore_d,
                            d2 = well_bore_d + 2 * vm_well_leadin + 2 * eps,
                            h = vm_well_leadin + eps,
                            anchor = BOTTOM
                        );
                    // Terminals + wires through the ledge into the skirt.
                    up(well_floor_z - eps)
                        cyl(d = vm_motor_term_hole_d, h = motor_z0 - well_floor_z + 3 * eps, anchor = BOTTOM);
                }
            }

            // Motor wires come up from the skirt into the box.
            for (my = motor_ys)
                down(eps / 2)
                    right(porch_x0 + wall_t + 3)
                        back(my * 0.35)
                            cuboid(
                                [max(wire_slot_w + 4, 10), wire_slot_w + 6, floor_h + 2 * eps],
                                anchor = BOTTOM
                            );

            // 608 OD pocket. Outer race sits on the z=0 annulus outside bearing_lip_id.
            up(bot_bearing_z0)
                cyl(d = bearing_pocket_d, h = bearing_h + eps, anchor = BOTTOM);

            // Skirt hollow (leave a solid core under the 608 boss for the OD lip,
            // and keep the motor well tubes down to their ledges).
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
                        right(bridge_x0)
                            cuboid(
                                [bridge_len + skirt_wall + 1, porch_outer_y - 2 * skirt_wall, skirt_h + eps],
                                anchor = LEFT + BOTTOM
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
                        d = boss_d,
                        h = skirt_h + 2 * eps,
                        anchor = BOTTOM
                    );
                    for (my = motor_ys)
                        translate([0, my, skirt_h + well_floor_z])
                            cyl(d = well_od, h = -well_floor_z + eps, anchor = BOTTOM);
                }

                // Through the lip: lower race spacer seats up against the 608 inner race.
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
            // The terminal holes must reopen through the protected tubes.
            for (my = motor_ys)
                translate([0, my, well_floor_z - eps])
                    cyl(d = vm_motor_term_hole_d, h = motor_z0 - well_floor_z + 3 * eps, anchor = BOTTOM);

            // M3 heat-set insert pilots in column tops (through the spigots).
            for (c = col_coords)
                translate([c.x, c.y, col_top_z + vm_locate_h])
                    mb_insert_pilot(vm_insert_len_col, eps);

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

            // Low window in the box wall facing the deck (wires over the floor).
            up(floor_h)
                right(porch_x0 - eps)
                    cuboid(
                        [wall_t + 4, max(wire_slot_w + 16, 20), min(porch_inner_z, vm_motor_h) + eps],
                        anchor = LEFT + BOTTOM
                    );

            // Top notch in the same wall for the TX coil + IR emitter leads (under the lid).
            up(porch_h - deck_wire_notch_h)
                right(porch_x0 - eps)
                    back(vm_tx_wire_y / 2)
                        cuboid(
                            [wall_t + 2 * eps, deck_wire_notch_w, deck_wire_notch_h + eps],
                            anchor = LEFT + BOTTOM
                        );

            up(floor_h + porch_inner_z / 3)
                right(porch_x1)
                    cyl(
                        d = switch_cutout_d,
                        h = wall_t + 10,
                        orient = RIGHT
);

            up(floor_h + porch_inner_z / 2)
                right(porch_x0 + wall_t + porch_inner_x / 2)
                    back(porch_outer_y / 2)
                        cyl(
                            d = cable_hole_d,
                            h = wall_t + 10,
                            anchor = CENTER,
                            orient = BACK
                        );

            // Lid posts: M3 heat-set inserts from the top (screws go down through the lid).
            for (p = post_coords)
                translate([p.x, p.y, vm_porch_top_z()])
                    mb_insert_pilot(vm_insert_len_col, eps);

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
