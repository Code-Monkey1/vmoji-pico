# Mechanics

The printable parts are OpenSCAD models in [`3D/`](../3D), built on the
[BOSL2](https://github.com/BelfrySCAD/BOSL2) library (setup:
[Getting started](getting-started.md#5-3d-the-bosl2-library)). To make the parts, see
[Printing](printing.md) and [Assembly](assembly.md).

## The design in one paragraph

A dual-motor helical gear drive spins a plastic rotor through the gap between two induction
coils. The rotor turns on **two 608ZZ bearings**: the bottom one clamped on an M8 stud in the
base, the top one hanging under the TX deck, at a safe distance below the TX coil. The
electronics box beside the base holds the 12 V jack and switch.

## Parameters

Every dimension lives in one file,
[`3D/vmoji-mech-params.scad`](../3D/vmoji-mech-params.scad), and every part derives from
it. Change a value there, never in a part file. Shared helpers, layout math and
`vm_assert_layout()` live in `motor-base-common.scad`; `vm_assert_coil_gap_metal_free()` sits
in the params file itself. The docs name parameters rather than repeat their values, so the
params file is always the reference.

## Rules the design must keep

Enforced by asserts (`vm_assert_layout()`, `vm_assert_coil_gap_metal_free()`):

- **No metal between the coils.** The M8 stud tip stays below the TX deck, and the top 608
  stays `vm_top_bearing_coil_clear` below the TX coil.
- **Coil gap.** The face-to-face gap (`vm_coil_gap`) has a hard floor: closer overheated
  the TX coil on the first build.

Design rules no check enforces, so keep them in mind when changing parts:

- **Bearing clearance.** The rotor collar stays `vm_rotor_collar_gap` under the top 608
  inner race; too small a gap crushed the bearing between collar and deck on the first
  build. The deck boss runs `vm_top_bearing_skirt` below the bearing to hide it.
- **No load on plastic threads.** No set screws into the plastic rotor; hexes and keys
  carry the torque.

World **z = 0** is the base floor (the bottom of the lower 608). The table is at
`-vm_skirt_h`, so the stud's head clears it without feet.

## Spin direction and gears

The gears are single helical (`vm_pinion_teeth` / `vm_driven_teeth`, module
`vm_gear_mod`, helix angle `vm_gear_helical`, pressure angle `vm_gear_pressure_angle`).
Helical, not herringbone, so the rotor can be dropped in and the unpowered pinions turn into
mesh. Mating helical gears need **opposite** helix hands; the models derive both from
`vm_rotor_dir`.

With `vm_rotor_dir = 1` the rotor spins **counter-clockwise seen from above**. The hands
are chosen so the helix pushes the pinions **down** onto the motors, keeping their press fit
seated. Spinning the wrong way pulls the pinions off their shafts within seconds (seen on
the first build): if the rotor turns clockwise, swap the motor leads (the motors are wired
in parallel, same polarity). To run clockwise on purpose, set `vm_rotor_dir = -1` and
reprint the pinions and the rotor.

## Checks

```bash
3D/scripts/check-collisions.sh               # all checks, several minutes
3D/scripts/check-collisions.sh base_deck     # a subset (see --help for the list)
JOBS=2 3D/scripts/check-collisions.sh        # fewer parallel renders, if memory is tight
3D/scripts/render-preview.sh                 # render the assembly to 3D/preview.png
3D/scripts/render-preview.sh --update-docs   # refresh the README image
```

- **Asserts** (`vm_assert_layout()`) run in every file, every render: clearances, coil
  gaps, wall thicknesses, the IR beam, insert bosses and more.
- **The collision check** intersects every pair of parts as assembled, spinning parts as
  swept volumes, plus a soldering-iron cylinder above every heat-set insert, and fails on
  any real overlap. It also checks the 12 V jack and the switch keep-out space in the box.
  A check that doesn't finish cleanly fails the run, so running out of memory can't pass.

Never weaken an assert or a check to make a build pass: they are the safety net.

Preview the whole machine in OpenSCAD with `3D/assembly-preview.scad` (F5). It has toggles
per part, an exploded view, a cross-section, and animation (*View → Animate*). The display
(PCB and matrix) is an approximate stand-in; the collision check uses its swept envelope.

## Files

| File | Role |
|------|------|
| `vmoji-mech-params.scad` | All dimensions and the vertical stack |
| `motor-base-common.scad` | Shared helpers, gear math, layout, `vm_assert_layout()` |
| `vmoji-assembly.scad` | Where every part sits in the assembly |
| `assembly-preview.scad`, `collision-check.scad` | Preview and collision scenes |
| `motor-base.scad`, `motor-base-lid.scad`, `motor-tx-deck.scad` | The stationary structure |
| `rotor-shaft.scad`, `rotor-head.scad`, `motor-pinion.scad`, `bearing-spacer.scad` | The moving parts and spacers |
| `fit-test.scad` | Fit coupons ([Printing](printing.md#fit-tuning)) |
| `scripts/` | Collision check, STL export, preview render (each has `--help`) |
