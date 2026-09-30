// Single source of mechanical defaults for the dual-motor gear drive (v2).
// Include this BEFORE motor-base-common.scad in every print / preview file.
//
// BOM (coil-safe):
//   - 2x 608ZZ: bottom one in the base (on the M8 stud), top one hanging under the TX deck,
//     kept vm_top_bearing_coil_clear below the TX coil.
//   - 1x M8x25 DIN 912 / ISO 4762 socket head cap screw + 1x M8 hex nut + 2x printed
//     race spacers (bearing-spacer.scad). The screw + nut clamp the bottom 608 inner race and
//     form a stud; the rotor's hex socket slips over the nut and its bore centers on the tip.
//   - M3 heat-set inserts (Ø4.2): M3x6 in column tops and lid posts, M3x4 in the rotor head.
//   - Printed plastic rotor (rotor-shaft.scad + rotor-head.scad) through the TX–RX gap.
//
// Buy: Amazon "M8 hex socket screw assortment" (16/20/25/30). Use a 25 mm screw for the stud.
// Kit head is Ø13 x 8 mm, hex key 6 mm. These SHCS are typically fully threaded — the thread
// crest runs inside the 608 bore; that is fine because the inner race is clamped, not sliding.
//
// Fit convention: `$slop` (global print clearance) is added to clearance holes. Press / snug
// fits use explicit absolute extras below (tune them with fit-test.scad, not $slop).

/* ---- Motor (RF-300C-class) ---- */
vm_motor_d = 24;
vm_motor_h = 12;
vm_motor_shaft_d = 1.9; // Proven pinion press-fit bore on the Ø2.0 shaft; do not change casually.
vm_motor_shaft_len = 4.5; // Shaft length above the motor face (measured 4–5 mm).
// Front bearing boss on the motor face; the pinion underside is relieved around it.
vm_motor_boss_d = 7;
vm_motor_boss_h = 1;
// Terminal tabs + wires exit the can bottom through this hole in the well ledge.
vm_motor_term_hole_d = 18;

/* ---- Crush-rib press-fit motor wells (no clamp screw) ---- */
vm_well_clear = 0.3; // Radial clearance between can and smooth bore.
vm_well_rib_n = 6;
vm_well_rib_w = 1.2;
vm_well_rib_interf = 0.15; // Radial interference of each rib tip on the can.
vm_well_wall = 2.5;
vm_well_ledge_h = 1.5; // Floor ring under the can.
vm_well_rim_drop = 1.5; // Well rim sits this far below the can top.
vm_well_leadin = 0.8; // Chamfer at the rim for easy insertion.

/* ---- Gear train (2:1 single helical) ---- */
// Herringbone cannot be meshed by axial assembly; single helical can (the unpowered
// pinions rotate while the rotor drops in). Axial thrust is negligible at these torques.
vm_gear_mod = 1.25;
vm_pinion_teeth = 14;
vm_driven_teeth = 28;
vm_gear_helical = 25; // Magnitude only; hands are derived from vm_rotor_dir below.
vm_gear_backlash = 0.3;
vm_gear_thickness = 8; // Face width (pinion only grips the 4–5 mm motor shaft).
vm_gear_pressure_angle = 20;
vm_gear_slices = 8;
// Air gap between pinion underside and motor face (press the pinion down onto a shim).
vm_pinion_face_gap = 0.5;
// Rotor spin: -1 = clockwise viewed from the top, +1 = counter-clockwise.
// Hands are picked so the helix pushes the rotor UP (well below its weight) and the
// pinions DOWN toward the motors, which keeps the pinion press-fits seated.
vm_rotor_dir = -1; // [-1, 1]
function vm_driven_helical() = vm_rotor_dir * vm_gear_helical;
function vm_pinion_helical() = -vm_driven_helical();

/* ---- 608ZZ (bottom in base + top under TX deck) ---- */
vm_bearing_id = 8;
vm_bearing_od = 22;
vm_bearing_h = 7;
vm_bearing_fit = 0.15;
vm_bearing_inner_race_od = 12; // Nothing clamped/rotating may touch the shields outside this.
// OD lip at z=0: outer race sits on the annulus; spacer + head pass through the hole.
vm_bearing_lip_id = 16.8;
// Top 608: lip above the outer race only (inner race + shaft pass through).
vm_top_bearing_lip_id = 19.5;
// Steel top bearing top face → TX coil bottom face. Hard floor asserted at 4 mm.
vm_top_bearing_coil_clear = 10; // [4:0.5:20]

