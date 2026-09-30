// Rotor shaft — plastic, with the 28T driven helical gear printed as one piece.
// Bottom: hex socket slips over the M8 nut on the bottom 608 (drive only), and a snug bore
// rides on the M8 screw tip above the nut (this centers the rotor). No threads in plastic,
// so either rotation direction is safe; the rotor rests on the nut top by its own weight.
// Above the gear: collar (under the top 608 inner race, 0.5 mm gap), Ø8 journal for the top
// 608, a slimmer shaft through the TX deck, then a double-D key for rotor-head.scad with a
// center M3 pilot (self-tapped). Print gear face down on the bed, axis vertical.
include <BOSL2/std.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module _double_d(d, flat, h, anchor = BOTTOM) {
    intersection() {
        cyl(d = d, h = h, anchor = anchor);
        cuboid([flat, d + 1, h], anchor = anchor);
    }
}


module rotor_shaft() {
    eps = cut_overlap;
    z0 = vm_rotor_z0();
    gear_t = vm_gear_thickness;
    socket_h = vm_nut_z1() - z0;
    socket_d = mb_hex_circum_d(vm_nut_af + vm_nut_socket_extra);
    tip_bore_d = vm_shcs_d + vm_tip_bore_extra;
    tip_bore_top = vm_tip_bore_top_z() - z0;
    collar_top = vm_rotor_collar_z1() - z0;
    journal_top = vm_journal_z1() - z0;
    key_z0 = vm_key_z0() - z0;
    top = vm_rotor_top_z() - z0;

    vm_assert_layout();
    assert(socket_h > 3, "Nut socket too shallow");
    assert(socket_h < gear_t - 1, "Nut socket breaks through the gear top");

    // Local z=0 = rotor underside = gear underside (world vm_rotor_z0()).
    diff() {
        union() {
            up(gear_t / 2)
                mb_helical_gear(
                    teeth = vm_driven_teeth,
                    helical = vm_driven_helical(),
                    thickness = gear_t
                );
            up(gear_t - eps)
                cyl(d = vm_rotor_collar_d, h = collar_top - gear_t + eps, anchor = BOTTOM);
            up(collar_top - eps)
                cyl(d = vm_top_journal_d, h = journal_top - collar_top + eps, anchor = BOTTOM, chamfer2 = 0.15);
            up(journal_top - eps)
                cyl(d = vm_rotor_shaft_d, h = key_z0 - journal_top + eps, anchor = BOTTOM);
            up(key_z0 - eps)
                intersection() {
                    _double_d(vm_rotor_shaft_d, vm_key_flat, top - key_z0 + eps);
                    cyl(d = vm_rotor_shaft_d, h = top - key_z0 + eps, anchor = BOTTOM, chamfer2 = 0.5);
                }
        }

        tag("remove") {
            // Hex socket over the M8 nut (drive only).
            down(eps)
                cyl(d = socket_d, h = socket_h + eps, anchor = BOTTOM, $fn = 6, chamfer1 = -0.6);
            // Snug centering bore on the M8 tip, cone top (no bridge when printing).
            up(socket_h - eps)
                cyl(d = tip_bore_d, h = tip_bore_top - socket_h + eps, anchor = BOTTOM);
            up(tip_bore_top - eps / 2)
                cyl(d1 = tip_bore_d, d2 = 0.4, h = tip_bore_d / 2, anchor = BOTTOM);
            // Center M3 self-tap pilot for the head screw.
            up(top + eps)
                cyl(d = vm_center_pilot_d, h = vm_center_pilot_depth + eps, anchor = TOP);
        }
    }
}


rotor_shaft();
