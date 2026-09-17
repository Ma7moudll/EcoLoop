# EcoLoop Station V2 — Rotary Sorting Mechanism

> **One product. One domain model. One backend authority. One AI pipeline.
> Two interchangeable physical sorting mechanisms.**

Station V2 sorts waste into four fixed bins with a **single rotating chute**
driven by a stepper motor. It implements the *existing* EcoLoop
station MQTT contract (`docs/mqtt-contract.md`) and reports
`mechanism_position` — the backend, AI pipeline, and Ecolamp app are
completely unaware of which mechanism is installed.

| | Station V1 — Carriage | Station V2 — Rotary |
|---|---|---|
| Moving element | carriage travels to bin | chute rotates to bin |
| Position report | `carriage_position` (legacy) / `mechanism_position` | `mechanism_position` only |
| State machine | shared contract (`IDLE→ROUTING→MOVING→POSITIONED→READY_FOR_DEPOSIT→DETECTING→MEASURING→DEPOSIT_CONFIRMED→RESETTING`) | identical |
| Reference impl | `hardware-simulator/` (+ firmware TODO) | `hardware-simulator/rotary_simulator.py` + `firmware/rotary-v2/` |

---

## 1. Concept selection (Phase 2–3)

| Criterion | A — Rotating Chute | B — Rotating Cylinder | C — Rotary Diverter |
|---|---|---|---|
| Moving parts | 1 (chute+shaft) | 1 (heavy cylinder) | 1 (flap/cone) |
| Rotating mass | ~0.4 kg | ~1.5–2 kg | ~0.15 kg |
| Jam risk | low (open bore) | medium (carry-over between chambers) | **high** (items wedge on diverter edge) |
| Retention/cleanability | open bore, hose-accessible | sealed chambers trap liquid | debris packs at seal edge |
| Torque needed | low–moderate | high | very low |
| Precision demand | ±1° (bin mouths 200 mm wide) | ±0.5° | ±3° but seal wear |
| Manufacturability | printed + tube | lathe/wound | printed + sealing strip |
| Safety | open top visible | enclosed | pinch point at seal |
| Scalability to 6 bins | trivial (add slot) | new cylinder | new geometry |

**Selected: Concept A — rotating chute.** Lowest total jam probability and
easiest manual clearing of the three; torque requirement is comfortably
within a NEMA 17; an open bore cannot trap liquids; adding bins is a config
row. Concept B's carry-over contamination alone disqualifies it for mixed
campus waste (residual soda in cans).

## 2. Geometry (Phase 4)

All dimensions in millimeters; prototype tolerances ±0.5 mm printed,
±2 mm fabricated frame.

```
                 top view                          side view
            ┌────────────────────┐              ┌──┬─ intake funnel Ø110→80
            │   P(270°)   M(90°) │              │  ↓
            │      \     /       │           ┌──┴──────────┐
            │       \   /        │           │ CHUTE Ø80 ID│  L=160, 45° slope
            │  O(180°) X  L(0°)  │           └──────┬──────┘
            │       home ↑       │                  ↓ drop 60
            └────────────────────┘              ┌────┴────┐ bins Ø160×250
```

| Parameter | Value | Rationale |
|---|---|---|
| Positions / spacing | 4 @ **90°** | max angular separation → misrouting falls into *no* bin rather than an adjacent one; symmetric load-cell/fill-sensor layout; worst-case travel 90° via shortest path. Alternating geometries (e.g., 100/80 fan layout) were rejected: asymmetric bearing loads and non-uniform bin access outweigh marginal travel savings. |
| Chute bore (ID) | **Ø80** | passes a 500 ml PET bottle (Ø65) lying down and a crumpled can; leaves ≥7 mm radial clearance |
| Chute length | **160** | gives a continuous 45° transport slope over the 56 mm chord between adjacent outlet centers |
| Chute slope angle | **45°** | see §12 below |
| Inlet funnel | Ø110 → Ø80 | hand-size opening, funnels without bottlenecking |
| Outlet → bin rim gap | **40–60** | gravity entry without splash-out; below the jam-critical >100 mm tumble |
| Shaft | Ø8 h7 steel | 2× 624-2RS bearings, one above / one below the drive flange |
| Bin ring radius | R120 | bin Ø160 bodies clear each other by ~97 mm at 90° |
| Footprint / height | **400 × 400 × 620** | fits campus recycling footprint; bins slide out radially for emptying |