/* ---- M8 stud (SHCS + race spacers + nut) ---- */
// DIN 912 / ISO 4762 M8: head Ø13 x 8. ISO 4032 M8 nut: 13 AF x 6.5.
vm_shcs_d = 8;
vm_shcs_len = 25;
vm_shcs_head_d = 13;
vm_shcs_head_h = 8;
vm_bolt_head_pocket_d = 14.5; // head + print clearance
vm_nut_af = 13;
vm_nut_h = 6.5;
// Printed spacer rings touch only the inner race (head and nut are wider than it).
vm_race_spacer_id = 8.4;
vm_race_spacer_od = 11.5;
vm_race_spacer_h = 1.5;
// Continuous printed skirt so the head sits above the table (no rubber feet).
// head 8 + spacer 1.5 + ~1 clearance under head.
vm_skirt_h = 10.5;
vm_skirt_wall = 3;

/* ---- Rotor shaft (plastic, integrated driven gear) ---- */
vm_rotor_bottom_gap = 0.5; // Rotor underside above the upper race spacer.
vm_nut_socket_extra = 0.4; // Across-flats clearance: hex only drives, it does not center.
vm_tip_bore_extra = 0.15; // Snug bore on the M8 tip crest: this centers the rotor.
vm_tip_bore_headroom = 0.5; // Above the screw tip.
vm_rotor_collar_d = 11; // Shoulder above the gear; < inner race OD so it never touches shields.
vm_rotor_collar_gap = 0.5; // Collar top → top 608 inner race (rotor captive, not over-constrained).
vm_top_journal_d = 7.95; // Snug slide into the top 608 inner race (tune with fit-test.scad).
vm_rotor_shaft_d = 7.7; // Above the journal: lets the top 608 slide down freely.
// Double-D key at the shaft top for the rotor head (plus one center M3 self-tapped).
vm_key_flat = 6.2; // Across flats.
vm_key_len = 7; // Socket depth in the head.
vm_key_fit = 0.25; // Diametral clearance of the head socket on the key.
vm_center_pilot_d = 2.5; // M3 self-tap pilot in the shaft top.
vm_center_pilot_depth = 10;

/* ---- Induction rings ---- */
vm_ring_id = 21.5;
vm_ring_od = 41;
vm_ring_h = 1.2;
vm_ring_fit = 0.6; // Diametral clearance of the ring rebates.
// Face-to-face air gap between TX top and RX bottom. Hardware needs 8–20 mm; prefer 8.
vm_coil_gap = 8; // [8:0.5:20]

/* ---- TX deck ---- */
vm_deck_plate_t = 3; // Plastic under the TX ring.
vm_ring_rebate_extra = 0.3; // Rebate depth beyond ring_h.
vm_deck_shaft_clear_d = 10;
vm_deck_boss_wall = 2.5; // Around the top 608 pocket.
vm_tx_wire_y = -12; // TX lead groove runs to the +X edge at this Y.
vm_tx_wire_w = 3;

/* ---- Rotor head (RX coil + PCB) ---- */
vm_rx_recess = 0.2; // RX copper face sits this far inside the head underside.
vm_head_over_coil = 3; // Plastic above the RX coil.
// The PCB-footprint plate runs from the head underside to the disk top (prints flat).
vm_head_hub_d = 14;
vm_head_ceiling_t = 1.5; // Socket ceiling under the center screw head.
vm_center_screw_head_h = 3; // M3 SHCS head sits on the hub, under the PCB.
vm_rx_wire_d = 3.5;
vm_rx_wire_angle = 90;
vm_glue_notch_n = 3;
vm_glue_notch_w = 3;
vm_glue_notch_d = 1.5;
// Counterweight pockets (M3 nuts, glued) to balance the off-axis LED matrix.
vm_cw_n = 6;
vm_cw_r = 15;
vm_cw_nut_af = 5.5;
vm_cw_depth = 2.5;
vm_cw_fit = 0.3;

