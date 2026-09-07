// Shared helpers for dual-motor offset gear drive parts.
// Include BOSL2/std.scad, BOSL2/screws.scad, and BOSL2/gears.scad before this file.
// Mating defaults live in each print file's Customizer and must stay in sync.

/* ---- Fasteners / clearance ---- */

function mb_clearance_hole_d(screw_spec) =
    struct_val(screw_info(screw_spec), "diameter") + 0.4 + 2 * $slop;

function mb_nut_circum_d(screw_spec) =
    struct_val(nut_info(screw_spec), "width") / cos(30);

function mb_nut_pocket_d(screw_spec, extra_d = 0) =
    mb_nut_circum_d(screw_spec) + extra_d + 2 * $slop;

function mb_collet_od(motor_d, wall) =
    motor_d + 2 * wall;

// Flange bolt angles: first at +Y so the +X slit/key sector stays clear.
function mb_flange_bolt_angles(n) =
    [for (i = [0:n - 1]) 90 + i * 360 / n];

/* ---- 608ZZ bearing (8 x 22 x 7) ---- */

function mb_bearing_id() = 8;
function mb_bearing_od() = 22;
function mb_bearing_h() = 7;

// Printed pocket OD: bearing OD + fit clearance.
function mb_bearing_pocket_d(fit = 0.15) =
    mb_bearing_od() + fit + 2 * $slop;

// Shaft clearance through plastic (not the bearing bore).
function mb_shaft_clear_d(shaft_d = 8, extra = 0.6) =
    shaft_d + extra + 2 * $slop;

/* ---- Gear train defaults (override in Customizer per file) ---- */

function mb_gear_mod() = 1.25;
function mb_pinion_teeth() = 14;
function mb_driven_teeth() = 28;
function mb_gear_helical() = 25;
function mb_gear_backlash() = 0.3;
function mb_gear_thickness() = 10;
function mb_gear_pressure_angle() = 20;

// Center distance including FDM backlash slack (added outside gear_dist).
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

function mb_motor_axis_y(
    mod = mb_gear_mod(),
    pinion_teeth = mb_pinion_teeth(),
    driven_teeth = mb_driven_teeth(),
    helical = mb_gear_helical(),
    backlash = mb_gear_backlash()
) =
    mb_gear_center_dist(mod, pinion_teeth, driven_teeth, helical, backlash);

/* ---- Keyed flange profile (motor collet) ---- */

module mb_flange_profile(flange_od, key_w, key_d) {
    union() {
        circle(d = flange_od);
        right(flange_od / 2)
            square([key_d * 2, key_w], center = true);
    }
}

module mb_flange_solid(flange_od, flange_h, key_w, key_d) {
    linear_extrude(height = flange_h)
        mb_flange_profile(flange_od, key_w, key_d);
}

function mb_col_d() = 12;

function mb_layout(
    motor_y,
    motor_d,
    collet_flange_od,
    driven_od,
    pinion_od,
    ring_od,
    bearing_pocket_d,
    deck_margin,
    wall_t
) =
    let(
        cavity_half_x = driven_od / 2 + 3,
        cavity_half_y = motor_y + pinion_od / 2 + 2,
        col_d = mb_col_d(),
        deck_half_y = max(
            motor_y + collet_flange_od / 2 + deck_margin,
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
        ]]
    ];

function mb_layout_get(layout, key) =
    struct_val(layout, key);

module mb_herringbone_gear(
    teeth,
    thickness = mb_gear_thickness(),
    mod = mb_gear_mod(),
    helical = mb_gear_helical(),
    backlash = mb_gear_backlash(),
    pressure_angle = mb_gear_pressure_angle(),
    shaft_diam = 0,
    slices = 6
) {
    spur_gear(
        mod = mod,
        teeth = teeth,
        thickness = thickness,
        helical = helical,
        herringbone = true,
        backlash = backlash,
        pressure_angle = pressure_angle,
        shaft_diam = shaft_diam,
        slices = slices,
        anchor = CENTER
    );
}
