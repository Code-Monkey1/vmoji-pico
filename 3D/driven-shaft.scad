// Printed plastic driven shaft — dielectric through the TX–RX coil gap.
// An M8x16 DIN 912 SHCS is the journal: shank press-fits into the bottom boss, rides in
// the 608, and the head + washer retain the stack from below (inside the base skirt).
// A short clearance bore above the press accepts the remaining tip. Print axis-vertical.
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
    journal_fit_extra = vm_journal_fit_extra,
    journal_clear_extra = vm_journal_clear_extra
) {
    eps = cut_overlap;
    h = is_undef(body_h) ? vm_shaft_body_h() : body_h;
    journal_bore_d = journal_d + journal_fit_extra + 2 * $slop;
    clear_bore_d = journal_d + journal_clear_extra + 2 * $slop;
    clear_depth = vm_journal_clear_depth();
    seat_z = journal_boss_h + flange_h;
    metal_into = vm_journal_into_plastic();

    vm_assert_coil_gap_metal_free();
    assert(flange_d > journal_boss_d, "flange must exceed journal boss OD");
    assert(journal_boss_d > journal_bore_d + 2.5, "journal boss wall too thin");
    assert(
        journal_press_depth <= journal_boss_h + flange_h - 0.5,
        "journal press must stay in boss/flange — keep Ø8 coil span solid plastic"
    );
    assert(
        metal_into <= h - 5,
        "journal tip would exit the top of the shaft — shorten screw"
    );
    assert(
        clear_depth < 0.01 || clear_bore_d >= journal_bore_d,
        "clearance bore must be at least as loose as the press bore"
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
            // Press fit in boss/flange.
            down(eps / 2)
                cyl(
                    d = journal_bore_d,
                    h = journal_press_depth + eps,
                    anchor = BOTTOM
                );

            // Loose tip clearance above the press (M8x16 leftover past bearing+press).
            if (clear_depth > 0.05)
                up(journal_press_depth - eps)
                    cyl(
                        d = clear_bore_d,
                        h = clear_depth + 2 * eps,
                        anchor = BOTTOM
                    );
        }
    }
}


driven_shaft();