/* ---- Spinning display / PCB ---- */
// 40x60 mm proto board, 4x M3 corner holes. Hole rectangle is a placeholder: measure yours.
vm_display_pcb_x = 60;
vm_display_pcb_y = 40;
vm_display_pcb_t = 1.6;
vm_pcb_hole_dx = 52;
vm_pcb_hole_dy = 32;
vm_pcb_corner_r = 2;
vm_led_n = 8;
vm_led_pitch = 4; // 8×4 = 32 mm square matrix, standing in Z
vm_led_xy = 3.2;
vm_led_h = 1.8; // LED depth along the viewing axis (faces +Y)

/* ---- IR index sensor (firmware GP3, once per rev) ---- */
// Emitter (IR LED) in the deck facing up; receiver (phototransistor) in the head facing down.
// The emitter angle defines display angle zero.
vm_ir_d = 5; // [3, 5]
vm_ir_flange_d = 5.8; // 3 mm parts: ~3.8
vm_ir_flange_h = 1;
vm_ir_len = 8.6; // Flange bottom → dome tip. 3 mm parts: ~5.3
vm_ir_hole_extra = 0.3;
vm_ir_r = 27;
vm_ir_angle = 0;
vm_ir_tx_protrude = 1.5; // Emitter dome above the deck top.
vm_ir_rx_seat_z = 7.5; // Head-local Z of the receiver flange seat (dome just below the underside).
vm_ir_min_gap = 2;

/* ---- Base / deck layout ---- */
vm_floor_h = 5;
vm_wall_t = 3;
vm_deck_margin = 4;
vm_porch_inner_x = 50;
vm_porch_inner_y = 72;
vm_porch_inner_z = 32;
vm_porch_gap = 3; // Electronics box wall ↔ TX deck edge (lid stays removable).
vm_post_d = 9; // Lid posts (insert bosses).
vm_lid_t = 2.5;
vm_col_d = 12;

/* ---- Heat-set inserts (M3, Ø4.2) ---- */
// Brass inserts want metal M3 screws. Pilot = vm_insert_hole_d + 2*$slop (proven with yours).
vm_insert_od = 4.2;
vm_insert_hole_d = 4.0;
vm_insert_len_col = 6; // Column tops and lid posts.
vm_insert_len_head = 4; // Rotor head PCB bosses.
vm_insert_depth_extra = 1; // Pilot deeper than the insert.
vm_insert_min_wall = 2; // Boss OD >= pilot + 2 * wall.
// Free vertical cylinder above every insert at install time (soldering-iron access).
vm_iron_clear_d = 14;
vm_iron_clear_h = 20;
function vm_insert_pilot_d() = vm_insert_hole_d + 2 * $slop;
function vm_insert_depth(len) = len + vm_insert_depth_extra;
function vm_insert_boss_min_d() = vm_insert_pilot_d() + 2 * vm_insert_min_wall;

/* ---- Deck locating spigots (keeps the two 608s coaxial) ---- */
// Column tops carry a spigot; the deck has recesses: diagonal pair tight, other pair loose.
vm_locate_d = 9;
vm_locate_h = 1.5;
vm_locate_fit = 0.15; // Diametral, tight pair.
vm_locate_loose = 0.8; // Diametral, loose pair.
vm_locate_depth_extra = 0.3;
vm_m3_clear_d = 3.4; // + 2*$slop in the deck.

