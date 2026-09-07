# vmoji mechanical (OpenSCAD)

Coil-safe dual-motor gear drive for the volumetric display. Metal stays
**below the TX deck** (one 608ZZ + M8 journal screw). A printed plastic
shaft runs through the TX–RX gap. Preview the full stack with
[`assembly-preview.scad`](assembly-preview.scad) (F5; optional Animate).

Defaults live in [`vmoji-mech-params.scad`](vmoji-mech-params.scad). Every
print file includes that before `motor-base-common.scad`.

## BOM

| Qty | Part | Notes |
|-----|------|--------|
| 1 | 608ZZ bearing | Bottom only. Do **not** put a steel bearing under the TX coil. |
| 1 | M8×16 DIN 912 / ISO 4762 socket head cap screw | Journal. Head Ø13 × 8 mm, hex key 6 mm. |
| 1 | M8 flat washer | Between SHCS head and 608 inner race. |
| 4 | M3 heat-set inserts | Column tops for TX deck bolts. |
| 2 | RF-300C-class motors | Ø24 × 12, Ø1.0 shaft. |
| — | M3 screws / nuts | Collet flanges, gear clamps, lid, hat (plastic OK for nut-trap clamps; metal for brass inserts). |
| 1 | Printed plastic driven shaft | Through the coil gap — no full-length metal rod. |

**Buy the journal screw:** [M8 hex-socket assortment (16/20/25/30)](https://www.amazon.ca/gp/product/B0GPXBPR31).
Use the **16 mm** screws for the journal; longer lengths are spares.

These SHCS are typically **fully threaded**. The thread major Ø runs inside
the 608 ID — oil the bearing; expect mild race wear at display RPM. Fine for v1.

## Coil-safe rules

- Face gap TX top → RX bottom: **8–20 mm** (`vm_coil_gap`, prefer 8).
- Journal metal top must stay below the TX deck (`vm_assert_coil_gap_metal_free`).
- TX deck uses a **flanged plastic bushing** only — no second 608 under TX.
- No set-screw into the plastic driven shaft (slit clamps only).

World **z=0** is the structural floor / bearing bottom. Table contact is at
`-vm_skirt_h` (~10.5 mm) so the SHCS head sits above the table without feet.

## Print orientation

| Part | File | Orientation / tips |
|------|------|--------------------|
| Driven shaft | `driven-shaft.scad` | **Axis vertical** (PETG/ABS). |
| Motor base | `motor-base.scad` | Skirt down on bed, or floor on bed if your slicer prefers — skirt must print cleanly. |
| TX deck | `motor-tx-deck.scad` | Bushing flange down. |
| Gears | `motor-pinion.scad`, `driven-gear.scad` | Flat on teeth or hub; herringbone needs good cooling. |
| Collets | `motor-collet.scad` | Flange on bed. |
| Lid | `motor-base-lid.scad` | Lip down or as preferred. |
| Collar + hat | `shaft-collar.scad` | RX seat down. |

Tune `$slop` (default 0.2) and the fit extras below after a test print.

## Assembly order

1. Press 608 into the base pocket (outer race on the OD lip).
2. From below: M8 washer, then M8×16 SHCS up through the bearing.
3. Press the plastic shaft onto the shank (press zone in the boss; tip uses the clearance bore).
4. Seat driven gear on the shaft flange; slit-clamp. Mount motors in collets; pinions on Ø1 shafts; mesh.
5. Heat-set M3 inserts in column tops; bolt on TX deck + bushing; seat TX ring.
6. Slide shaft collar / RX seat; set coil gap; clamp. Mount PCB on the hat.
7. Porch lid last.

## Fit tuning

| Param | Default | Role |
|-------|---------|------|
| `$slop` | 0.2 | Global print clearance (bores, pockets). |
| `vm_journal_fit_extra` | 0.05 | Press bore on M8 shank (plus `$slop`). |
| `vm_journal_clear_extra` | 0.35 | Loose tip bore above the press. |
| `vm_bushing_fit_extra` | 0.25 | TX bushing on Ø8 plastic. |
| `vm_bearing_fit` | 0.15 | 608 OD pocket. |
| `vm_insert_hole_d` | 4.0 | Heat-set pilot — match your insert datasheet. |
| `vm_pcb_hole_spacing` | 11 | Collar hat bolt circle (tune to real PCB). |

**Do not change casually:** `vm_motor_shaft_d` (proven pinion press-fit).

The display ghost in the preview (60×40 PCB + 8×8 matrix) is **swept volume**
only — it is not the hat mounting pattern.

## File map

| File | Role |
|------|------|
| `vmoji-mech-params.scad` | Shared dims, Z stack, asserts |
| `motor-base-common.scad` | Clearances, gear math, layout helpers |
| `assembly-preview.scad` | Full F5 assembly + animation |
| `motor-base.scad` | Floor, skirt, 608 pocket, columns, porch |
| `motor-base-lid.scad` | Porch lid |
| `motor-tx-deck.scad` | TX plate + plastic bushing |
| `motor-collet.scad` | Motor clamp + keyed flange |
| `motor-pinion.scad` / `driven-gear.scad` | 14T / 28T herringbone |
| `driven-shaft.scad` | Plastic shaft + journal bores |
| `shaft-collar.scad` | RX seat, clamp, PCB hat |