## 3. Torque calculation & motor selection (Phase 6)

Loads:
- Chute assembly (printed chute 250 g + shaft 100 g + hub 50 g) = **0.40 kg**, CoM offset from axis ≤ 30 mm (outlet lip) → static imbalance torque = 0.40 × 9.81 × 0.03 ≈ **118 mN·m worst case** (worst when imbalance arm is horizontal).
- Friction: 2 ball bearings ≈ **< 10 mN·m**.
- Waste: 0.5 kg max item riding at r = 55 mm → adds inertia, negligible static torque about the vertical axis (gravity is parallel), but include in dynamics.

Inertia: chute ring I ≈ m·r² = 0.4·0.05² = 1.0×10⁻³ kg·m²; waste I ≈ 0.5·0.055² = 1.5×10⁻³; shaft/hub ≈ 0.2×10⁻³ → **I ≈ 2.7×10⁻³ kg·m²**.

Motion profile: 90° move in ≤ 0.6 s trapezoidal → α_peak ≈ **17.5 rad/s²**, ω_peak ≈ 10.5 rad/s.

Dynamic torque = I·α ≈ 47 mN·m.
**Total required** ≈ 118 + 10 + 47 ≈ **175 mN·m**. With **SF = 2 → 350 mN·m**.

**Selected motor: NEMA 17 17HS4401S** — 0.42 N·m holding, driven at 1.2 A RMS by **TMC2209** (silent, stallGuard optional as secondary jam sensor). Available running torque ≈ 60 % of holding ≈ 250 mN·m… marginal vs 350. Therefore the spec requires running at **1.4 A peak / 1.0 A RMS with the TMC2209 in coolStep** giving ≈ 300 mN·m usable, plus the design cap `MAX_DEG_PER_SEC=300°/s` keeps α within budget. If measured margin on the prototype is < 25 %, the documented fallback is a **3.6:1 planetary (27HS gearset)** which multiplies torque ×3.6 and drops slew to 83 °/s (still a 1.08 s worst-case move, inside the 6 s timeout).

Direct drive chosen over belt: eliminates belt stretch/slip (position integrity), one less part to maintain; backlash irrelevant since position is re-referenced by homing each boot and verified optically per move.

## 4. Positioning & feedback (§8–§9)

- **Home reference**: diametric magnet on the shaft + **digital Hall latch (AH1815)** against a machined hard stop. Hall selected over limit switch (no wearing contacts, dust-immune, sealed) and optical interrupter (flag windows clog with paper dust). Repeatability with hard stop + back-off ≈ ±0.15°, far inside the ±1° need.
- **Homing sequence** (every boot, after any estop/jam recovery): seek CCW at 60°/s until Hall fires → set step counter zero → back off +3° → return to 0°. Timeout 12 s ⇒ SENSOR_ERROR state, never endless seek (§11).
- **Per-move verification**: AccelStepper target reached AND `mechanism_position()` == routed compartment, else WRONG_POSITION/JAMMED.

## 5. Angle / position model (§10)

Single calibration table (`config.h` + Python mirror `hardware/rotary.py::BinMap`):

| Bin | Compartment index | Angle |
|---|---|---|
| PLASTIC | 1 | 0° (home) |
| METAL | 2 | 90° |
| PAPER | 3 | 180° |
| OTHER | 4 | 270° |

Steps derive: `steps = Δdeg / (360 / (200 × 16 × 1.0))`. Recalibration =
edit the table (or `CAL` serial mode) — no logic changes anywhere.

## 6. Electronics & power (Phase 5, §16–§17)

```
12V/5A PSU ──fuse 5A──switch──┬──────────────────── TMC2209 VMOT (+100µF bulk)
                              │                    (motor: 17HS4401S)
                              └─buck 12→5V 3A──┬── ESP32 devkit (VIN)
                                               ├── 4× HX711 VCC (~140 mA)
                                               ├── 4× VL53L1X (~150 mA)
                                               └── station camera module
E-STOP ──in series with 12V MOTOR LEG ONLY (logic stays alive to report)
```

Budget: motor 1.4 A peak @12 V (intermittent) + logic/camera ≈ 1.2 A avg →
**12 V / 5 A (60 W)** supply gives ≈ 2× headroom. Separate logic/motor rails;
star ground at PSU; HX711 data lines kept short & away from motor cable;
stepper cable shielded, bonded at controller end.

