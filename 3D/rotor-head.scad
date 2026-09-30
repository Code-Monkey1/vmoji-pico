// Rotor head — RX coil holder + 40x60 PCB mount, keyed on the rotor-shaft double-D.
// Underside: open RX coil rebate (coil drops in from below, copper facing the TX coil),
// hot-glue notches and a lead hole up to the PCB. Top: 4 M3 heat-set insert bosses under
// the PCB corner holes, center M3 screw into the shaft top, counterweight pockets (M3 nuts)
// and the IR index receiver (phototransistor pointing down, flange on its boss; a matching
// dummy hole on the opposite side keeps the head balanced). Print underside on the bed.
include <BOSL2/std.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module rotor_head() {
    eps = cut_overlap;
    disk_d = vm_head_disk_d();
    rx_top = vm_head_rx_top();
    disk_top = vm_head_disk_top();
    plate_z0 = 0;
    hub_top = vm_head_hub_top();
    pcb_z = vm_head_pcb_z();
    rebate_od = vm_ring_od + vm_ring_fit;
    rebate_id = vm_ring_id - vm_ring_fit;
    boss_d = max(9, vm_insert_boss_min_d());
    hole_pts = [for (sx = [1, -1], sy = [1, -1]) [sx * vm_pcb_hole_dx / 2, sy * vm_pcb_hole_dy / 2]];
    ir_xy = mb_ir_xy();
    ir_pts = [ir_xy, -ir_xy];
    ir_boss_d = vm_ir_flange_d + 3;
    cw_d = mb_hex_circum_d(vm_cw_nut_af + vm_cw_fit);
    m3_clear = vm_m3_clear_d + 2 * $slop;

    vm_assert_layout();
    assert(rebate_id > vm_head_hub_d + 2, "RX rebate cuts into the hub");
    assert(vm_cw_r - cw_d / 2 > vm_head_hub_d / 2 + 1 && vm_cw_r + cw_d / 2 < rebate_od / 2,
        "Counterweight pockets must sit over the RX rebate, clear of the hub");

    // Local z=0 = head underside (world vm_head_z()).
    diff() {
        union() {
            cyl(d = disk_d, h = disk_top, anchor = BOTTOM, chamfer1 = 0.4);
            up(plate_z0)
                cuboid(
                    [vm_display_pcb_x, vm_display_pcb_y, disk_top - plate_z0],
                    anchor = BOTTOM,
                    rounding = vm_pcb_corner_r,
                    edges = "Z"
                );
            cyl(d = vm_head_hub_d, h = hub_top, anchor = BOTTOM);
            for (p = hole_pts)
                translate([p.x, p.y, plate_z0])
                    cyl(d = boss_d, h = pcb_z - plate_z0, anchor = BOTTOM);
            for (p = ir_pts)
                translate([p.x, p.y, plate_z0])
                    cyl(d = ir_boss_d, h = vm_ir_rx_seat_z - plate_z0, anchor = BOTTOM);
        }

        tag("remove") {
            // RX coil rebate, open downward.
            down(eps)
                difference() {
                    cyl(d = rebate_od, h = rx_top + eps, anchor = BOTTOM);
                    down(eps)
                        cyl(d = rebate_id, h = rx_top + 3 * eps, anchor = BOTTOM);
                }
            // Hot-glue notches past the coil OD.
            for (i = [0:vm_glue_notch_n - 1])
                zrot(30 + i * 360 / vm_glue_notch_n)
                    translate([rebate_od / 2 - 1, 0, -eps])
                        cuboid(
                            [vm_glue_notch_d + 1, vm_glue_notch_w, rx_top + eps],
                            anchor = LEFT + BOTTOM
                        );
            // RX leads up to the PCB.
            zrot(vm_rx_wire_angle)
                right(vm_ring_od / 2 - 1.5)
                    down(eps)
                        cyl(d = vm_rx_wire_d, h = disk_top + 2 * eps, anchor = BOTTOM);

            // Double-D socket on the shaft key; shaft top face seats on the ceiling.
            down(eps)
                intersection() {
                    cyl(d = vm_rotor_shaft_d + vm_key_fit, h = vm_key_len + eps, anchor = BOTTOM, chamfer1 = -0.5);
                    cuboid([vm_key_flat + vm_key_fit, disk_d, vm_key_len + eps], anchor = BOTTOM);
                }
            // Center M3 screw (head sits on the hub top, under the PCB).
            up(vm_key_len - eps)
                cyl(d = m3_clear, h = hub_top - vm_key_len + 2 * eps, anchor = BOTTOM);

            // Counterweight pockets (glue M3 nuts in the light side after a spin test).
            for (i = [0:vm_cw_n - 1])
                zrot(i * 360 / vm_cw_n)
                    translate([vm_cw_r, 0, disk_top + eps])
                        cyl(d = cw_d, h = vm_cw_depth + eps, anchor = TOP, $fn = 6);

            // PCB insert pilots.
            for (p = hole_pts)
                translate([p.x, p.y, pcb_z])
                    mb_insert_pilot(vm_insert_len_head, eps);

            // IR receiver (+ balancing dummy): body hole, flange rests on the boss top.
            for (p = ir_pts)
                translate([p.x, p.y, -eps])
                    cyl(d = vm_ir_d + vm_ir_hole_extra, h = vm_ir_rx_seat_z + 2 * eps, anchor = BOTTOM);
        }
    }
}


rotor_head();