/* ---- Derived Z stack ---- */
// World z=0 = structural floor / bottom 608 bottom. Table contact is at -vm_skirt_h.
function vm_bot_bearing_z0() = 0;
function vm_bot_bearing_z1() = vm_bot_bearing_z0() + vm_bearing_h;
function vm_spacer_top_z() = vm_bot_bearing_z1() + vm_race_spacer_h;
function vm_nut_z0() = vm_spacer_top_z();
function vm_nut_z1() = vm_nut_z0() + vm_nut_h;
function vm_shcs_head_z1() = vm_bot_bearing_z0() - vm_race_spacer_h;
function vm_shcs_head_z0() = vm_shcs_head_z1() - vm_shcs_head_h;
function vm_shcs_tip_z() = vm_shcs_head_z1() + vm_shcs_len;
// Rotor underside = gear underside (gear prints flat on the bed).
function vm_rotor_z0() = vm_spacer_top_z() + vm_rotor_bottom_gap;
function vm_gear_z0() = vm_rotor_z0();
function vm_gear_z1() = vm_gear_z0() + vm_gear_thickness;
function vm_motor_top_z() = vm_gear_z0() - vm_pinion_face_gap;
function vm_motor_z0() = vm_motor_top_z() - vm_motor_h;
function vm_well_floor_z() = vm_motor_z0() - vm_well_ledge_h;
function vm_well_rim_z() = vm_motor_top_z() - vm_well_rim_drop;
function vm_tip_bore_top_z() = vm_shcs_tip_z() + vm_tip_bore_headroom;
function vm_rotor_collar_z1() = max(vm_gear_z1(), vm_tip_bore_top_z() + 1.5);
function vm_top_bearing_z0() = vm_rotor_collar_z1() + vm_rotor_collar_gap;
function vm_top_bearing_z1() = vm_top_bearing_z0() + vm_bearing_h;
function vm_journal_z1() = vm_top_bearing_z1() + 0.5;
function vm_tx_ring_z() = vm_top_bearing_z1() + vm_top_bearing_coil_clear;
function vm_tx_ring_top_z() = vm_tx_ring_z() + vm_ring_h;
function vm_deck_z() = vm_tx_ring_z() - vm_deck_plate_t; // Plate underside = column tops.
function vm_deck_top_z() = vm_tx_ring_z() + vm_ring_h + vm_ring_rebate_extra;
function vm_col_top_z() = vm_deck_z();
function vm_tx_deck_z() = vm_deck_z();
function vm_rx_ring_z() = vm_tx_ring_top_z() + vm_coil_gap;
function vm_head_z() = vm_rx_ring_z() - vm_rx_recess; // Head underside (world).
// Head-local heights.
function vm_head_rx_top() = vm_rx_recess + vm_ring_h;
function vm_head_disk_top() = vm_head_rx_top() + vm_head_over_coil;
function vm_head_disk_d() = vm_ring_od + 4;
function vm_head_hub_top() = vm_key_len + vm_head_ceiling_t;
function vm_head_pcb_z() = vm_head_hub_top() + vm_center_screw_head_h + 0.5;
function vm_rotor_top_z() = vm_head_z() + vm_key_len; // Shaft top face seats on the socket ceiling.
function vm_key_z0() = vm_head_z() - 0.5;
function vm_pcb_z() = vm_head_z() + vm_head_pcb_z();
function vm_display_z() = vm_pcb_z();
function vm_base_contact_z() = -vm_skirt_h;
function vm_porch_top_z() = vm_floor_h + vm_porch_inner_z;
function vm_lid_top_z() = vm_porch_top_z() + vm_lid_t;
// IR tips (world).
function vm_ir_tx_tip_z() = vm_deck_top_z() + vm_ir_tx_protrude;
function vm_ir_rx_tip_z() = vm_head_z() + vm_ir_rx_seat_z - (vm_ir_len - vm_ir_flange_h);

function vm_gear_ratio() = vm_driven_teeth / vm_pinion_teeth;
function vm_driven_spin(t) = vm_rotor_dir * t * 360;
function vm_pinion_spin(t) = -vm_rotor_dir * t * 360 * vm_gear_ratio();

// Kept for callers of the v1 name; v2 checks everything in vm_assert_layout().
module vm_assert_coil_gap_metal_free() {
    assert(
        vm_shcs_tip_z() < vm_deck_z() - 0.5,
        "M8 stud reaches into TX deck / coil zone — use a shorter screw"
    );
    assert(
        vm_top_bearing_coil_clear >= 4,
        "Top 608 closer than 4 mm to the TX coil — no room for plastic, heavy coupling"
    );
    assert(
        vm_coil_gap >= 8 && vm_coil_gap <= 20,
        "TX–RX coil face gap must stay in 8–20 mm"
    );
}
