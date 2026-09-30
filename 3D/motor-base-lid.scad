// Electronics box ("porch") lid. M3 screws go down through the lid into heat-set inserts
// in the post tops. Box position comes from mb_porch_x0() so base and lid stay in sync.
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Lid] */
lid_lip = 0.8; // [0:0.1:2]
lid_fit_slop = 0.25; // [0.1:0.05:0.8]
lid_screw = "M3";
teardrop_holes = true; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_base_lid(
    lid_t = vm_lid_t,
    lid_lip = lid_lip,
    lid_fit_slop = lid_fit_slop,
    post_d = vm_post_d,
    lid_screw = lid_screw,
    teardrop_holes = teardrop_holes
) {
    eps = cut_overlap;
    layout = mb_layout();

    porch_x0 = mb_porch_x0(layout);
    porch_outer_x = mb_porch_outer_x();
    porch_outer_y = mb_porch_outer_y();

    post_coords = mb_post_coords(layout, post_d);

    lip_x = vm_porch_inner_x - 2 * lid_fit_slop;
    lip_y = vm_porch_inner_y - 2 * lid_fit_slop;

    // Local z=0 = lid underside, resting on the box wall tops (lip hangs inside, below 0).
    diff() {
        union() {
            right(porch_x0)
                cuboid(
                    [porch_outer_x, porch_outer_y, lid_t],
                    anchor = LEFT + BOTTOM,
                    chamfer = 1,
                    edges = [FRONT + RIGHT, BACK + RIGHT, FRONT + LEFT, BACK + LEFT]
                );

            if (lid_lip > 0)
                down(lid_lip)
                    right(porch_x0 + vm_wall_t + lid_fit_slop)
                        difference() {
                            cuboid(
                                [lip_x, lip_y, lid_lip + eps],
                                anchor = LEFT + BOTTOM
                            );
                            // Lip clears the posts.
                            for (p = post_coords)
                                translate([p.x - (porch_x0 + vm_wall_t + lid_fit_slop), p.y, -eps])
                                    cyl(d = post_d + 1, h = lid_lip + 3 * eps, anchor = BOTTOM);
                        }
        }

        tag("remove") {
            for (p = post_coords)
                translate([p.x, p.y, -lid_lip - eps / 2])
                    screw_hole(
                        lid_screw,
                        l = lid_t + lid_lip + eps,
                        teardrop = teardrop_holes,
                        anchor = BOTTOM,
                        orient = UP
                    );
        }
    }
}


motor_base_lid();
