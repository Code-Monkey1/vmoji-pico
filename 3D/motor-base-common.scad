// Shared helpers for dual-motor offset gear drive parts.
// Include BOSL2 (std, screws, gears as needed) and vmoji-mech-params.scad before this file.

/* ---- Fasteners / clearance ---- */

function mb_clearance_hole_d(screw_spec) =
    struct_val(screw_info(screw_spec), "diameter") + 0.4 + 2 * $slop;

function mb_nut_circum_d(screw_spec) =
    struct_val(nut_info(screw_spec), "width") / cos(30);

function mb_nut_pocket_d(screw_spec, extra_d = 0) =
    mb_nut_circum_d(screw_spec) + extra_d + 2 * $slop;

function mb_hex_circum_d(af) = af / cos(30);

// Heat-set insert pilot, top face at local z=0, going down.
module mb_insert_pilot(len, eps = 0.2) {
    up(eps)
        cyl(
            d = vm_insert_pilot_d(),
            h = vm_insert_depth(len) + eps,
            anchor = TOP,
            chamfer2 = -0.4
        );
}

// Soldering-iron access volume above an insert whose top face is at local z=0.
module mb_iron_clearance() {
    up(0.05)
        cyl(d = vm_iron_clear_d, h = vm_iron_clear_h, anchor = BOTTOM);
}

/* ---- Bearing / shaft (defaults from params) ---- */

function mb_bearing_id() = vm_bearing_id;
function mb_bearing_od() = vm_bearing_od;
function mb_bearing_h() = vm_bearing_h;

function mb_bearing_pocket_d(fit = undef) =
    let (f = is_undef(fit) ? vm_bearing_fit : fit)
        mb_bearing_od() + f + 2 * $slop;

function mb_bearing_boss_d() = mb_bearing_pocket_d() + 2 * vm_wall_t;

function mb_shaft_clear_d(shaft_d = vm_shcs_d, extra = 0.6) =
    shaft_d + extra + 2 * $slop;

/* ---- Motor wells ---- */

function mb_well_bore_d() = vm_motor_d + 2 * vm_well_clear;
function mb_well_od() = mb_well_bore_d() + 2 * vm_well_wall;
function mb_rib_inner_r() = vm_motor_d / 2 - vm_well_rib_interf;

/* ---- Gear train (defaults from params) ---- */

function mb_gear_mod() = vm_gear_mod;
function mb_pinion_teeth() = vm_pinion_teeth;
function mb_driven_teeth() = vm_driven_teeth;
function mb_gear_helical() = vm_gear_helical;
function mb_gear_backlash() = vm_gear_backlash;
function mb_gear_thickness() = vm_gear_thickness;
function mb_gear_pressure_angle() = vm_gear_pressure_angle;

function mb_gear_center_dist(
    mod = mb_gear_mod(),
    pinion_teeth = mb_pinion_teeth(),
    driven_teeth = mb_driven_teeth(),
    helical = mb_gear_helical(),
    backlash = mb_gear_backlash(),
    pressure_angle = mb_gear_pressure_angle()
) =
    gear_dist(
        mod = mod,
        teeth1 = pinion_teeth,
        teeth2 = driven_teeth,
        helical = helical,
        backlash = 0,
        pressure_angle = pressure_angle
    ) + backlash;

function mb_gear_outer_d(
    teeth,
    mod = mb_gear_mod(),
    helical = mb_gear_helical(),
    pressure_angle = mb_gear_pressure_angle()
) =
    2 * outer_radius(
        mod = mod,
        teeth = teeth,
        helical = helical,
        pressure_angle = pressure_angle
    );

function mb_gear_root_d(
    teeth,
    mod = mb_gear_mod(),
    helical = mb_gear_helical(),
    pressure_angle = mb_gear_pressure_angle(),
    backlash = mb_gear_backlash()
) =
    2 * root_radius(
        mod = mod,
        teeth = teeth,
        helical = helical,
        pressure_angle = pressure_angle,
        backlash = backlash
    );

