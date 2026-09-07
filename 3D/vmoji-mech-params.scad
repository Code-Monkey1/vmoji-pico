// Single source of mechanical defaults for the dual-motor gear drive.
// Include this BEFORE motor-base-common.scad in every print / preview file.
//
// BOM (coil-safe):
//   - 1x 608ZZ bearing (bottom only — NOT under the TX coil)
//   - 1x short Ø8 mm journal (~18–22 mm; aluminum preferred; steel OK only below TX deck)
//   - 1x M8 nylock + washer (underside axial retention)
//   - 4x M3 heat-set inserts (column tops for TX deck bolts)
//   - Printed plastic driven shaft through the TX–RX gap (no full-length metal rod)

/* ---- Motor (RF-300C-class) ---- */
vm_motor_d = 24;
vm_motor_h = 12;
vm_motor_shaft_d = 1.0; // Proven pinion press-fit; do not change casually.
vm_collet_wall = 4.5;
vm_collet_flange_od = 48;
vm_collet_flange_h = 3;
vm_flange_bolt_r = 20;
vm_flange_bolt_count = 3;
vm_key_w = 8;
vm_key_d = 2.5;

/* ---- Gear train (2:1 herringbone) ---- */
vm_gear_mod = 1.25;
vm_pinion_teeth = 14;
vm_driven_teeth = 28;
vm_gear_helical = 25;
vm_gear_backlash = 0.3;
vm_gear_thickness = 10;
vm_gear_pressure_angle = 20;
vm_gear_slices = 6;
// Short pinion hub: less cantilever on the 1 mm motor shaft.
vm_pinion_hub_h = 2;
// Driven gear clamp boss above teeth (slit clamp only — no set-screw into plastic).
vm_driven_hub_h = 6;

/* ---- Driven shaft (plastic through coils) ---- */
vm_shaft_d = 8;
vm_shaft_bore_extra = 0.15;
// Short metal journal press-fit into plastic shaft; protrudes down through 608 only.
vm_journal_d = 8;
vm_journal_len = 18;
vm_journal_press_depth = 6; // Must fit inside journal_boss_h (+ flange).
vm_journal_fit_extra = 0.05;
// Flange under driven gear (sets gear Z).
vm_shaft_flange_d = 16;
vm_shaft_flange_h = 2;
// Boss below the gear seat: holds the Ø8 journal press bore (Ø8 body above stays solid).
vm_shaft_journal_boss_d = 13;
vm_shaft_journal_boss_h = 5;
// Collar / RX stack above TX.
vm_collar_h = 12;
vm_hat_h = 3.5;
vm_coil_gap = 3; // Free air gap between TX top and RX bottom.

/* ---- Induction rings ---- */
vm_ring_id = 21.5;
vm_ring_od = 41;
vm_ring_h = 1.2;
vm_ring_standoff = 1.5;

/* ---- 608ZZ (bottom only) ---- */
vm_bearing_id = 8;
vm_bearing_od = 22;
vm_bearing_h = 7;
vm_bearing_fit = 0.15;
vm_nylock_countersink_d = 15;
vm_nylock_countersink_h = 6.5; // M8 nylock ~8 mm tall; recess + washer room.

/* ---- Top plastic bushing (in TX deck) ---- */
vm_bushing_len = 8;
vm_bushing_flange_d = 16;
vm_bushing_flange_h = 2;
vm_bushing_fit_extra = 0.25; // Diametral clearance on Ø8 plastic shaft.

/* ---- Base / deck layout ---- */
vm_floor_h = 5;
vm_wall_t = 3;
vm_deck_margin = 4;
vm_porch_inner_x = 50;
vm_porch_inner_y = 72;
vm_porch_inner_z = 32;
vm_pocket_slop = 0.3;
vm_deck_plate_t = 3;

/* ---- Heat-set inserts (M3) in column tops ---- */
vm_insert_od = 4.2; // Tapered brass M3 short insert major OD (tune to your inserts).
vm_insert_depth = 5.5;
vm_insert_hole_d = 4.0; // Pilot for heat-set; adjust per insert datasheet.

/* ---- Derived Z stack (world z=0 at base underside) ---- */
// Meshing teeth start at gear_z0 (motor face + pinion hub).
function vm_gear_z0() = vm_motor_h + vm_pinion_hub_h;
function vm_gear_z1() = vm_gear_z0() + vm_gear_thickness;
// Gear seats on flange top; journal boss sits below the flange on the 608.
function vm_gear_seat_z() = vm_gear_z0();
function vm_shaft_z0() =
    vm_gear_seat_z() - vm_shaft_flange_h - vm_shaft_journal_boss_h;
function vm_bot_bearing_z1() = vm_shaft_z0();
function vm_bot_bearing_z0() = vm_bot_bearing_z1() - vm_bearing_h;
function vm_journal_metal_top_z() =
    vm_shaft_z0() + vm_journal_press_depth;
function vm_col_top_z() = vm_gear_z1() + vm_driven_hub_h;
function vm_tx_deck_z() = vm_col_top_z();
function vm_bushing_z0() = vm_tx_deck_z();
function vm_tx_ring_z() =
    vm_tx_deck_z() + vm_bushing_flange_h + vm_deck_plate_t + vm_ring_standoff;
function vm_tx_ring_top_z() = vm_tx_ring_z() + vm_ring_h;
// Collar print bottom (RX seat faces TX); RX copper sits at ring_standoff into the seat.
function vm_collar_z() = vm_tx_ring_top_z() + vm_coil_gap - vm_ring_standoff;
function vm_rx_ring_z() = vm_collar_z() + vm_ring_standoff;
function vm_collar_body_z() =
    vm_collar_z() + vm_ring_standoff + vm_ring_h + 1.2;
function vm_shaft_top_z() = vm_collar_body_z() + vm_collar_h + vm_hat_h + 2;
function vm_shaft_body_h() = vm_shaft_top_z() - vm_shaft_z0();

module vm_assert_coil_gap_metal_free() {
    assert(
        vm_journal_metal_top_z() < vm_tx_deck_z() - 0.5,
        "Metal journal reaches into TX deck / coil zone — shorten press depth or journal"
    );
    assert(
        vm_bot_bearing_z0() >= 0,
        "Bottom bearing extends below base — shorten journal boss / flange"
    );
    assert(
        vm_journal_len >= vm_journal_press_depth + vm_bearing_h + 2,
        "Journal too short to pass through 608 and reach nylock"
    );
}
