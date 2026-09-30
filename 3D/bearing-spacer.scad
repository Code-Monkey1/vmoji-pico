// 608 inner-race spacer ring (print 2). One goes between the M8 SHCS head and the bottom
// 608, the other between the 608 and the M8 nut. Both the head (Ø13) and the nut (15 across
// corners) are wider than the inner race, so without these they would rub the shields.
// Print flat; 100% infill (it is clamped by the M8 stud).
include <BOSL2/std.scad>
include <vmoji-mech-params.scad>


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;


module bearing_spacer() {
    assert(vm_race_spacer_od < vm_bearing_inner_race_od - 0.3,
        "Race spacer OD would touch the 608 shields");
    difference() {
        cyl(d = vm_race_spacer_od, h = vm_race_spacer_h, anchor = BOTTOM, chamfer = 0.3);
        down(0.1)
            cyl(d = vm_race_spacer_id, h = vm_race_spacer_h + 0.2, anchor = BOTTOM);
    }
}


bearing_spacer();