function mb_motor_axis_y(
    mod = mb_gear_mod(),
    pinion_teeth = mb_pinion_teeth(),
    driven_teeth = mb_driven_teeth(),
    helical = mb_gear_helical(),
    backlash = mb_gear_backlash()
) =
    mb_gear_center_dist(mod, pinion_teeth, driven_teeth, helical, backlash);

// Single-helical gear, centered on its thickness. `helical` carries the hand (sign).
module mb_helical_gear(
    teeth,
    helical,
    thickness = mb_gear_thickness(),
    mod = mb_gear_mod(),
    backlash = mb_gear_backlash(),
    pressure_angle = mb_gear_pressure_angle(),
    shaft_diam = 0,
    slices = vm_gear_slices
) {
    spur_gear(
        mod = mod,
        teeth = teeth,
        thickness = thickness,
        helical = helical,
        herringbone = false,
        backlash = backlash,
        pressure_angle = pressure_angle,
        shaft_diam = shaft_diam,
        slices = slices,
        anchor = CENTER
    );
}

/* ---- Layout ---- */

function mb_col_d() = vm_col_d;

function mb_layout(
    motor_y = mb_gear_center_dist(),
    well_od = mb_well_od(),
    driven_od = mb_gear_outer_d(vm_driven_teeth),
    pinion_od = mb_gear_outer_d(vm_pinion_teeth),
    ring_od = vm_ring_od,
    bearing_pocket_d = mb_bearing_pocket_d(),
    deck_margin = vm_deck_margin,
    wall_t = vm_wall_t
) =
    let(
        cavity_half_x = driven_od / 2 + 3,
        cavity_half_y = motor_y + pinion_od / 2 + 2,
        col_d = mb_col_d(),
        deck_half_y = max(
            motor_y + well_od / 2 + deck_margin,
            cavity_half_y + col_d / 2 + 3
        ),
        deck_half_x = max(
            max(ring_od / 2, driven_od / 2, bearing_pocket_d / 2) + deck_margin + wall_t,
            cavity_half_x + col_d / 2 + 3
        ),
        col_inset = col_d / 2 + 2
    )
    [
        ["deck_half_x", deck_half_x],
        ["deck_half_y", deck_half_y],
        ["cavity_half_x", cavity_half_x],
        ["cavity_half_y", cavity_half_y],
        ["col_d", col_d],
        ["col_inset", col_inset],
        ["col_coords", [
            [ deck_half_x - col_inset,  deck_half_y - col_inset],
            [ deck_half_x - col_inset, -(deck_half_y - col_inset)],
            [-deck_half_x + col_inset,  deck_half_y - col_inset],
            [-deck_half_x + col_inset, -(deck_half_y - col_inset)]
        ]],
        // Diagonal pair (+,+) / (-,-) gets the tight locating fit.
        ["col_tight", [true, false, false, true]]
    ];

function mb_layout_get(layout, key) =
    struct_val(layout, key);

// Electronics box ("porch") sits vm_porch_gap beyond the deck edge in +X.
function mb_porch_x0(layout = mb_layout()) =
    mb_layout_get(layout, "deck_half_x") + vm_porch_gap;
function mb_porch_outer_x() = vm_porch_inner_x + 2 * vm_wall_t;
function mb_porch_outer_y() = vm_porch_inner_y + 2 * vm_wall_t;

function mb_post_coords(layout = mb_layout(), post_d = vm_post_d) =
    let(
        x0 = mb_porch_x0(layout),
        x1 = x0 + mb_porch_outer_x(),
        inset = vm_wall_t + post_d / 2 + 1,
        py = vm_porch_inner_y / 2 - post_d / 2 - 1
    )
    [[x0 + inset, py], [x0 + inset, -py], [x1 - inset, py], [x1 - inset, -py]];

function mb_ir_xy() = [vm_ir_r * cos(vm_ir_angle), vm_ir_r * sin(vm_ir_angle)];

// Sweep radius of the head + PCB (corner of the rounded PCB rectangle).
function mb_head_sweep_r() =
    norm([vm_display_pcb_x / 2, vm_display_pcb_y / 2]) - vm_pcb_corner_r * (sqrt(2) - 1);

