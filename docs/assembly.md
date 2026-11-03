# Assembly

How to put the machine together once the parts are printed ([Printing](printing.md)).

## Parts list

| Qty | Part | Notes |
|-----|------|-------|
| 2 | 608ZZ bearing | Bottom (base pocket) and top (hanging under the TX deck). |
| 1 | M8×25 socket head cap screw (DIN 912 / ISO 4762) | The stud through the bottom 608. **25 mm**: its tip pokes above the nut and centers the rotor. Fully threaded is fine. Sold in assortments, e.g. [this one](https://www.amazon.ca/gp/product/B0GPXBPR31). |
| 1 | M8 hex nut | Clamps the bottom 608 inner race; the rotor's hex socket drops over it. |
| 8 | M3 heat-set inserts, Ø4.2 mm, 6 mm long | 4 column tops (TX deck bolts) and 4 lid posts. |
| 4 | M3 heat-set inserts, Ø4.2 mm, 4 mm long | Rotor head PCB bosses. |
| 2 | Printed race spacers (`bearing-spacer`) | The stud head and nut are wider than the inner race; the spacers keep them off the bearing shields. |
| 8 | M3×8 screws | TX deck to columns (4), lid to posts (4). |
| 4 | M3×6 screws | PCB to rotor head. |
| 1 | M3×10 socket head cap screw | Rotor head center screw; self-taps into the shaft top. |
| 0–6 | M3 nuts | Counterweights, glued into the head pockets. |
| 2 | RF-300C-class motors | Ø24 × 12 mm can, Ø2 mm shaft (`vm_motor_*`). |
| 1 + 1 | IR LED + IR receiver | LED: 5 mm by default (`vm_ir_*` for 3 mm parts). Receiver: small package glued face-down over its hole. |
| 1 | Induction coil pair (TX + RX) | Sized by `vm_ring_*`. |
| 1 | 12 V female jack, 2.1×5.5 mm, screw terminals | Sits in the box cradle (`vm_jack_*`). |
| 1 | 12 V lit toggle switch with flip cover | Ø12 mm panel hole in the box wall (`vm_switch_*`). |
| 1 | Zip tie, ≤ 4.5 mm wide | Holds the jack in its cradle. |
| 1 | 40 × 60 mm proto PCB | 4 M3 corner holes; set `vm_pcb_hole_dx/dy` to your board. |

Sizes in parentheses name the parameters in
[`3D/vmoji-mech-params.scad`](../3D/vmoji-mech-params.scad) to adjust for your parts.

## Order

Everything goes in from the top.

1. **Tune the fits** with the coupons first ([Printing](printing.md#fit-tuning)).
2. **Heat-set the inserts** while the parts are bare: 6 mm inserts into the 4 column tops
   and the 4 lid posts, 4 mm inserts into the 4 head bosses.
3. **Bottom stud.** Press a 608 into the base pocket. From below: a spacer, then the M8×25
   up through the bearing. On top: a spacer, then the nut. Tighten firmly but don't crank
   it (6 mm hex key below, 13 mm wrench above). Stud and nut must now spin freely with the
   inner race.
4. **Motors.** Solder the leads, thread them down through the well ledge hole and up
   through the box floor slots. Press each motor into its well until it sits on the ledge.
5. **Pinions (hot press).** Put a shim (`vm_pinion_face_gap`, e.g. two business cards) on
   the motor face. Warm the shaft with a soldering iron for 3–5 s (shaft only, not the
   motor), press the pinion straight down onto the shim in one motion, and hold it until it
   cools. Remove the shim and wick a drop of thin CA glue into the joint from below. A cold
   press fit alone does not hold on the smooth shaft.
6. **Rotor.** Lower it onto the stud: the tip enters the centering bore, the hex socket
   drops over the nut (turn slightly), and the helical teeth twist into mesh.
7. **TX deck.** Glue the TX coil into its rebate, leads in the groove toward the box. Push
   the IR LED in from below (flange against the step, dab of glue). Press the top 608 into
   the hanging pocket from below until it stops on the lip.
8. Lower the deck over the rotor: the bearing slides onto the journal and the column
   spigots drop into the deck recesses. Bolt it down with 4× M3×8. Route the TX and IR
   leads into the box through the notch in its wall.
9. **Rotor head.** Hot-glue the RX coil into its rebate (glue into the three notches) with
   the leads up through the lead notch. Bend the IR receiver's pins up, press it face-down
   onto its boss over the hole, and hot-glue it.
10. Slide the head onto the shaft's double-D key and drive the M3×10 center screw (it
    self-taps; snug only).
11. Bolt the PCB on with 4× M3×6, then solder the RX coil leads and the IR receiver.
12. **Power.** Jack first (it sits under the switch): wire it, drop it into its cradle
    (front into the wall recess, back against the backstop, wires through the backstop
    slot) and zip-tie it through the tunnel in the riser. Mount the switch in the wall and
    crimp its leads. Screw the lid on (4× M3×8). `show_power` in the preview shows both.
13. **Balance** (below).

## Balancing

The LED matrix sits off-axis, so the rotor is heavy on one side. At around 1000 RPM a few
grams off-center shakes the whole machine.

1. Unpowered, lay the base on its side (rotor axis horizontal).
2. Let the rotor come to rest: the heavy side ends up at the bottom.
3. Glue M3 nuts into the head pockets on the **top** (light) side. Repeat until the rotor
   stays wherever you leave it.
4. Spin up slowly and feel for vibration; nudge the weights if needed.

## Next

Flash the firmware ([Firmware](firmware.md)) and work through [Bring-up](bring-up.md).
