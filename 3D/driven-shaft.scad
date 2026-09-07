// Printed plastic driven shaft — dielectric through the TX–RX coil gap.
// Short Ø8 metal journal press-fits into the bottom boss and rides in the 608 only.
// Print axis-vertical in PETG/ABS. Do NOT use a full-length metal rod.
include <BOSL2/std.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module driven_shaft(
    shaft_d = vm_shaft_d,
    body_h = undef,
    flange_d = vm_shaft_flange_d,
    flange_h = vm_shaft_flange_h,
    journal_boss_d = vm_shaft_journal_boss_d,
    journal_boss_h = vm_shaft_journal_boss_h,
    journal_d = vm_journal_d,
    journal_press_depth = vm_journal_press_depth,
    journal_fit_extra = vm_journal_fit_extra
) {
    eps = cut_overlap;
    h = is_undef(body_h) ? vm_shaft_body_h() : body_h;
    journal_bore_d = journal_d + journal_fit_extra + 2 * $slop;
    seat_z = journal_boss_h + flange_h;

    vm_assert_coil_gap_metal_free();
    assert(flange_d > journal_boss_d, "flange must exceed journal boss OD");
    assert(journal_boss_d > journal_bore_d + 2.5, "journal boss wall too thin");
    assert(
        journal_press_depth <= journal_boss_h + flange_h - 0.5,
        "journal press must stay in boss/flange — keep Ø8 coil span solid plastic"
    );
    assert(h > seat_z + 20, "shaft body too short for coil / collar stack");

    // Local z=0 = bottom on 608 inner race.
    // Gear seats on flange top at local z=seat_z (= world gear_z0).
    diff() {
        union() {
            cyl(d = journal_boss_d, h = journal_boss_h, anchor = BOTTOM);

            up(journal_boss_h - eps)
                cyl(d = flange_d, h = flange_h + eps, anchor = BOTTOM);

            up(seat_z - eps)
                cyl(d = shaft_d, h = h - seat_z + eps, anchor = BOTTOM);
        }

        tag("remove") {
            down(eps / 2)
                cyl(
                    d = journal_bore_d,
                    h = journal_press_depth + eps,
                    anchor = BOTTOM
                );
        }
    }
}


driven_shaft();