/* ---- Swept envelopes (collision checks) ---- */

// Conservative solid of revolution covering every rotor-shaft angle (world Z).
module mb_rotor_shaft_envelope() {
    up(vm_rotor_z0()) cyl(d = mb_gear_outer_d(vm_driven_teeth), h = vm_gear_thickness, anchor = BOTTOM);
    up(vm_gear_z1()) cyl(d = vm_rotor_collar_d, h = vm_rotor_collar_z1() - vm_gear_z1(), anchor = BOTTOM);
    up(vm_rotor_collar_z1()) cyl(d = vm_top_journal_d, h = vm_journal_z1() - vm_rotor_collar_z1(), anchor = BOTTOM);
    up(vm_journal_z1()) cyl(d = vm_rotor_shaft_d, h = vm_rotor_top_z() - vm_journal_z1(), anchor = BOTTOM);
}

// Conservative envelope of the head (+ PCB footprint) over a full turn (world Z).
module mb_rotor_head_envelope() {
    up(vm_head_z()) {
        cyl(r = mb_head_sweep_r(), h = vm_head_pcb_z(), anchor = BOTTOM);
    }
}

module mb_pinion_envelope() {
    up(vm_gear_z0())
        cyl(d = mb_gear_outer_d(vm_pinion_teeth), h = vm_gear_thickness, anchor = BOTTOM);
}

/* ---- Layout asserts (analytic collision + fit checks) ---- */

module vm_assert_layout() {
    layout = mb_layout();
    motor_y = mb_gear_center_dist();
    deck_half_x = mb_layout_get(layout, "deck_half_x");
    col_coords = mb_layout_get(layout, "col_coords");
    col_r_min = min([for (c = col_coords) norm(c)]);
    col_to_motor = min([for (c = col_coords, s = [1, -1]) norm(c - [0, s * motor_y])]);
    driven_od = mb_gear_outer_d(vm_driven_teeth);
    pinion_od = mb_gear_outer_d(vm_pinion_teeth);
    ir_boss_r = vm_ir_flange_d / 2 + 1.5;
    m3_clear = vm_m3_clear_d + 2 * $slop;

    vm_assert_coil_gap_metal_free();

    // Electronics box vs TX deck.
    assert(mb_porch_x0(layout) - deck_half_x >= vm_porch_gap - 0.01,
        "Electronics box is closer than vm_porch_gap to the TX deck");
    assert(vm_lid_top_z() < vm_head_z() - 1,
        "Box lid reaches the rotor head height");

    // M8 stud.
    assert(vm_skirt_h >= vm_shcs_head_h + vm_race_spacer_h + 0.5,
        "Skirt shorter than SHCS head + spacer — head would hit the table");
    assert(vm_shcs_tip_z() >= vm_nut_z1() + 3,
        "M8 tip too short above the nut to center the rotor — use a longer screw");
    assert(vm_race_spacer_od < vm_bearing_inner_race_od - 0.3,
        "Race spacer OD would touch the 608 shields");
    assert(vm_race_spacer_od < vm_bearing_lip_id && vm_bolt_head_pocket_d < vm_bearing_lip_id,
        "Spacer / head must pass through the bottom 608 lip hole");
    assert(vm_bearing_lip_id < vm_bearing_od - 2,
        "Bearing lip ID too large — outer race has no seat");
    assert(vm_bolt_head_pocket_d > vm_shcs_head_d,
        "Head pocket must clear the SHCS head OD");

    // Rotor.
    assert(vm_rotor_collar_d < vm_bearing_inner_race_od - 0.5,
        "Rotor collar would touch the top 608 shields");
    assert(vm_rotor_collar_d >= vm_shcs_d + vm_tip_bore_extra + 2.4,
        "Rotor collar wall around the tip bore too thin");
    assert(mb_hex_circum_d(vm_nut_af + vm_nut_socket_extra) + 4 < mb_gear_root_d(vm_driven_teeth),
        "Nut socket too close to the gear roots");
    assert(vm_key_flat < vm_rotor_shaft_d && vm_rotor_shaft_d < vm_top_journal_d,
        "Key / shaft must pass through the top 608 bore");
    assert(vm_rotor_top_z() - vm_center_pilot_depth > vm_journal_z1(),
        "Center screw pilot reaches the journal");

