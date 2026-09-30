# vmoji mechanical (OpenSCAD) — v2

Coil-safe dual-motor gear drive for the volumetric display. The rotor turns on
**two 608ZZ**: the bottom one clamped on an M8 stud in the base, the top one hanging
under the TX deck, `vm_top_bearing_coil_clear` (10 mm) below the TX coil. A printed
plastic rotor runs through the TX–RX gap. Preview the full stack with
[`assembly-preview.scad`](assembly-preview.scad) (F5; optional Animate, `section` toggle)
and check it with [`check-collisions.sh`](check-collisions.sh).

Defaults live in [`vmoji-mech-params.scad`](vmoji-mech-params.scad). Every
print file includes that before `motor-base-common.scad`.

## BOM

| Qty | Part | Notes |
|-----|------|--------|
| 2 | 608ZZ bearing | Bottom (base pocket) + top (TX deck hanging pocket). |
| 1 | M8×25 DIN 912 / ISO 4762 SHCS | Stud through the bottom 608. Head Ø13 × 8 mm, hex key 6 mm. |
| 1 | M8 hex nut | Clamps the bottom 608 inner race; the rotor's hex socket drops over it. |
| 2 | Printed race spacers | `bearing-spacer.scad`, 100 % infill. Head and nut are wider than the inner race; spacers keep them off the shields. |
| 8 | M3×6 heat-set inserts (Ø4.2) | 4 column spigots (TX deck bolts) + 4 lid posts. |
| 4 | M3×4 heat-set inserts (Ø4.2) | Rotor head PCB bosses. |
| 4 | M3×8 screws | TX deck → columns. |
| 4 | M3×8 screws | Lid → posts. |
| 4 | M3×6 screws | PCB → head. |
| 1 | M3×10 SHCS | Head center screw, self-taps into the shaft top. |
| 0–6 | M3 nuts | Counterweights (glued into the head pockets). |
| 2 | RF-300C-class motors | Ø24 × 12, Ø2.0 shaft sticking out 4–5 mm (`vm_motor_shaft_len`). |
| 1 | IR LED + 1 phototransistor | 5 mm by default (`vm_ir_d`, `vm_ir_flange_d`, `vm_ir_len` for 3 mm parts). |
| 1 | 40 × 60 mm proto PCB | 4 M3 corner holes; set `vm_pcb_hole_dx/dy` to your board (placeholder 52 × 32). |