### Wiring table (ESP32 GPIO)

| Function | Pin |
|---|---|
| STEP / DIR / ENABLE | 25 / 26 / 27 |
| Home Hall (INPUT_PULLUP, active LOW) | 34 |
| IR beam (deposit detect) | 35 |
| HX711 shared SCK | 32 |
| HX711 DOUT ×4 | 33, 35*, 36, 39 → final map: 16, 17, 36, 39 (*beam moved off 35) |
| ToF XSHUT ×4 | 4, 13, 14, 15 (addresses 0x2A–0x2D) |

> Note: exact pin table is repeated in `firmware/rotary-v2/include/config.h`
> and must be reconciled there first if changed (single source of truth).

## 7. Load cells (§14)

- 4× micro load cell **2 kg** (TAL220B class) under each bin, 3-point mount.
- 4× HX711 @ 10 SPS (deposit mode), shared SCK. Per-bin tare at boot;
  calibration factors in `config.h`.
- **Deposit weight = post − pre delta** on the routed bin during the
  operation window — matches backend expectation that `weight_grams` is the
  deposited amount, not cumulative bin weight.
- Noise filtering: median-of-3 readings + 1.5 s settle before reporting;
  `weight_stable` asserted only when Δ over the settle window < 0.3 g.

## 8. Fill level (§15)

4× **VL53L1X** ToF aimed straight down into each bin (narrow FOV ignores bin
walls, immune to bottle sheen unlike IR sonar; HC-SR04 rejected — 15° cone
sees walls in a Ø160 bin). Distance → `%fill = 1 − d/BIN_DEPTH`; bands:
OK < 75 % ≤ NEAR_FULL < 95 % ≤ FULL. Published in heartbeat/sensor telemetry;
backend/admin maps bands to "Available / Almost Full" user states.

## 9. Firmware architecture (Phase 8)

```
MQTT layer (mqtt_station.*): topics, JSON, reconnect, LWT, idempotency guard
Station FSM (station_fsm.*): shared lifecycle, illegal transitions refused
RotaryController: homing, shortest-path moves, watchdogs, e-stop
AccelStepper + TMC2209: STEP/DIR, non-blocking run()
config.h: ALL constants
```

Non-blocking `loop()`: MQTT pump → `rotary.tick()` → operation engine →
heartbeat timer. No long delays anywhere except deliberate settle waits that
yield. Safety behaviors implemented:

| Hazard | Protection |
|---|---|
| stalled motor | progress watchdog (no steps in timeout window) → JAMMED, driver disabled |
| missed home sensor | 450° seek cap → TIMEOUT |
| move outside envelope | pre-move check vs timeout budget → refuse |
| MQTT loss mid-motion | immediate `emergencyStop()`, LWT marks offline (§20) |
| duplicate route command | last-operation-id guard (§21) |
| operator hazard | E-stop cuts motor rail; software estop releases driver |

## 10. Calibration mode (§24) & manual recovery (§26)

Send `CAL\n` on USB within 5 s of boot while holding BOOT (production builds
compile with `-DCALIBRATION_NEEDS_BOOT_BTN`, making serial-only entry fail):
commands `home`, `cw <deg>`, `ccw <deg>`, `zero`, `goto <pos>`, `sensors`,
`load`, `pos`, `quit`.

Jam recovery procedure:
1. E-stop (cuts motor torque).
2. Remove front access panel (4 quarter-turn fasteners).
3. Lift chute 10 mm off the magnetic thrust coupling / or release the shaft
   collar — chute spins freely by hand.
4. Clear obstruction through the open bore (no tools reach the mechanism).
5. Re-seat collar, close panel, power-cycle → automatic re-homing.

## 11. BOM (§27) — prototype quantities, EUR estimate

### Mechanical
| Item | Spec | Qty | Purpose | € |
|---|---|---|---|---|
| Chute tube | PVC 80 mm ID × 160 mm, cut 45° both ends | 1 | transport bore | 6 |
| Chute hubs | PETG print, 3 mm walls | 2 | shaft interface | 3 |
| Funnel | PETG print, Ø110→80 × 90 tall | 1 | intake | 4 |
| Shaft | Ø8 h7 × 220 C45 steel, keyway 3 mm | 1 | drive | 7 |
| Bearings | 624-2RS | 2 | support | 4 |
| Bearing blocks | printed + M4 heat-set | 2 | mount | 3 |
| Hard stop | steel block + 3 mm shim | 1 | home reference | 2 |
| Magnet Ø4×2 N42 | diametric | 1 | Hall trigger | 1 |