    // Motors, wells, gears.
    assert(motor_y - mb_well_bore_d() / 2 - mb_bearing_pocket_d() / 2 >= 3,
        "Motor well bore too close to the bottom 608 pocket");
    assert(vm_well_rim_z() < vm_gear_z0() - 1,
        "Motor well rim reaches the gear plane");
    assert(vm_bot_bearing_z1() < vm_rotor_z0() - 1,
        "Bearing boss top reaches the rotor underside");
    assert(vm_well_floor_z() >= -vm_skirt_h + 4,
        "Motor well floor too close to the table (no room for terminals / wires)");
    assert(vm_motor_shaft_len - vm_pinion_face_gap >= 2.5,
        "Motor shaft too short for a press-fit pinion");
    assert(col_r_min - mb_col_d() / 2 > driven_od / 2 + 1,
        "Column collides with the driven gear");
    assert(col_to_motor - mb_col_d() / 2 > max(mb_well_od(), pinion_od) / 2 + 0.5,
        "Column collides with a motor well / pinion");

    // Top bearing + deck.
    assert(vm_top_bearing_z0() > vm_gear_z1() + 1,
        "Top 608 boss reaches the gear plane");
    assert(vm_top_bearing_lip_id > vm_rotor_collar_d + 1 && vm_top_bearing_lip_id < vm_bearing_od - 1.5,
        "Top 608 lip must clear the rotor and still hold the outer race");
    assert(vm_deck_shaft_clear_d > vm_rotor_shaft_d + 1,
        "Deck shaft hole too tight");
    assert(vm_deck_shaft_clear_d < vm_ring_id - vm_ring_fit - 2,
        "Deck shaft hole cuts into the TX ring island");
    assert(vm_locate_fit < m3_clear - 3 && vm_locate_loose < 2 * (m3_clear - 3),
        "Locating spigots must be tighter than the screw clearance");
    assert(vm_locate_d >= vm_insert_boss_min_d(),
        "Locating spigot too thin around the column insert");

    // Head.
    assert(vm_head_z() > vm_deck_top_z() + 3,
        "Rotor head too close to the TX deck top");
    assert(vm_head_disk_top() - vm_cw_depth >= vm_head_rx_top() + 0.4,
        "Counterweight pockets break into the RX rebate");
    assert(vm_pcb_hole_dx < vm_display_pcb_x - 4 && vm_pcb_hole_dy < vm_display_pcb_y - 4,
        "PCB holes outside the 40x60 board");
    assert(vm_head_pcb_z() - vm_insert_depth(vm_insert_len_head) >= 0.4,
        "Head insert pilots break through the plate");

    // Inserts.
    assert(mb_col_d() >= vm_insert_boss_min_d() && vm_post_d >= vm_insert_boss_min_d(),
        "Insert boss too thin (column / post)");

    // IR index sensor.
    assert(vm_ir_r - ir_boss_r > vm_ring_od / 2 + vm_ring_fit + 1,
        "IR sensor overlaps the coil rebates");
    assert(vm_ir_r - vm_ir_d / 2 > vm_head_disk_d() / 2 + 0.5,
        "IR receiver hole cuts into the RX disk");
    assert(vm_ir_r + ir_boss_r < deck_half_x,
        "IR emitter outside the TX deck");
    assert(vm_ir_rx_tip_z() - vm_ir_tx_tip_z() >= vm_ir_min_gap,
        "IR emitter and receiver domes too close (they pass each other every turn)");
    assert(vm_ir_rx_tip_z() <= vm_head_z() + 0.5,
        "IR receiver dome sits too deep in the head (it must look out of the underside)");
    assert(vm_ir_rx_seat_z < vm_head_pcb_z() - 1,
        "IR receiver seat collides with the PCB");
    assert(vm_deck_top_z() + vm_ir_tx_protrude - vm_ir_len > vm_top_bearing_z1(),
        "IR emitter reaches down to the top 608");
}