**Buy the stud screw:** [M8 hex-socket assortment (16/20/25/30)](https://www.amazon.ca/gp/product/B0GPXBPR31).
Use a **25 mm** screw: its tip sticks ~8 mm above the nut and centers the rotor.

These SHCS are typically fully threaded. The thread crest sits inside the 608 bore;
that's fine because the inner race is clamped by the stud, not sliding on it.

## Coil-safe rules

- Face gap TX top → RX bottom: **8–20 mm** (`vm_coil_gap`, prefer 8).
- The M8 stud tip stays below the TX deck (`vm_assert_coil_gap_metal_free`).
- The top 608 stays `vm_top_bearing_coil_clear` below the TX coil (default 10 mm, hard floor 4 mm).
- No set-screw into the plastic rotor, no threads in plastic under load (hex + key drives).

World **z=0** is the structural floor / bottom 608 bottom. Table contact is at
`-vm_skirt_h` (~10.5 mm) so the SHCS head sits above the table without feet.

## Spin direction and gears

Single helical 14T / 28T, m1.25, 25°. Herringbone can't be meshed by dropping the rotor in;
helical can (the unpowered pinions turn as the teeth slide in). Mating helical gears need
**opposite** helix angles (the v1 files used the same sign for both).

`vm_rotor_dir = -1`: the rotor spins **clockwise viewed from the top**, the pinions
counter-clockwise. The hands are chosen so the pinions are pushed **down** toward the
motors (keeps the press-fits seated) and the rotor slightly up (far less than its weight).
If the rotor spins the other way, swap the motor leads (both motors in parallel, same
polarity). If you'd rather have CCW, set `vm_rotor_dir = 1` and reprint pinions + rotor.

## Material (PLA)

Everything prints in PLA. PLA softens around 55–60 °C and creeps under constant load, so:

- Don't run the motors hot; a warm can slowly loosens the pinion press-fit and crush ribs.
  If a pinion slips, put a drop of **CA glue** (cyanoacrylate, "super glue") on the shaft and press it back on.
- Keep the TX coil power reasonable; the deck holds the top 608 pocket right under it.
- Race spacers: 100 % infill. Tighten the M8 stud firmly but don't crank it.

## Print orientation

| Part | File | Orientation / tips |
|------|------|--------------------|
| Motor base | `motor-base.scad` | Skirt down on bed. Supports from the build plate inside the skirt (floor + well ledges bridge the hollow). |
| TX deck | `motor-tx-deck.scad` | **Upside down** (coil face on bed): no overhangs, the bearing pocket opens upward. |
| Rotor shaft | `rotor-shaft.scad` | Gear face down, axis vertical. Brim; 4+ perimeters (thin shaft). |
| Rotor head | `rotor-head.scad` | Underside (RX coil rebate) on bed. |
| Pinions (×2) | `motor-pinion.scad` | Underside down; good cooling. |
| Lid | `motor-base-lid.scad` | Top face on bed (lip up). |
| Race spacers (×2) | `bearing-spacer.scad` | Flat, 100 % infill. |
| Fit coupons | `fit-test.scad` | Flat. Pick one with `coupon`, or `all`. |

## Assembly order

Every step is top-down.

1. Print the fit coupons first and tune (see **Fit tuning**).
2. Heat-set the inserts while the parts are bare: M3×6 into the 4 column spigots and the
   4 lid posts, M3×4 into the 4 head bosses (the iron clearance above each is checked).
3. **Bottom stud:** press a 608 into the base pocket (outer race on the z=0 lip). From below:
   spacer, then M8×25 up through the bearing. On top: spacer, then the M8 nut. Tighten (6 mm key
   below, 13 mm wrench above). The stud + nut must now spin freely with the inner race.
4. **Motors:** solder leads, thread them down through the well ledge hole into the skirt and
   up through the box floor slots. Press each motor into its crush-rib well until it sits on the ledge.
5. **Pinions:** put a 0.5 mm shim (`vm_pinion_face_gap`, e.g. two business cards) on the motor
   face and press the pinion down onto it; the ledge takes the force. Remove the shim.
6. **Rotor:** lower it onto the stud. The tip enters the centering bore, the hex socket drops
   over the nut (turn slightly), and the helical teeth twist into mesh with the pinions.
7. **TX deck:** glue the TX coil into the rebate (leads in the groove toward the box), push the
   IR LED in from below (flange against the step, dab of glue), and press the top 608 into the
   hanging pocket from below until it stops on the lip.
8. Lower the deck over the rotor: the bearing slides onto the journal and the column spigots
   drop into the deck recesses. Bolt it down with 4× M3×8. Route TX + IR leads into the box
   through the notch at the top of its wall.
9. **Head:** hot-glue the RX coil into the rebate (glue into the three notches), leads up
   through the lead hole. Drop the phototransistor into its hole from above (dome down,
   flange on the boss).
10. Slide the head onto the double-D key and drive the M3×10 center screw (self-taps; snug only).
11. Bolt the PCB with 4× M3×6; solder the RX leads and the phototransistor.
12. Screw the lid on (4× M3×8).
13. Balance (below).

## Balancing

The LED matrix sits off-axis, so the rotor is heavy on one side. At ~1000 RPM a few grams
off-center shakes the whole thing.

1. Take the base off the table and lay it on its side (rotor axis horizontal). Unpowered.
2. Let the rotor come to rest; the heavy side ends up at the bottom.
3. Glue M3 nuts into the head pockets on the **top** (light) side. Repeat until the rotor stays
   wherever you leave it.
4. Spin up slowly and feel for vibration; nudge weights if needed.

## Fit tuning

Print `fit-test.scad`, try each coupon on the real part, then copy the winner here.

| Param | Default | Coupon | Role |
|-------|---------|--------|------|
| `vm_motor_shaft_d` | 1.9 | `motor_shaft` | Pinion press bore on the Ø2 shaft (proven; change only if needed). |
| `vm_top_journal_d` | 7.95 | `journal` | Journal: snug slide into the top 608 inner race. |
| `vm_bearing_fit` | 0.15 | `bearing_od` | 608 OD pockets (plus `$slop`). |
| `vm_nut_socket_extra` | 0.4 | `nut_socket` | Hex socket over the M8 nut (loose: drive only). |
| `vm_tip_bore_extra` | 0.15 | `tip_bore` | Snug bore on the M8 tip (this centers the rotor). |
| `vm_key_fit` | 0.25 | `key` | Head socket on the double-D key. |
| `vm_well_rib_interf` | 0.15 | `well` | Crush-rib grip on the motor can. |
| `vm_insert_hole_d` | 4.0 | `insert` | Heat-set pilot (plus `$slop`). |
| `vm_locate_fit` / `vm_locate_loose` | 0.15 / 0.8 | `locate` | Deck recesses on the column spigots (diagonal pair tight). |
| `vm_ir_hole_extra` | 0.3 | `ir` | IR LED / phototransistor holes. |
| `$slop` | 0.2 | — | Global print clearance (clearance holes). |

The display ghost in the preview (60×40 PCB + 8×8 matrix) is approximate; the swept
volume check uses its envelope.

## Collision and assembly checks

- **Analytic asserts** (`vm_assert_layout()` in `motor-base-common.scad`) run in every file:
  box ↔ deck gap (`vm_porch_gap`, 3 mm), coil gaps, bearing-to-coil distance, metal below the
  coil zone, well ↔ bearing walls, gear ↔ column / well clearance, IR beam gap, insert boss walls, and more.
- **Geometric checks:** `./check-collisions.sh` intersects every part pair as assembled
  (spinning parts as swept envelopes) plus a soldering-iron cylinder above every insert, and
  fails on any real overlap. Takes ~5 min on OpenSCAD 2021; newer builds are faster with
  `OPENSCAD_ARGS="--enable=manifold"`. Run a subset with `./check-collisions.sh base_deck coils`.

## File map

| File | Role |
|------|------|
| `vmoji-mech-params.scad` | Shared dims, Z stack |
| `motor-base-common.scad` | Clearances, gear math, layout, envelopes, `vm_assert_layout()` |
| `vmoji-assembly.scad` | World placement of every part + hardware ghosts |
| `assembly-preview.scad` | Full F5 assembly + animation + section |
| `collision-check.scad` / `check-collisions.sh` | Pairwise collision + iron-access checks |
| `motor-base.scad` | Floor, skirt, bottom 608 pocket, crush-rib wells, columns, box |
| `motor-base-lid.scad` | Box lid |
| `motor-tx-deck.scad` | TX plate + hanging top 608 pocket + IR emitter |
| `motor-pinion.scad` | 14T helical, press-fit |
| `rotor-shaft.scad` | Rotor: 28T helical gear + nut socket + journal + key |
| `rotor-head.scad` | RX coil holder + PCB mount + counterweights + IR receiver |
| `bearing-spacer.scad` | 608 inner-race spacer |
| `fit-test.scad` | Fit coupons |
| `archive/` | v1 parts (driven shaft/gear, shaft collar, collets). Kept for reference; their includes no longer resolve from that folder. |
