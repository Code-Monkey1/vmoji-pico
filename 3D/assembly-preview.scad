// Coil-safe dual-motor assembly preview (F5).
// Metal: bottom 608 + M8 stud (well below the coils) and the top 608 hanging under the TX
// deck, vm_top_bearing_coil_clear below the TX coil. Plastic rotor through the TX–RX gap.
// Base skirt contact is at -vm_skirt_h; SHCS head stays above the table.
//
// Animate: View → Animate. Start with FPS=30, Steps=180.
// $t runs 0→1; the rotor turns once per cycle (vm_rotor_dir), pinions twice (2:1) the other way.
// Collisions: run ./check-collisions.sh (uses the same placements, vmoji-assembly.scad).
include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>
include <vmoji-assembly.scad>


/* [Preview] */
show_base = true; // [true, false]
show_tx_deck = true; // [true, false]
show_lid = true; // [true, false]
show_motors = true; // [true, false]
show_gears = true; // [true, false]
show_shaft = true; // [true, false]
show_bearing = true; // [true, false]
show_stud = true; // [true, false]
show_coils = true; // [true, false]
show_head = true; // [true, false]
show_ir = true; // [true, false]
show_display = true; // [true, false]
explode = 0; // [0:0.5:20]
// Cut away the -Y half to see the stack (section at Y=0).
section = false; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.4;
$slop = 0.2;

vm_assert_layout();

driven_a = vm_driven_spin($t);


module _assembly() {
    if (show_base)
        color("royalblue", 0.5)
            asm_base();

    if (show_tx_deck)
        color("dodgerblue", 0.65)
            up(explode)
                asm_deck();

    if (show_lid)
        color("steelblue", 0.7)
            up(explode)
                asm_lid();

    if (show_motors)
        for (my = asm_motor_ys()) {
            color("dimgray")
                down(explode * 0.2)
                    asm_motor(my);
            if (show_gears)
                color("seagreen")
                    up(explode * 0.4)
                        asm_pinion(my, driven_a);
        }

    if (show_shaft)
        color("ivory", 0.9)
            up(explode * 0.5)
                asm_rotor_shaft(driven_a);

    if (show_bearing) {
        color("silver") down(explode * 0.15) asm_bearing_bottom();
        color("silver") up(explode * 0.8) asm_bearing_top();
    }

    if (show_stud)
        color("lightsteelblue")
            down(explode * 0.3)
                asm_stud(driven_a);

    if (show_coils) {
        color("goldenrod") up(explode * 1.1) asm_tx_coil();
        color("goldenrod") up(explode * 1.6) asm_rx_coil(driven_a);
    }

    if (show_head)
        color("tomato")
            up(explode * 1.8)
                asm_head(driven_a);

    if (show_ir) {
        color("purple") up(explode * 1.1) asm_ir_emitter();
        color("black") up(explode * 1.8) asm_ir_receiver(driven_a);
    }

    if (show_display)
        up(explode * 2.2)
            asm_display(driven_a, colored = true);
}


if (section)
    difference() {
        _assembly();
        fwd(200) cube(400, center = true);
    }
else
    _assembly();