### Drive
| Item | Spec | Qty | € |
|---|---|---|---|
| Stepper | 17HS4401S NEMA 17, 1.7 A, 0.42 N·m | 1 | 14 |
| Driver | TMC2209 (STEP/DIR, UART cfg) breakout | 1 | 9 |
| Fallback gearbox | 3.6:1 planetary NEMA17 | 0 (contingency) | 22 |

### Sensors
| Item | Spec | Qty | € |
|---|---|---|---|
| Load cell | TAL220B 2 kg | 4 | 32 |
| HX711 breakout | 24-bit | 4 | 8 |
| ToF | VL53L1X breakout | 4 | 48 |
| Hall | AH1815 non-latching | 1 | 1 |
| Beam | IR break-beam pair 5V | 1 | 4 |

### Control & power
| Item | Spec | Qty | € |
|---|---|---|---|
| MCU | ESP32-WROOM-32 devkit v1 | 1 | 8 |
| PSU | 12 V 5 A 60 W brick, CE | 1 | 15 |
| Buck | 12→5 V 3 A | 1 | 6 |
| Camera | existing station camera module (RV pipeline) | 1 | carried |
| Fuse holder + 5 A fuse | inline | 1 | 3 |
| E-stop | NC mushroom, 2-pole (motor leg) | 1 | 6 |
| Rocker switch | 250 V AC rated | 1 | 2 |

### Wiring / fasteners / enclosure
| Item | Spec | Qty | € |
|---|---|---|---|
| Motor cable | 4-core shielded 1 m + JST | 1 | 4 |
| Wire kit | 22 AWG silicone, ferrules | 1 | 8 |
| Frame | 2020 aluminum profile + corners | 1 lot | 25 |
| Bin ring deck | 12 mm plywood, CNC-less jigsaw cut | 1 | 8 |
| Access panel | acrylic 3 mm + quarter-turn clips | 1 | 6 |
| Fasteners | M3/M4/M5 socket + heat-sets | lot | 10 |

**Prototype total ≈ €255** (excl. camera, excl. contingency gearbox).

## 12. Waste-flow rationale (§12)

- **Bottles/cans (rigid cylinders)**: 45° slope >> 25–35° roll/sliding angles for PET on printed PETG (dry); they slide, never bridge, because bore Ø80 > 1.2× their max diagonal (Ø65).
- **Paper/cardboard**: light sheets can flutter-hang at shallow angles; at 45° with a *continuous* slope (no ledge at the outlet — outlet is the low lip of the same bore) sheets exit by combined slide+drag; the Ø110 inlet prevents two-sheet arching.
- **Irregular "other"**: worst case is a cup with handle or film. Mitigations: no internal screws (heat-set nuts outside the bore), minimum feature size inside bore = none (smooth wall), 40–60 mm short drop prevents levering across the bin gap. Film that drapes on a lip would do so in ANY mechanism — the open bore makes it visible and reachable through the access panel in seconds.
- Slopes steeper than 50° increase impact velocity at the bin (splash/bounce-out) without improving clearance; shallower than 40° risks paper hang. 45° is the documented optimum; the CAD-free prototype validates with the four material test kits in §13.

## 13. Test procedure (§29)

| Level | What | How |
|---|---|---|
| Unit | angle/steps mapping, shortest-path, jam crossing, lifecycle legality | `pytest tests/test_rotary_bin_map.py tests/test_rotary_simulator.py` |
| Simulator E2E | full deposit plans over MQTT incl. jam/wrong-position/duplicate | backend `tests/integration/test_rotary_mqtt_deposit_flow.py` |
| Hardware-in-loop | homing repeatability (50 cycles, record angle error), per-bin weight vs reference masses (20/100/500 g), fill sensor vs ruler | `CAL` mode scripts |
| System acceptance | §34 flow end-to-end with real Ecolamp app + backend | station registered `mechanism="rotary"` |

## 14. Remaining issues / next steps

- Physical fabrication + HIL validation of the torque budget (fallback gearbox specified).
- Camera module reuse decision (existing RV camera integration is mechanism-independent; unchanged here).
