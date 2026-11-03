# Printing

Every part prints in **PLA**. Background on the design: [Mechanics](mechanics.md).

## Export the STLs

```bash
3D/scripts/export-stl.sh             # all printed parts, fresh, into 3D/stl/
3D/scripts/export-stl.sh fit-test    # the fit coupons (not part of the default set)
```

The script replaces the whole `3D/stl/` folder, so no stale or obsolete file survives. It
only touches the folder if every part renders without errors, warnings or failed asserts.
STLs keep the modelled orientation: orient them in the slicer as below.

## Orientation and settings

| Part | Qty | Orientation and tips |
|------|-----|----------------------|
| `motor-base` | 1 | Skirt down. Supports from the build plate inside the skirt. |
| `motor-tx-deck` | 1 | **Upside down** (coil face on the bed): no overhangs. |
| `rotor-shaft` | 1 | Gear face down. Brim, 5+ perimeters, 100 % infill, a little hotter for layer bonding. Let the bed cool and lift it by the gear, never by the shaft. |
| `rotor-head` | 1 | Underside (coil rebate) on the bed. |
| `motor-pinion` | 2 | Underside down, good cooling. |
| `motor-base-lid` | 1 | Top face on the bed (lip up). |
| `bearing-spacer` | 2 | Flat, 100 % infill. |
| `fit-test` | — | Flat. Pick one coupon with its `coupon` parameter, or `all`. |

## PLA notes

PLA softens around 55–60 °C and creeps under steady load:

- Don't run the motors hot: a warm motor can slowly loosen the pinion press fit and the
  crush ribs.
- Keep the TX coil power reasonable; the top bearing pocket sits right under it.
- Printed gears are audible. A thin film of plastic-safe grease (PTFE or silicone, not
  petroleum-based) on the teeth quiets them a lot.

## Fit tuning

Printers differ, so tight fits are tuned with coupons, not guessed. Print `fit-test.scad`,
try each coupon on the real part, and set the winning value in
[`3D/vmoji-mech-params.scad`](../3D/vmoji-mech-params.scad). The params file comments
record what has been tried.

| Parameter | Coupon | Fit |
|-----------|--------|-----|
| `vm_motor_shaft_d`, `vm_motor_shaft_lead_d` | `motor_shaft` | Pinion bore on the motor shaft: a lead-in, then a grip. Hot-pressed and glued ([Assembly](assembly.md)). |
| `vm_top_journal_d` | `journal` | Rotor journal in the top 608: slides on by hand. Loose: one wrap of tape. Tight: sand it while spinning it in a drill. |
| `vm_bearing_fit` | `bearing_od` | 608 pockets (plus `$slop`). Still loose: tape the outer race. |
| `vm_nut_socket_extra` | `nut_socket` | Hex socket over the M8 nut (drives only, doesn't center). |
| `vm_tip_bore_extra` | `tip_bore` | Snug bore on the M8 stud tip: this centers the rotor. |
| `vm_key_fit` | `key` | Head socket on the shaft's double-D key. |
| `vm_well_rib_interf` | `well` | Crush-rib grip on the motor can. |
| `vm_insert_hole_d` | `insert` | Heat-set insert pilot holes. |
| `vm_locate_fit`, `vm_locate_loose` | `locate` | Deck recesses on the column spigots (one diagonal pair tight). |
| `vm_ir_hole_extra` | `ir` | IR LED hole (the receiver uses `vm_ir_rx_hole_d`). |
| `vm_jack_fit` | `jack` | 12 V jack cradle: snug drop-in, the plug must seat fully. |
| `vm_ring_fit_od`, `vm_ring_fit_id` | — (real coils) | Coil rebates: clearance around the coil and its center island. |
| `vm_ring_rebate_extra`, `vm_rx_rebate_extra` | — (real coils) | Extra rebate depth for the TX deck and the rotor head. |
| `$slop` | — | Global print clearance, set at the top of each part file. |
