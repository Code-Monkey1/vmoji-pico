// TX deck: holds the TX coil on top and the top 608 in a boss hanging underneath.
// The steel bearing stays vm_top_bearing_coil_clear below the TX coil (asserted).
// Bolts into M3 heat-set inserts in motor-base column tops; locating recesses on the
// underside take the column spigots (diagonal pair tight) so both 608s stay coaxial.
// Print upside down (coil face on the bed): no overhangs, bearing pocket opens upward.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Hardware] */
mount_screw = "M3";


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_tx_deck(mount_screw = mount_screw) {
    eps = cut_overlap;
    bearing_pocket_d = mb_bearing_pocket_d();
    layout = mb_layout();
    deck_half_x = mb_layout_get(layout, "deck_half_x");
    deck_half_y = mb_layout_get(layout, "deck_half_y");
    col_coords = mb_layout_get(layout, "col_coords");
    col_tight = mb_layout_get(layout, "col_tight");
    deck_x = 2 * deck_half_x;
    deck_y = 2 * deck_half_y;

    // Part local z=0 = underside seated on column tops.
    dz = vm_deck_z();
    top_z = vm_deck_top_z() - dz;
    ring_z = vm_tx_ring_z() - dz;
    tb_z0 = vm_top_bearing_z0() - dz;
    tb_z1 = vm_top_bearing_z1() - dz;
    boss_d = bearing_pocket_d + 2 * vm_deck_boss_wall;
    rebate_od = vm_ring_od + vm_ring_fit;
    island_d = vm_ring_id - vm_ring_fit;
    ir_xy = mb_ir_xy();
    ir_hole_d = vm_ir_d + vm_ir_hole_extra;
    ir_flange_hole_d = vm_ir_flange_d + 0.4;
    // Emitter inserted from below; flange stops against the step.
    ir_step_z = vm_ir_tx_tip_z() - dz - (vm_ir_len - vm_ir_flange_h);
    ir_boss_z0 = min(0, ir_step_z - vm_ir_flange_h - 0.4);
    ir_boss_d = ir_flange_hole_d + 3;
    m3_clear = vm_m3_clear_d + 2 * $slop;

    vm_assert_layout();
    assert(vm_ring_od > vm_ring_id, "ring_od must exceed ring_id");

    diff() {
        union() {
            // TX deck plate (plastic only under the coil).
            cuboid(
                [deck_x, deck_y, top_z],
                anchor = BOTTOM,
                rounding = 6,
                edges = "Z"
            );

            // Hanging boss around the top 608.
            up(tb_z0)
                cyl(d = boss_d, h = -tb_z0 + eps, anchor = BOTTOM, chamfer1 = 0.6);

            // IR emitter boss (only if the LED needs more depth than the plate).
            if (ir_boss_z0 < 0)
                translate([ir_xy.x, ir_xy.y, ir_boss_z0])
                    cyl(d = ir_boss_d, h = -ir_boss_z0 + eps, anchor = BOTTOM);
        }

        tag("remove") {
            // Top 608 pocket (pressed in from below) + bore above the outer-race lip.
            down(eps)
                up(tb_z0)
                    cyl(d = bearing_pocket_d, h = vm_bearing_h + eps, anchor = BOTTOM, chamfer1 = -0.5);
            up(tb_z1 - eps / 2)
                cyl(d = vm_top_bearing_lip_id, h = -tb_z1 + eps, anchor = BOTTOM);
            down(eps / 2)
                cyl(d = vm_deck_shaft_clear_d, h = top_z + eps, anchor = BOTTOM);

            // TX ring rebate (coil sits on the floor, glue as needed).
            up(ring_z)
                difference() {
                    cyl(d = rebate_od, h = top_z - ring_z + eps, anchor = BOTTOM);
                    down(eps)
                        cyl(d = island_d, h = top_z - ring_z + 3 * eps, anchor = BOTTOM);
                }

            // TX lead groove to the +X edge (toward the box notch).
            translate([0, vm_tx_wire_y, ring_z])
                cuboid(
                    [deck_half_x + eps, vm_tx_wire_w, top_z - ring_z + eps],
                    anchor = LEFT + BOTTOM
                );

            // Clearance bolts into column heat-set inserts + locating recesses.
            for (i = [0:len(col_coords) - 1]) {
                c = col_coords[i];
                translate([c.x, c.y, -eps / 2])
                    cyl(d = m3_clear, h = top_z + eps, anchor = BOTTOM);
                translate([c.x, c.y, -eps])
                    cyl(
                        d = vm_locate_d + (col_tight[i] ? vm_locate_fit : vm_locate_loose),
                        h = vm_locate_h + vm_locate_depth_extra + eps,
                        anchor = BOTTOM
                    );
            }

            // IR emitter: body hole through the top, flange counterbore from below.
            translate([ir_xy.x, ir_xy.y, ir_step_z - eps / 2])
                cyl(d = ir_hole_d, h = top_z - ir_step_z + eps, anchor = BOTTOM);
            translate([ir_xy.x, ir_xy.y, ir_boss_z0 - eps])
                cyl(d = ir_flange_hole_d, h = ir_step_z - ir_boss_z0 + eps, anchor = BOTTOM);
        }
    }
}


motor_tx_deck();
