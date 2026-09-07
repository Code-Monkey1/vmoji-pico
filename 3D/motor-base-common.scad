// Shared helpers for dual-motor offset gear drive parts.
// Include BOSL2 (std, screws, gears as needed) and vmoji-mech-params.scad before this file.

/* ---- Fasteners / clearance ---- */

function mb_clearance_hole_d(screw_spec) =
    struct_val(screw_info(screw_spec), "diameter") + 0.4 + 2 * $slop;

function mb_nut_circum_d(screw_spec) =
    struct_val(nut_info(screw_spec), "width") / cos(30);

function mb_nut_pocket_d(screw_spec, extra_d = 0) =
    mb_nut_circum_d(screw_spec) + extra_d + 2 * $slop;

function mb_collet_od(motor_d, wall) =
    motor_d + 2 * wall;

function mb_flange_bolt_angles(n) =
    [for (i = [0:n - 1]) 90 + i * 360 / n];

/* ---- Bearing / shaft (defaults from params) ---- */

function mb_bearing_id() = vm_bearing_id;
function mb_bearing_od() = vm_bearing_od;
function mb_bearing_h() = vm_bearing_h;

function mb_bearing_pocket_d(fit = undef) =
    let (f = is_undef(fit) ? vm_bearing_fit : fit)
        mb_bearing_od() + f + 2 * $slop;

function mb_shaft_clear_d(shaft_d = undef, extra = 0.6) =
    let (d = is_undef(shaft_d) ? vm_shaft_d : shaft_d)
        d + extra + 2 * $slop;

function mb_bushing_id(fit_extra = undef) =
    let (e = is_undef(fit_extra) ? vm_bushing_fit_extra : fit_extra)
        vm_shaft_d + e + 2 * $slop;

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
